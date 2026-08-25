# PhoneDown

A reaction-time instrument for phone disengagement. It fires unpredictable "put
your phone down" interrupts and measures how long it takes to actually put the
phone down. It blocks nothing. All compliance is voluntary.

Single user, no accounts, no network, no sync. All data local.

## Status

MVP in progress. See [`phonedown-mvp-spec.md`](phonedown-mvp-spec.md) for scope
and [`phonedown-full-spec.md`](phonedown-full-spec.md) for where it is going.

**Read [`docs/feasibility.md`](docs/feasibility.md) first.** The core mechanism
runs into a hard iOS boundary, and the architecture is shaped entirely by which
side of that boundary you choose to stand on. That document records what was
checked and what each option actually costs.

## What is measured

Follow-through, not reaction time.

If you lock the phone and pick it back up before the cooldown elapses, the
re-interrupt is another segment on the **same** intervention, not a new sample.
Penalty time accumulates until you manage one clean cooldown. Three numbers come
out of it:

- `accumulatedLatency` — total time spent on the phone after being told not to
  be. The headline. Locked gaps are excluded; they are time genuinely spent off
  the phone and are not charged to you.
- `wallClockSpan` — first interrupt to final close, gaps included.
- `relapseCount` — how many times you came back before it stuck.

## Layout

```
Sources/PhoneDownKit/     pure Foundation domain — no UIKit, no SwiftUI
Sources/PhoneDown/        the app
Sources/PhoneDownMonitor/ DeviceActivityMonitor extension
Tests/PhoneDownKitTests/  domain tests, run natively on CI in seconds
docs/                     feasibility findings and decisions
```

`PhoneDownKit` is a standalone Swift package with no platform dependencies, so
the whole domain — scheduling, accumulation, statistics — compiles and tests on
the CI host without booting a simulator. There is no local Mac; every iteration
is a CI round trip, so the fast lane is worth the separation.

## Build

CI on GitHub Actions macOS runners is the only build environment. Builds produce
an unsigned IPA as a workflow artifact, signed on-device by SideStore. CI never
handles certificates.

```sh
swift test          # domain tests, no simulator needed
xcodegen generate   # produces PhoneDown.xcodeproj (not checked in)
```
