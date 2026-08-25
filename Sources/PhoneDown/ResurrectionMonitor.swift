import CoreLocation
import PhoneDownKit

/// Brings the process back after it dies.
///
/// A swipe-away kills the audio session along with everything else, and iOS
/// treats force-quit as an instruction not to run again. Region monitoring is
/// the single documented exception: the geofence lives in the location daemon
/// rather than in our process, so it survives us and relaunches the app on a
/// boundary crossing — after a force-quit and after a reboot.
///
/// It is not free of holes. Nothing fires if the phone never moves, so a
/// swipe-away followed by an evening at home stays dark. And there are reports
/// that this stopped working on iOS 26, which is one of the things the spike
/// exists to settle.
///
/// Uses the pre-iOS-17 monitoring API on purpose: the relaunch-after-force-quit
/// behaviour is documented for this one, and `CLMonitor` is the fallback to try
/// if the log shows nothing coming back.
final class ResurrectionMonitor: NSObject {
    private static let regionIdentifier = "phonedown.resurrection"

    /// Large enough that ordinary indoor drift doesn't churn the region, small
    /// enough that leaving the building crosses it.
    private static let radius: CLLocationDistance = 150

    private let manager = CLLocationManager()
    private let log: EventLog

    init(log: EventLog) {
        self.log = log
        super.init()
        manager.delegate = self
        // Deliberately not setting allowsBackgroundLocationUpdates: geofences
        // don't need it, and without it there is no persistent location
        // indicator in the status bar.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            refreshRegion()
        case .authorizedWhenInUse:
            // When-in-use is not enough. The app has to be relaunchable while
            // it isn't running, which is the entire point of this class.
            manager.requestAlwaysAuthorization()
        default:
            log.append(
                .regionMonitoringFailed,
                detail: "authorization=\(manager.authorizationStatus.rawValue)"
            )
        }
    }

    /// Re-centre on wherever we are now. Called on every launch so the geofence
    /// follows the user instead of pinning to wherever they first ran the app.
    private func refreshRegion() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        manager.requestLocation()
    }

    private func monitor(around coordinate: CLLocationCoordinate2D) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            log.append(.regionMonitoringFailed, detail: "monitoring unavailable")
            return
        }
        let region = CLCircularRegion(
            center: coordinate,
            radius: Self.radius,
            identifier: Self.regionIdentifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
        log.append(.regionMonitoringStarted, detail: "radius=\(Self.radius)")
    }
}

extension ResurrectionMonitor: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            refreshRegion()
        } else {
            log.append(
                .regionMonitoringFailed,
                detail: "authorization=\(manager.authorizationStatus.rawValue)"
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        monitor(around: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log.append(.regionBoundaryCrossed, detail: "exit \(region.identifier)")
        // Crossing out means the old centre is stale; follow the user.
        refreshRegion()
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log.append(.regionBoundaryCrossed, detail: "enter \(region.identifier)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.append(.regionMonitoringFailed, detail: String(describing: error))
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        log.append(.regionMonitoringFailed, detail: String(describing: error))
    }
}
