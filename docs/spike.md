# Running the spike

This build is an instrument, not the app. It holds the process open, records
every candidate lock signal it can see, and writes an exportable log. It does
not schedule triggers or measure latencies — those come after this log says the
foundation holds.

## Get it on your phone

1. Open the [Actions tab](https://github.com/luca-bovelli/PhoneDown/actions),
   pick the most recent green run on `main`.
2. Download the **PhoneDown-unsigned-ipa** artifact and unzip it.
3. Sideload `PhoneDown.ipa` with SideStore.
4. Launch it once and grant **Always** location when asked. When-in-use is not
   enough — the whole point is being relaunchable while not running.

Then put it in your pocket and use your phone normally.

## What to do to it

Ordinary use answers most of it, but four things need doing deliberately:

- **Lock and unlock maybe ten times** across the day, mixing button presses with
  letting the screen time out on its own. Both routes are supposed to count as
  the same event, and this is what proves whether they do.
- **Force-quit it** — swipe it out of the app switcher — then walk a few hundred
  metres. If it comes back, resurrection works on your iOS version.
- **Reboot the phone**, unlock it, wait a few minutes, then look again.
- **Leave it overnight** without touching it, to see whether the process survives
  a long idle stretch.

Then open the app, hit the share button, and send me the JSON.

## What the Findings section means

**protectedData lag** is the number the whole spike exists to produce: how far
the public signal trails the screen actually going dark.

The *spread* decides it, not the mean. A constant offset can simply be
subtracted. A variable one is noise on a metric measured in seconds and cannot
be calibrated away.

- Spread under a second → the private Darwin key gets deleted, and the app is
  left with exactly one App Store problem instead of two.
- Spread of many seconds → the Darwin key is earning its keep.

**Lock episodes** counts how many times the signals agreed enough to be grouped.
If this is far below the number of times you actually locked the phone, some
signals aren't firing at all.

**Observation gaps** are stretches where nothing was recorded, so the process was
gone. Each is marked as a reboot or a death — uptime running backwards is the
one unambiguous fingerprint of a reboot. A gap that starts right after you
force-quit and ends when you walked somewhere is resurrection working.

## Check the event detail lines

Every Darwin event carries its raw notify state, like
`com.apple.iokit.hid.displayStatus=0`. The polarity is assumed from convention
rather than from documentation that exists, so the first real run is what
confirms it. If `screenOff` events are showing `=1`, the mapping is inverted and
that is a one-line fix.

## What is deliberately broken

- **Battery.** A continuously live process costs something. Check Settings →
  Battery after a full day; that number is one of the four things being decided.
- **Swipe-away is fatal** until a geofence fires. If you swipe it away and stay
  home all evening, it stays dead.
- **App Store.** The `audio` background mode used as a keep-alive is a guideline
  2.5.4 violation. Declared knowingly — see [`feasibility.md`](feasibility.md).
