# PhoneDown — Full Spec

Build a native iOS app in Swift called **PhoneDown**. This spec describes *what* the app does. Choose the technical approach yourself — frameworks, APIs, persistence, architecture, background execution strategy.

If any requirement turns out to be infeasible on iOS, say so before building around it. Do not silently substitute a weaker mechanism.

---

## 1. What the app is

A reaction-time instrument for phone disengagement.

It fires unpredictable "put your phone down" interrupts throughout the day and measures how long it takes the user to actually lock the device. The trained variable is **latency between the instruction and the action** — not screen time, not app usage.

Alongside it, a declared-intent mechanism (**Hall Pass**) that lets the user suspend interruptions for legitimate phone use, at the cost of stating in writing what they need it for and how long.

The app cannot block anything. It interrupts, measures, and logs. All compliance is voluntary.

Single user. No accounts, no network, no sync. All data local to the device.

---

## 2. Build order

**The riskiest requirement is reliably detecting the device lock while the app is not in the foreground.** Everything else is ordinary app code.

Prove lock detection works on a real device before building anything else. If it can't be made reliable, the product doesn't exist in this form.

After that: trigger loop → charts → Hall Passes → widget.

---

## 3. The core loop

**Firing condition.** A scheduled trigger only fires if the device is currently unlocked and in use. If the device is locked at that moment the trigger is skipped — recorded as a skip, never deferred or re-queued. If a Hall Pass is active, the trigger is suppressed and recorded as suppressed.

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

**Never display the count of triggers remaining today.** Not in the UI, not in a widget, not in a notification. Knowing how many are left turns the end of a heavy-use day into a free pass. Historical counts are fine; today's remainder is not.

**Constraint:** iOS caps pending scheduled local notifications per app, and extras beyond the cap are dropped silently. Verify the current limit and make sure a 12-hour block at maximum rate stays under it, or schedule in smaller rolling chunks. Do not ship a rate slider whose top end silently loses triggers.

---

## 5. Hall Pass

The user's escape hatch for legitimate phone use. It converts an unplanned "I'll just check" into a declared intention.

The metaphor is exact and the naming should follow it throughout: you need a stated reason, it expires, and it makes you immune to a random check.

### Starting a pass

The user declares, before using the phone:
- an **intended duration**
- a **typed sentence** stating what they need the phone for, subject to a configurable minimum length

The sentence must be typed fresh every time. **No autofill, no suggestions, no reusing the previous entry, no picking from past reasons.** The friction is the mechanism.

While a pass is active, triggers are suppressed.

### Expiry

When the intended duration elapses, the app sends a notification telling the user their pass is up.

That notification must **not** deep-link into the app and must carry no actions. The user has to open the app themselves and check the pass off manually. The act of navigating back is part of the loop.

### Checking off

In the app, the user closes the pass with one of two choices:

- **Did it** — they accomplished what they declared
- **Didn't** — they did not

Two distinct buttons, not a single confirm. A single confirm gets tapped every time and measures nothing; the ratio between these two is the declaration-accuracy metric.

### Ending early

Checking off before the intended end time ends the pass immediately and the user becomes interruptible again. This is a deliberate trade — ending early scores well on the early-stop metric but re-exposes them to triggers.

### Unchecked passes

A pass always expires at its intended end time whether or not it was checked off. The check-in stays pending. If still unchecked after 24 hours it auto-resolves as **Didn't**.

Forgetting must never silently delete a pass from the data.

### Recorded per pass

Start time, intended end time, actual check-off time, the reason sentence, and the did/didn't outcome.

---

## 6. Metrics

### Primary

**Phone-down latency** — notification delivery to device lock. Lower is better. The headline number of the whole app.

### Hall Pass metrics

**Pass length** — check-off time minus start time. Lower is better. This is the outcome; the two below decompose it.

**Intended pass length** — intended end minus start. Lower is better. This is what makes padding visible: giving yourself twelve hours is not an achievement.

**Early stop** — intended end minus check-off. Higher is better. Present three averages so they can be read separately:
- across all passes
- across negative values only (overruns)
- across positive values only (genuine early stops)

Also present early stop **as a proportion of intended length**, not only as an absolute delta. Absolute deltas reward padding — declare 60 minutes, finish in 10, and the delta looks excellent while intended length quietly rises. The ratio doesn't have that hole.

**Declaration accuracy** — proportion of checked-off passes marked *Did it*.

### Derived

**Failure rate** — proportion of latencies above a user-set threshold, expressed as failures per day, rolling.

