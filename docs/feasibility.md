# Lock detection on iOS — what is actually possible

Written before the app, because the whole product rests on one mechanism and it
is worth knowing exactly how far that mechanism goes.

## The question

Measure the interval between "put your phone down" and the phone actually being
put down, to second resolution, without the app being open.

## The answer

**Second resolution requires the app's process to be alive at the moment the
device locks. There is no way around this.** Every other constraint follows from
that one fact.

## What was checked, and what each gives

| Mechanism | Wakes the app? | Precision | Verdict |
|---|---|---|---|
| `UNUserNotificationCenter` local notification | No — the system displays it, the app is not involved | Delivery time is exact | Fires reliably after force-quit and reboot. **The interrupt never needs the app.** |
| `protectedDataWillBecomeUnavailable` | No — it is a callback into a *running* process | Seconds, if running | Not a system log. Nothing to read back later. |
| Darwin `com.apple.iokit.hid.displayStatus` | No | Sub-second, if running | Private. Not in `notify_keys.h`. App Store disqualifier. |
| `BGTaskScheduler` | Opportunistically | None — `earliestBeginDate` is a floor, not a schedule | Never runs after force-quit. |
| `BGContinuedProcessingTask` (iOS 26) | No | — | Requires foreground user initiation and a completing goal. |
| Silent push | Yes | Throttled to ~1–2/hour | Needs network and a server. Dead after force-quit. |
| Region monitoring / SLC | **Yes**, even after force-quit and reboot | Geographic, not timed | Only region monitoring is reliable for relaunch; SLC is not. |
| HealthKit background delivery | Yes | Data-arrival timing | Irregular, uncontrollable cadence. |
| Shortcuts automations | n/a | — | No lock/unlock trigger exists. |
| CoreMotion history (`CMPedometer`, `CMSensorRecorder`) | No — the system records for you | 50 Hz, 3 days | Records *motion*, not screen state. Stationary ≠ locked. |
| `DeviceActivityMonitor` (Family Controls) | Wakes an **extension**, never the app | 5-minute thresholds, 5–10 min observed variance | The only scheduled wakeup on the platform. |
| `DeviceActivityReport` | n/a | Has real timestamps | Sandbox is sealed by design; the data cannot reach the app. |

Two boundaries worth stating plainly, because they close off whole families of
otherwise-reasonable ideas:

- **Extensions cannot launch their host app.** A `DeviceActivityMonitor` waking
  up does not wake PhoneDown. It is a separate short-lived process with its own
  small memory budget.
- **iOS has no timed app wakeup at any precision.** Not early, not late, not at
  all. There is nothing to schedule and therefore nothing to pre-fire.

## The keep-alive question

Staying alive in the background needs a background mode. The audio route —
holding a silent `AVAudioSession` open — works, and is a documented App Store
rejection under guideline 2.5.4: background audio must play audible content, and
using the mode for another purpose is the exact thing the guideline names.
Location has the same shape of problem unless the app genuinely uses location,
which this one does not.

So: continuous background execution is available, and it is sideload-only.

## The trade

Four constraints. Any three:

- **App Store legal**
- **No privileged entitlement**
- **No running process**
- **Second resolution**

| Drop | You get | Cost |
|---|---|---|
| No running process | Legal, free, second-precise | Needs the user to open the app; interrupts they ignore go unmeasured |
| No entitlement | Legal, nothing running | Family Controls approval; resolution falls to ~5 minutes |
| App Store legal | Everything, unconditionally | Sideload only, forever |

## What this repo builds

The firing gate and the measurement are separate concerns and sit behind
separate protocols, because they have different answers.

- **Firing gate.** `DeviceActivityMonitor.intervalDidStart` fires at a scheduled
  time *only when the device is actually in use*. That is the spec's firing
  condition handed to the system: if the phone sits locked, no callback, no
  notification, and the skip records itself. No keep-alive, no reboot gap, and
  no 4am buzz for a trigger nobody saw.
- **Measurement, precise path.** The user taps the notification, the app comes to
  the foreground with the stopwatch running, and the lock is observed exactly
  because the process is alive and frontmost.
- **Measurement, fallback path.** No tap: the threshold ladder bounds the answer
  and the interrupt is recorded as *ignored*, which is its own metric and
  arguably the most informative one in the set.

`LockPrecision` carries `.exact`, `.bracketed` and `.unobserved` through to
storage so that a soft measurement is never averaged into the headline as if it
were a hard one.
