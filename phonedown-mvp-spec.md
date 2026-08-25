# PhoneDown — MVP Spec

Build a native iOS app in Swift called **PhoneDown**. This spec describes *what* the app does. Choose the technical approach yourself — frameworks, APIs, persistence, architecture, background execution strategy.

If any requirement turns out to be infeasible on iOS, say so before building around it. Do not silently substitute a weaker mechanism.

---

## 1. What the app is

A reaction-time instrument for phone disengagement.

It fires unpredictable "put your phone down" interrupts throughout the day and measures how long it takes the user to actually lock the device. The trained variable is **latency between the instruction and the action** — not screen time, not app usage.

The app cannot block anything. It interrupts, measures, and logs. All compliance is voluntary.

Single user. No accounts, no network, no sync. All data local.

---

## 2. MVP scope

**In:** the trigger loop, latency measurement, cooldown, the scatterplot, and a debug harness that makes all of it testable on demand.

**Explicitly out of this build:**
- Hall Passes (declared sessions) and everything derived from them
- Auth, profile menu, settings-behind-a-person-icon
- Lock screen widget
- Auto-selected "interesting" secondary stat

Build order matters. **The riskiest requirement is reliably detecting the device lock while the app is not in the foreground.** Everything else is ordinary app code. Prove lock detection works on a real device before building the UI around it — if it can't be made reliable, the product doesn't exist in this form and I need to know in week one.

---

## 3. Core loop

**Firing condition.** A scheduled trigger only fires if the device is currently unlocked and in use. If the device is locked at that moment, the trigger is skipped — recorded as a skip, never deferred or re-queued.

**Intervention.** When a trigger fires:
- A notification is delivered telling the user to put the phone down.
- A live stopwatch appears in the Dynamic Island, counting up from the moment of delivery.
- The stopwatch runs until the device is locked.

**Measurement.** Latency is the interval from notification delivery to device lock.

The lock may be user-initiated or the screen timing out on its own. **Both count.** The measured quantity is "how long until the phone stopped being used," and both routes satisfy it. Do not attempt to distinguish them.

**Confirmation.** On lock, the Dynamic Island element shows a success state with the recorded time.

**Cooldown.** After locking, the device must stay locked continuously for the cooldown period — configurable, default 5 minutes. Unlocking early re-triggers the intervention immediately: new notification, new stopwatch, new latency recorded, cooldown restarts. The cycle closes only after one uninterrupted cooldown period.

Five minutes is the default because that is long enough to break the scroll loop and short enough that avoiding the system isn't worth it.

---

## 4. Scheduling

**Batch generation.** Trigger times are generated ahead of time in blocks and persisted, not drawn one-at-a-time as each fires. The pending schedule must be a durable, inspectable list that survives app termination and device reboot.

- Block length: **12 hours**, refilled on fixed clock boundaries. Generate the next block before the current one expires so the schedule never runs dry.
- Times within a block are drawn **independently and uniformly** across the block. No spacing constraints, no even distribution, no minimum gap. Clustering is expected and correct — three triggers in twenty minutes followed by nothing for three hours is a valid day.

**Rate setting: triggers per hour.** The user sets a rate; a block draws `block_hours × rate` times. Default 2/hour.

Control is a **slider with a step value**, range 0.5–4.0, step 0.25. Not a stepper.

**Draw across the full 24 hours.** Do not restrict to waking hours. Draws landing while the phone is locked cost nothing, and a trigger that catches genuine 4am scrolling is the highest-value trigger in the set.

Consequence to surface in the UI: the rate is *draws* per hour, not *interruptions* per hour — most draws land while the phone is locked and are skipped. Show the recent actual fired-per-day figure next to the setting so the user tunes against reality.

**Constraint:** iOS caps pending scheduled local notifications per app. Extras beyond the cap are dropped silently. Verify the current limit and make sure a 12-hour block at maximum rate stays under it, or schedule in smaller rolling chunks. Do not ship a rate slider whose top end silently loses triggers.

---

## 5. Metrics

**Phone-down latency** — notification delivery to device lock. Lower is better. The headline number.

**Failure rate** — proportion of latencies above a user-set threshold, expressed as failures per day, rolling.

**Triggers fired vs. skipped per day** — how many draws fired versus were skipped because the phone was already locked.

**Rolling averages are defined in days**, not in sample counts. Each chart carries its own window size, inheriting a global default until overridden; mark a chart visibly when its window differs from the default so two charts are never misread as covering the same span.

---

## 6. Screens

Model the visual language on the iOS Settings and Screen Time pages: grouped cards on a dark background, dividers, disclosure rows, large navigation titles. Wireframes are provided as images — follow their structure.

### Root

Large title "PhoneDown". No section header above the first card (matches Settings/Screen Time convention). No toolbar or profile button in this build.