**Triggers fired / skipped / suppressed per day** — fired, skipped because the phone was locked, suppressed because a pass was active. Three separate series.

**Hall Pass minutes per day.**

### Rolling windows

**Defined in days**, not in sample counts. The user reads trends in days; sample density is an implementation detail that shouldn't leak into how a trend is expressed.

Each chart carries its own window size, inheriting a global default until overridden. Mark a chart visibly when its window differs from the default, so two charts are never misread as covering the same span.

---

## 7. Screens

Visual language follows the iOS Settings and Screen Time pages: grouped cards on a dark background, dividers, disclosure rows, large navigation titles. Wireframes are provided as images — follow their structure.

**Chart previews are never tappable.** A preview is a preview; navigation happens through the labelled disclosure row beneath it, exactly as in Screen Time.

**Settings live next to the data they affect**, on the relevant detail page — not gathered into one global settings screen.

### Root

Large title "PhoneDown". Profile icon top right, opening a dropdown menu containing **Settings** and **Log out**. No section header above the first card, matching Settings and Screen Time convention.

The profile icon and the Log out row are intentional even though this build has no accounts — the menu is where auth will live in a later release, and the shape is being fixed now. Log out is present and inert in this build. See §12.

1. **PhoneDowns card** — headline number in large type (rolling average latency) with its trend delta, scatterplot preview below it, divider, then a **View Details** disclosure row. A bare scatterplot doesn't parse at a glance; the number carries the card.

2. **Hall Passes section** — a state-dependent card (see below), divider, then a **View Details** disclosure row.

3. **More Stats** — a grid of small preview cards for secondary metrics, each navigating to its own detail page. One of these is the auto-selected trend card (see §8).

### Hall Pass card — three states

**Idle.** Ring unfilled and grey, ticket glyph dimmed with a play symbol over it. Primary affordance: start a pass. One line of context beneath — last pass, or today's total.

**Active.** Ring filled and counting down, ticket glyph in accent colour. Remaining time as the largest element. **The reason sentence shown verbatim underneath** — reading your own stated reason back while the clock runs is most of the mechanism. Plus an *End now* affordance.

**Pending check-off.** Pass expired, not yet resolved. Ring outlined, exclamation glyph. Shows the reason sentence and the two buttons, *Did it* and *Didn't*. This state needs visual urgency — tinted background and an app icon badge — because an unchecked pass is a hole in the data.

### PhoneDowns detail

Navigation title "Your PhoneDowns", back chevron.

- Segmented control: 7 Days / 30 Days / 6 Months
- Large scatterplot of individual latencies over the period:
  - points above the fail threshold in red
  - rolling average line overlaid
  - rolling failure-frequency line using the same window
- Below the divider, in the same card: **Rolling Window Size**
- Separate card of settings belonging to this metric: **Hourly Triggers**, **Cooldown**, **Fail Threshold**
- **More Stats** grid at the bottom

The fail threshold is a live control, not a constant. Where the line sits is a judgement the user makes while reading the data, so moving it must recolour the points and recompute the failure-rate line together.

### Hall Passes detail

Navigation title "Hall Passes", back chevron.

- Segmented control: 7 Days / 30 Days / 6 Months
- Chart of pass metrics over the period
- Below the divider: **Rolling Window Size**
- Separate settings card: **Min Reason Length**, **History**, **Archive**
- **More Stats** grid at the bottom

### History

Browsable list of every pass: the reason sentence, start time, intended end, actual check-off, and outcome.

This log is as valuable as any chart — it is a record of stated intent against actual behaviour, and it is the only place the sentences can be read back in sequence.

### Sub-stat detail

Same layout, one chart, its own **Rolling Window Size** row, no additional settings.

### Empty states

Use the system's standard empty-state view for any chart with no data yet, not an empty plot.

### Numerics

Any live-updating number — stopwatches, counters, running averages — uses fixed-width digits so figures don't jitter as they change.

---

## 8. Auto-selected trend

One card in the **More Stats** grid surfaces whichever metric is currently most interesting, meaning it is showing the largest movement.

**Selection rule:** the metric with the largest standardized change between the current rolling window and the immediately preceding one. Apply a cooldown so the same metric cannot surface on consecutive days.

The card shows the metric's own name, not a generic label. If the app picks early stops, the card says Early Stops.

---

## 9. Lock screen widget

A widget to start a Hall Pass quickly.

