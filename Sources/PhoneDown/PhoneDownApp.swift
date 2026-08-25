import SwiftUI
import UIKit

@main
struct PhoneDownApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            SpikeView()
                .environmentObject(delegate.coordinator)
        }
    }
}

/// Present only to see the launch options.
///
/// Whether iOS relaunched us because of a geofence, rather than because the
/// user tapped the icon, is the single most important thing this build records
/// — it is the difference between resurrection working and not existing.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let coordinator = SpikeCoordinator()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let byLocation = launchOptions?[.location] != nil
        coordinator.start(relaunchedByLocation: byLocation)
        return true
    }
}