1. **Chart preview card.** A scatterplot preview with a divider and a "View Details" disclosure row beneath it. **The chart itself is not tappable** — it is a preview, exactly as in Screen Time. Navigation happens through the row.

   Above the plot, show the headline number in large type — rolling average latency, with its trend delta. A bare scatterplot doesn't parse at a glance.

2. **More Stats** section — a grid of small preview cards for the secondary metrics, each navigating to its own detail page.

3. **Debug** section — see below.

### PhoneDowns detail

Navigation title "Your PhoneDowns", back chevron.

- Segmented control at top: 7 Days / 30 Days / 6 Months
- Large scatterplot of individual latencies over the selected period
  - points above the fail threshold drawn in red
  - rolling average line overlaid
  - rolling failure-frequency line using the same window
- Below the divider, in the same card: **Rolling Window Size** row
- Separate card with the settings that belong to this metric: **Hourly Triggers**, **Cooldown**, **Fail Threshold**
- **More Stats** grid at the bottom

Settings live next to the data they affect, not in a global settings screen.

### Sub-stat detail

Same layout, one chart, its own Rolling Window Size row, no additional settings.

### Empty states

Use the system's standard empty-state view for any chart with no data yet, not an empty plot.

### Numerics

Any live-updating number — stopwatches, counters, running averages — uses fixed-width digits so figures don't jitter as they change.

---

## 7. Debug harness

**This is a first-class deliverable, not an afterthought.** Without it the app is untestable: real triggers are random and rare, the charts are empty for weeks, and the one risky mechanism only manifests when the app isn't in the foreground.

A **Debug** section on the root screen, always visible in this build.

### Triggering

- **Fire trigger now** — runs a real intervention immediately: notification, Dynamic Island, latency measurement, cooldown. Identical to a scheduled trigger in every respect.
- **Fire trigger in 10s** — same, delayed, so the app can be backgrounded first. This is the only way to test the realistic case where the trigger arrives while the user is in another app.
- **Cooldown override** — temporarily set cooldown to a few seconds so the unlock-early re-trigger loop can be exercised in a minute instead of half an hour.

### Schedule inspection

- **Pending schedule** — a list of all upcoming generated trigger times, with the block they belong to.
- **Regenerate schedule** — discard and redraw the current block.
- **Rate preview** — for the current rate setting, generate a day's worth of draws and display the resulting times and gap distribution without scheduling them. Lets the rate be tuned by inspection rather than by waiting a week.

### Event log

An append-only, timestamped log of every meaningful event, viewable in-app and exportable:

- block generated, with the times drawn
- trigger due / fired / skipped (and why skipped)
- notification delivered
- device locked / unlocked
- cooldown started / completed / broken
- latency recorded
- app launched, backgrounded, terminated, relaunched

**This log is the acceptance test for the risky requirement.** CI cannot verify that lock detection works while the app is backgrounded — only a real device can. The log is how that gets verified: fire a delayed trigger, switch to another app, lock the phone, and check whether a lock event was recorded with a correct timestamp.

### Data

- **Seed synthetic history** — generate N days of plausible latencies and daily aggregates so every chart, rolling average, threshold colouring, and empty state can be exercised immediately. Include a slowly improving trend and a realistic tail, since the charts are meant to reveal exactly that.
- **Clear all data** — with confirmation.
- **Export** — dump all recorded data and the event log as JSON via the share sheet, so it can be pulled off the device and analysed elsewhere.

### State display

An optional overlay or banner showing current state: scheduling active or not, next trigger time, intervention in progress, cooldown remaining.

---

## 8. Build and test

**There is no local Mac. GitHub Actions on macOS runners is the only build environment.** Structure the project accordingly.

- Builds produce an **unsigned IPA** as a workflow artifact, signed on-device by SideStore. CI never handles certificates.
- Public repository, so runner minutes are unmetered.
- **Snapshot tests render SwiftUI views to PNGs and upload them as artifacts.** This is the only way to see the UI at all. Cover every screen, every chart state including empty, and every Dynamic Island presentation state. Treat this as a primary deliverable — without it the project is unbuildable.
- **Unit tests for the scheduler:** draw distribution across a block, block refill at boundaries, skip behaviour when locked, cooldown re-trigger logic, schedule persistence across simulated termination.
- **Unit tests for the statistics:** rolling averages, failure-rate calculation, threshold behaviour, aggregation over each time period.

Every iteration is a CI round trip, so work test-first and keep the build green. A broken build costs ten minutes, not ten seconds.

---

## 9. Non-goals

- App blocking or shielding of any kind
- Screen time or usage tracking
- Accounts, sync, sharing, streaks, gamification
- Onboarding flows
- Any network calls whatsoever