**It navigates to the declaration screen — it does not start a pass.** One tap from the lock screen straight into an active pass would delete the typed sentence, which is the entire mechanism. The widget's job is to remove navigation friction, not declaration friction.

Tapping opens the app directly at the duration picker and sentence field.

When a pass is active, the widget shows remaining time instead. When one is pending check-off, it shows that.

---

## 10. Debug harness

Ships in development builds. Real triggers are random and rare, charts are empty for weeks, and the risky mechanism only manifests when the app isn't in the foreground — so none of this is testable without it.

A **Debug** section on the root screen.

### Triggering

- **Fire trigger now** — a real intervention immediately: notification, Dynamic Island, measurement, cooldown. Identical to a scheduled trigger in every respect.
- **Fire trigger in 10s** — same, delayed, so the app can be backgrounded first. This is the only way to test the realistic case where the trigger arrives while the user is in another app.
- **Cooldown override** — set cooldown to a few seconds so the unlock-early re-trigger loop can be exercised in a minute instead of half an hour.

### Schedule inspection

- **Pending schedule** — all upcoming generated trigger times with their block.
- **Regenerate schedule** — discard and redraw the current block.
- **Rate preview** — for the current rate, generate a day of draws and show the times and gap distribution without scheduling them. Lets the rate be tuned by inspection rather than by waiting a week.

### Hall Pass

- **Expire active pass now** — jump straight to the pending check-off state.
- **Create backdated passes** — synthesise completed passes with varied outcomes so the metrics and History have content.

### Event log

Append-only, timestamped, viewable in-app and exportable:

- block generated, with the times drawn
- trigger due / fired / skipped / suppressed, and why
- notification delivered
- device locked / unlocked
- cooldown started / completed / broken
- latency recorded
- pass started / expired / checked off / auto-resolved
- app launched, backgrounded, terminated, relaunched

**This log is the acceptance test for the risky requirement.** CI cannot verify that lock detection works while the app is backgrounded — only a real device can. Verification is: fire a delayed trigger, switch to another app, lock the phone, and check whether a lock event was recorded with a correct timestamp.

### Data

- **Seed synthetic history** — N days of plausible latencies, passes, and daily aggregates, so every chart, rolling average, threshold colouring and empty state can be exercised immediately. Include a slowly improving trend and a realistic tail, since the charts exist to reveal exactly that.
- **Clear all data**, with confirmation.
- **Export** — all recorded data plus the event log as JSON via the share sheet.

### State display

Optional overlay showing current state: scheduling active, next trigger time, intervention in progress, cooldown remaining, pass status.

---

## 11. Build and test

**There is no local Mac. GitHub Actions on macOS runners is the only build environment.** Structure the project accordingly.

- Builds produce an **unsigned IPA** as a workflow artifact, signed on-device by SideStore. CI never handles certificates.
- Public repository, so runner minutes are unmetered.
- **Snapshot tests render SwiftUI views to PNGs and upload them as artifacts.** This is the only way to see the UI at all. Cover every screen, all three Hall Pass card states, every chart state including empty, the widget, and every Dynamic Island presentation state. Treat this as a primary deliverable — without it the project is unbuildable.
- **Unit tests for the scheduler:** draw distribution across a block, block refill at boundaries, skip behaviour when locked, suppression during a pass, cooldown re-trigger logic, schedule persistence across simulated termination.
- **Unit tests for the statistics:** rolling averages, the three early-stop aggregates and the ratio form, declaration accuracy, failure-rate calculation, threshold behaviour, the trend selection rule and its cooldown, aggregation over each time period.
- **Unit tests for Hall Pass lifecycle:** expiry without check-off, 24-hour auto-resolve, early check-off ending suppression immediately.

Every iteration is a CI round trip, so work test-first and keep the build green. A broken build costs ten minutes, not ten seconds.

---

## 12. Out of scope

Deliberately excluded. Do not build these, and do not leave placeholders for them.

- **Accounts and auth.** Planned for an eventual App Store release, not built here. Nothing in this build stores, requires, or assumes a user identity, and no data is keyed to one.

  The exception is the root screen's profile icon and its dropdown, which ship as described in §7. **Log out is a visible, inert row** — it performs no action. Build the menu as UI only: no auth flows, no session state, no sign-in screens, no credential storage, no stubbed service layer waiting to be filled in. The intent is to fix the navigation shape now so adding auth later doesn't move anything the user has learned.
- App blocking or shielding of any kind
- Screen time or usage tracking
- Sync, sharing, streaks, gamification, social features
- Onboarding flows
- Any network calls whatsoever
