# Phase status

| Phase | Scope | Status |
|---|---|---|
| 1 | Foundation and core map | **Done** (2026-11-13), approved |
| 2 | Trains and passenger simulation | **Done** (2026-11-13), approved (user started Phase 3) |
| 3 | Resources, scoring, game over (Endless prototype) | **Done** (2026-11-13), approved (user asked for an easier early game, then Phase 4) |
| 4 | Strategic mechanics | **Done** (2026-11-13), approved (user started Phase 5) |
| 5 | Campaign and Challenge modes | **Done** (2026-11-17), approved (user started Phase 6) |
| 6 | Visual and audio polish | **Done** (2026-11-17), plus Vietnamese (user request), approved (user started Phase 7) |
| 7 | Testing and optimisation | **Done** (2026-11-17): release candidate, see [TEST_REPORT.md](TEST_REPORT.md) |
| Part 2, batch 1 | Campaign levels 9–10: stadium and airport | **Done** (2026-11-18), approved |
| Part 2, batch 2 | Levels 11–12: drawbridge, new district | **Done** (2026-11-18), approved |
| Part 2, batch 3 | Levels 13–14: hills (new map type), megacity finale, rewards | Planned |

## Campaign part 2 — batch 2 (levels 11–12)

- **Drawbridges** (`Model/Drawbridges.swift`, `Engine/BridgeManager.swift`, `GameConfiguration.drawbridges`).
  A fixed timetable: from 25 s into the first week, every 40 s every bridge (a segment that has to cross
  water) is up for 16 s. A train about to cross waits at the station before it (people can still board);
  a train already on the bridge carries on. Decks turn amber 10 s before a lift and red during it; the HUD
  counts down. Level 11 *Drawbridge* (Bridgewater, chosen because its river runs through the city: the auto
  player needs three crossings): pass 240 / 74% efficiency / 4,400 points.
- **New districts** (`DistrictManager`, `GameConfiguration.newDistricts`). From week 2, once a week: a mapped
  neighbourhood with no stations, about a short line away from the network, is announced 25 s ahead (dashed
  circle on the map, HUD countdown), then 4 stations open inside it. With none left it opens just beyond
  the city's edge. Ordinary stations appear more slowly in this level (every 32 s). Level 12 *New District*
  (Newbury Fields): pass 320 / 28 stations on lines / 7,000 points.
- Both are off everywhere else, and their state is optional in saves, as in batch 1.

## Campaign part 2 — batch 1 (levels 9–10)

Six new levels are planned, each adding one mechanic; two per batch, approved one batch at a time.

- **Venues** (`Model/Venues.swift`, `Engine/VenueManager.swift`), switched on per level by
  `GameConfiguration.venues`. Off everywhere else: the first eight levels, the challenges and Endless play
  exactly as before (the scenario report is unchanged).
  - **Stadium** (level 9, *Match Day*): the 5th station. Quiet between matches (×0.5 demand), +16 room. Every
    Wednesday and Saturday at full time, 12 fans leave over 12 s, heading anywhere. The HUD shows the next
    match, then a 20 s countdown, then the crowd leaving; the stadium gets the event ring.
  - **Airport** (level 10, *Airport*): the 6th station, placed beyond the edge of town. Busy (×2 demand),
    +6 room. Its passengers are travellers: one who waits 45 s on a platform gives up and takes a taxi
    (shown as "−N 🚕"); one delivered within 60 s of landing earns +10.
- **New objectives:** fans delivered, travellers delivered on time.
- **Passenger conservation** now reads: spawned = delivered + in the network + gave up.
- **Saves:** every new field is optional, so sessions saved by 1.0.1 still load.
- **Targets** (auto player, 12 variants): Match Day pass 220 / 36 fans / survive to the end of week 4 (only
  with a bigger budget, so it needs preparing for matches); Airport pass 260 / 35 travellers on time /
  6,400 points.
- Also fixed: special-station descriptions on the station card weren't translated into Vietnamese.

## Phase 7 — testing and optimisation

Full results in [TEST_REPORT.md](TEST_REPORT.md). In short:

- **New tests:**
  - pathfinding properties on 40 random networks, checked against an independent reachability search
  - save and load: old progress files, damaged files, resuming mid-event
  - 30-week runs on every difficulty that check every invariant each simulated second
  - a per-system cost breakdown of a full city

  113 tests in total, all passing.
- **Optimisations from profiling:**
  - HUD tunnel count cached
  - per-step station table for trains; stop rules only when express or events exist
  - train renderer position table
  - music synthesiser using a sine table and fixed buffers: 3.5 % → 0.46 % of a core

  A full city simulates in 0.03 ms per step (Release).
- **Memory:** stable node count; no leaks in game code (the only reports are inside Apple's audio framework).
- **Fixes:**
  - depot credit count squeezed out of a crowded HUD
  - in-game HUD too wide for an iPad in portrait (it now wraps to two rows)
  - city names wrapping on the phone Endless picker
  - tour groups bypassing the queue safety cap
  - "best efficiency" showing 0 % for old records
- **Screen sizes:** iPhone 18 Pro, iPhone 17e, iPad mini and the smallest Mac window (900×600), in English and Vietnamese.
- **Debug tools added:**
  - `-MetroDemoStress`: a full city for profiling
  - `-MetroScreen <campaign|challenges|endless|statistics|settings>`
  - `-MetroWindowSize 900x600` (macOS)
  - `METRO_LANG=vi|en`

## Phase 6 — what was built

- **Sound effects (`AudioManager`, `Feedback`):** 12 sounds from Kenney Interface Sounds (CC0), converted from Ogg to mono WAV (280 KB). Events covered:
  - building a line, deleting one, a new station
  - a delivery (quiet and throttled), a purchase or upgrade
  - a station starting to overcrowd, an event warning
  - a new week, game over, a level complete
  - taps and toggles

  On iPhone the matching haptics play too. The audio session is "ambient": it mixes with the player's music and respects the silent switch.
- **Generative music (`MusicSynth`):** original music synthesised in real time (no files), on the real-time audio thread without allocations:
  - a slow Cmaj9–Am7–Fmaj7–G6 pad loop, soft bass, and pentatonic plucks
  - calm in menus, a little busier in play, faster with more notes in rush hour
  - quieter while paused or after the end
- **Sound settings:** music volume, effects volume and mute (saved with progress).
- **Visual themes:** Metropolitan, Coastal (sand, turquoise water), Old Town (warm stone, heritage colours) and Industrial (steel, signal colours). They unlock after campaign levels 2, 4 and 6. A picker with previews is in Settings.
- **Animations and feedback:**
  - passengers shown as small dots travelling between the platform and the train when they get on or off
  - the train bounces slightly at the same time
  - a rising "+N" score label after deliveries (summed per station)
  - a glow along a newly built line
- **Off-screen alerts:** an arrow at the screen edge points to any overcrowding station outside the view (amber, then red and pulsing).
- **Menus:** screens slide in from the right and back, the main menu buttons appear one after another, and the game opens with a soft zoom.

## Vietnamese (user request, 2026-11-17)

- **Design:** `UI/L10n.swift` shadows `Text`, `Button`, `Label`, `.help` and `.accessibilityLabel` so every string is looked up. Sentences built in code go through `tr("Deliver \(n) passengers")` (key "Deliver %@ passengers"; translations may reorder with `%1$@`). The table is `Resources/Localization/vi.json` (359 entries): menus, cards, the depot, notices, errors, objectives, and all campaign and challenge briefings.
- **Switching:** an **EN | VI** switch on the main menu (also in Settings), instant, saved with progress. The first launch follows the device language. The macOS menu bar stays English (no `.lproj`).
- **Font:** Outfit has no Vietnamese letters (46 of 52 missing), so in Vietnamese the interface uses the rounded system font, which has them all.
- `Scripts/l10n.py check` lists strings without a translation (0 now); `Scripts/l10n.py wrap` puts `tr()` around new sentences. `METRO_LANG=vi` forces Vietnamese for screenshots.

## Phase 5 — what was built

- **Difficulty levels (`Difficulty`, `GameConfiguration.make`):** Easy, Normal and Hard differ in much more than passenger rate:

  | | Easy | Normal | Hard |
  |---|---|---|---|
  | Starting trains | 4 | 3 | 3 |
  | Weekly credits | 4 | 3 | 3 (smaller bonus) |
  | Tunnels | 4 | 3 | 2 |
  | Station room | 14 | 12 | 10 |
  | Overcrowding timer | 60 s | 50 s | 40 s |
  | Rare shapes from | 12 stations | 8 | 5 |
  | Rush hours / events from | week 3 / 5 | 3 / 4 | 2 / 3 |
  | Prices | | | lines and expansions dearer |

  The casual auto player survives an average of 7.2 / 4.6 / 3.1 weeks; a test keeps that order.
- **Campaign (`CampaignManager`):** eight fixed cities, each introducing one idea and its depot items:
  1. First Line: trains and lines only, no rare shapes
  2. Across the River: tunnels
  3. Busy Platforms: carriages and expansions
  4. New Shapes: rare stations and fast motors
  5. Rush Hour
  6. Changing Trains: special stations and express
  7. Disruptions: events
  8. Metropolis: everything, on Hard

  Each level has a week limit and three different objectives: deliver N, connect N stations, average efficiency, score, rush-hour deliveries, keep every station calm, use at most N lines. The first is required to pass; each is a star. Levels unlock in order and can be replayed. Targets were set from auto-player runs: it passes levels 1–6 with 1–2 stars and fails 7–8. Three stars need planning.
- **Challenges (`ChallengeManager`):** five fixed, deterministic cities with one unusual rule and bronze/silver/gold medals:
  - Two Lines Only
  - Commuter Belt (four rush hours a week)
  - Closed Depot (no purchases)
  - Islands (dear tunnels)
  - Chaos Week (an event every ~30 s)

  Every attempt plays out identically for the same actions (tested).
- **Unlocks (`PlayerProgress`):** the campaign unlocks Endless maps (Riverside at the start; then Harbour Bay, Lakeland, random cities, Twin Rivers, Old Port), Hard difficulty (after level 4) and the challenges (after the level that teaches what each one tests).
- **Scenario rules in the core (`ScenarioManager`):**
  - Time limits end a level exactly at the end of its last week, before the next week's credits arrive.
  - Objectives that depend on history (calm stations, line count, rush deliveries) are tracked during play.
  - Campaign levels pass once the first objective ("to pass") is met; if the network fails after that, the level still counts, scored at that moment (changed after a player report). A failure before it fails the level. Challenges are scored however they end.
- **Saving:**
  - **Progress:** stars, medals, Endless bests per map and difficulty, totals and the default difficulty are kept in `progress.json` in Application Support, with atomic writes. The Phase 3 best scores are migrated.
  - **Game in progress:** saved to `session.json` every 20 s, at each new week, when the app goes to the background and when leaving to the menu. The menu shows **Continue**, which resumes paused exactly where it was (tested to continue identically). The save is cleared when the game ends.
- **Screens:**
  - **Main menu:** Continue, Campaign, Endless, Challenges, Statistics and Settings, all live.
  - **Campaign / challenge lists:** stars, medals and locks; a briefing with the map, idea and objectives.
  - **Endless picker:** difficulty selector and locked maps with hints.
  - **In game:** "Week 2/4" in the HUD, an objectives capsule with a progress card, and a level-result screen (stars, objectives, Next level / Retry / Levels).
  - **Statistics:** totals and a best-score table per city and difficulty.
  - **Settings:** default difficulty and reset progress, with confirmation.
  - The depot, train card and line card only offer what the level allows.
- **Tests:** 106 total (13 new):
  - difficulty differences and ordering
  - scenario definitions; items and express refused when not allowed
  - exact time limit; failing versus scoring on game over
  - history objectives; determinism
  - unlock order and keeping best results; per-difficulty records; progress JSON
  - a saved session resuming identically
  - an auto-player report for every scenario

## Phase 5 — how it was verified

- 106/106 tests pass. macOS and iOS Simulator builds, Debug and Release, no warnings.
- iPhone 18 Pro simulator:
  - main menu (phone layout fixed so the three small buttons don't wrap)
  - campaign list with locks, and the level 1 briefing
  - started level 1 by touch, drew a line, and saw "Week 1/2" and the objectives capsule
- **Crash recovery:** the app was force-quit mid-level. On relaunch the menu offered **Continue**, which resumed the exact state, paused.
- **Level results:** the auto player played level 1 at 4×. The result showed "Level complete" with 2 stars and each objective's numbers. With saving on, it offered "Next: Across the River", and `progress.json` recorded 2 stars, the best score and the migrated Endless bests.
- macOS: the main menu renders correctly.
- **Not checked by hand:**
  - challenge and statistics screens
  - settings: reset progress and the difficulty picker
  - map-picker locks
  - the objectives card, which is the same component as the result rows
  - the Mac versions of the new screens
- The simulator dropped about half of all taps, so long touch sequences weren't practical.

## Phase 5 — known limitations

- Campaign and challenge scenarios are random within their seed. They are deterministic and hand-tuned, but
  not hand-built station by station.
- Progress lives on one device. There is no iCloud sync (CloudKit was optional and is not planned before release).
- Visual themes as unlockable content wait for Phase 6, where themes are made.
- The "Leave this city?" dialog has no title on iPhone (iOS hides confirmation-dialog titles).

## Phase 4 — what was built

Every system below changes a decision the player makes; all numbers are `GameConfiguration` values.

- **Smarter routing (interchange optimisation, `NetworkGraph`):** boarding a line now costs a fixed 3 s
  plus half the line's headway (its cycle time divided by its trains in service), so passengers prefer
  lines that run often, and a line with no trains is never used. Changing trains at an **interchange**
  station costs 35% as much and boarding/alighting there is twice as fast.
- **One stop rule for trains and route planning (`StopRules`):** closed stations and stations skipped by an
  express are run through without braking (unless the train must turn round there); passengers never plan
  to get on or off where the train won't stop.
- **Express lines (advanced route management):** a toggle on the line card. Express trains stop only at the
  line's ends, interchanges (stations on two or more lines) and special stations, which makes trips faster
  but takes service away from the stations in between. Drawn with a white centre stripe. It turns itself
  off when fewer than two stops would remain.
- **Demand patterns (`DemandManager`):** every station gets a demand (0.8–1.3× from district density), an
  attraction (central stations up to 2.2× more popular as destinations) and a centrality. Trips favour shapes
  found in the centre.
- **Rush hour:** from week 3, two rush hours a week on random weekdays: a morning one (outskirts generate up
  to 2× passengers, +0.1× a week, max 3×) and an evening one (the centre). Listed in the weekly Depot and
  in the HUD ("Rush hour Thu · morning", then a countdown while it runs).
- **Special stations:** from the 6th station, 20% of new stations get a role, at most 2 of each:
  - **Hub:** 1.7× passengers, +4 room.
  - **Interchange:** quick transfers, +4 room.
  - **Heritage:** at most 2 lines may stop there.
  - **Grand:** +14 room, but can't be expanded.

  Each has a badge on the map and a description in the station card.
- **Network events (`EventManager`):** from week 4, one at a time every 55–95 s, announced 8 s ahead (toast, a
  dashed spinning ring on the station, and a countdown in the HUD):
  - demand **surge** at a station (3× for 25 s)
  - **tour group** of 5 heading for the rarest shape
  - **train maintenance:** only on lines with at least 2 trains; the train lets everyone off at its next stop and waits 25 s
  - **station closure:** an ordinary station whose shape exists elsewhere; trains run through, nobody arrives, and its overcrowding timer is frozen for 20 s
- **Network efficiency (`EfficiencyManager`):** a 0–100 score from average waiting time, trip time, seat
  use and the share of nearly-full stations (moving averages). Shown in the HUD; tap/click for a breakdown
  card with a tip for the weakest factor. The session average is in the game-over summary.
- **Tests:** 93 total (14 new):
  - express stop rules, express run-through and passengers planning for it
  - closure (run through, frozen timer, reopening)
  - headway costs and lines with no trains; interchange discount
  - heritage line limit; grand/hub capacity and demand
  - destination attraction; station character; rush-hour planning and multipliers
  - maintenance; events announced ahead and never overlapping, across three seeds with passengers conserved
  - the efficiency score; deliveries feeding it

  The balance test still requires the casual auto player to reach week 4 (it now reaches weeks 4–6).

## Phase 4 — how it was verified

- 93/93 tests pass (`swift test`). macOS and iOS Simulator builds, Debug and Release, no warnings.
- iPhone 18 Pro simulator, with the auto player running the network at 4× (`-MetroDemoAuto -MetroDemoSpeed 4`), 50–60 fps:
  - rush-hour notices ("Rush hour Tue · morning", then a red running countdown) and a maintenance warning
    counting down
  - the efficiency capsule and its breakdown card (85%: bars and a tip)
  - heritage and grand badges on the map, and the heritage station card
  - an express line with its white stripe, and the line card's Express switch ("Stops at 3 of 7")
  - the game-over summary showing network efficiency (76%)
- The demo that switched a small line to express early lost in week 3. That shows the trade-off is real:
  stations it skips lose that line's service.
- Not seen on screen: a station closure marker, the surge ring, and the warning ring (only covered by
  tests). Also not seen: a tour-group toast, and the macOS layout of the new status row and cards.

## Phase 4 — known limitations

- Express is per line (all its trains). Mixed stopping patterns on one line aren't supported.
- Network events are random within their rules. There's no "event preview" in the Depot yet.
- Special stations are random (20% from the 6th station). Campaign levels (Phase 5) will place them by design.
- The auto player is deliberately simple: it never uses express, loops or recolouring.

## Phase 3 — what was built

All numbers below are `GameConfiguration` values (Endless defaults); balance is revisited in Phase 7.

- **Weeks and budget (`DifficultyManager`, `ResourceManager`):** a week is 90 simulated seconds. Each new
  week grants 3 credits plus 1 bonus credit per 20 passengers delivered the previous week (max +3). The
  game pauses and the **Depot** opens with the grant breakdown; it can also be opened any time (ticket
  button, `D`). Unspent credits carry over.
- **Depot items (prices in credits):** train 3, carriage 2, new line 4 (up to 7), tunnels ×2 for 2, station
  expansion 2, fast motor 3. Starting stock: 3 lines, 3 trains, 3 tunnels, 2 credits.
- **Limited resources, nothing free:** a line slot, train, carriage, motor or expansion is either spare or
  in use. A new line takes a spare train if there is one (otherwise it starts empty); line card **+** uses a
  spare; a withdrawn train or a deleted line's trains return their locomotive, carriages and motor to stock
  once they've finished their trip. Locked line colours show a padlock in the HUD (tap → depot).
- **Water crossings:** a line segment needs a tunnel when *both* bend directions of its path cross water.
  If only one bend stays dry, the line is always drawn that way, so it never crosses water unnecessarily.
  Each line over the water uses its own tunnel; edits that would need more tunnels than owned are refused
  ("Not enough tunnels…"), and removing the segment frees the tunnel. Bridges are drawn over the water part.
- **Train upgrades:** carriages (+4 seats each, max 2 per train, each makes the train 15% slower to
  accelerate; can't be uncoupled while those seats are taken) and a fast motor (+35% speed, +30%
  acceleration). Fitted from the train card; drawn as coupled cars and a white speed stripe.
- **Station congestion and game over:** a station holds 12 passengers (+8 per expansion, max 2). Over
  capacity, its overcrowding timer fills in 50 s (ring around the station, amber → red, glow from halfway,
  a toast when it starts); back under capacity it drains over 30 s. A full timer ends the session: the
  simulation stops, the camera frames the station, and further commands are refused.
- **Scoring (`ScoringManager`):** 10 points per delivered passenger, +up to 5 for quick journeys (full
  bonus ≤ 30 s door to door, none from 90 s). HUD shows score, passengers, week and day.
- **Difficulty progression:** passenger intervals start at 12 s per station and shrink 8% a week (floor 34%, about 4 s), on top
  of the city growing (a station every ~20 s, rarer shapes after 8 stations).
- **End-of-session summary:** score, passengers, week reached and time, stations, average journey, best
  week, points per trip; personal best per city stored locally (`ScoreBook`, UserDefaults JSON) with a
  "New best" badge. Play the same city again, choose another, or go to the menu.
- **Tests:** 77 total (18 new): starting stock, line-slot purchase, prices and failure leaving state
  untouched, train stock and return of parts, carriage limits and in-use rule, motor speed, tunnels (needed,
  refused, per line, freed), dry-bend forcing, bridge spans, overcrowding timer → game over → frozen state,
  recovery, expansions, weekly grant and bonus cap, demand curve, scoring curve, summary, and a 4-seed random
  play fuzz asserting every item is conserved (spare + in use = start + bought), tunnels used ≤ owned,
  credits ≥ 0 and passengers conserved.

## Phase 3 — how it was verified

- 77/77 tests pass (`swift test`); macOS and iOS Simulator builds, Debug and Release, no warnings.
  Full-city stress test: 0.006 ms per simulation step in Release.
- iPhone 18 Pro simulator (debug demo flags, 50–60 fps):
  - HUD fits a landscape phone: week and day, score, passengers, line slots (with locked slots), spare trains, free tunnels and the Depot button.
  - The Depot opens by itself at week 2 with the right grant (+3, +1 for 36–39 passengers).
  - Buying worked by touch: a train, an expansion and a carriage. Credits and stock updated, and unaffordable items greyed out.
  - "Start week" resumed the game.
  - Line card: **+** disabled with no spare trains.
  - Train card: carriages and motor rows.
  - A line built with no spare trains starts empty.
  - Overcrowding rings went amber → red.
  - Bridge drawn where a line crosses the river; the tunnel count dropped by one.
  - Game over: the camera framed the failed station, the summary showed, the personal best was kept across sessions, and "Play again" started a fresh city.
- macOS (window covered by Claude, ~5 fps, so stills only): the full-size HUD and train card lay out correctly.
- Not checked by hand: coupling a carriage, fitting a motor and expanding a station by tapping the card buttons (the simulator dropped taps; the logic is covered by tests). The macOS Depot and game-over layouts were not seen. No long human play-test of the balance yet: an unattended demo with 3 lines and no depot use fails in week 2.

## Early-game balance pass (2026-11-13, user request: "early game easier")

Measured with a deterministic **auto player** (`BalanceTests.swift`): a deliberately casual strategy that
keeps every station connected to the nearest line end, places spare trains on the busiest line and spends
credits on the obvious fix. Six maps (3 presets + 3 random seeds).

| | Before | After |
|---|---|---|
| Casual auto player loses | week 2–3 (2.8–4.5 min) | week 4–5 (5.0–7.2 min) |
| City with no lines loses | 2.2 min | 3.0 min |

Changes: passengers start every 12 s per station instead of 9 s (demand then grows 8% a week instead of 7%,
so the late game is as hard as before); stations appear every ~20 s instead of ~16 s; a station holds 12
instead of 10; the overcrowding timer is 50 s instead of 40 s; you start with 2 credits. A balance test now
fails if the casual player loses before week 4 on any of the six maps, or if an empty city survives.

## Phase 3 — known limitations

- No Easy/Normal/Hard yet (Phase 5); Endless uses one balanced default, not yet play-tested at length.
- "Network efficiency" in the summary is the average journey time; the full efficiency model is Phase 4.
- Express trains (skipping stops) are left for Phase 4's advanced route management.
- Sessions still aren't saved mid-game (the state is `Codable`; saving comes with Phase 5 progression).
- A line drawn over water while out of tunnels is only refused when you let go (toast), not shown in red
  while dragging.

## Design polish (pulled forward from Phase 6 at the user's request, 2026-11-13)

Free assets, all logged in [THIRD_PARTY_ASSETS.md](../THIRD_PARTY_ASSETS.md):
- **Outfit** (SIL OFL 1.1, downloaded with approval) for every UI string; registered at launch with Core Text.
- **Kenney Particle Pack** (CC0): a soft glow (station and train
  shadows, selection halo, spawn pulse) and a sparkle (passenger delivered).

Drawn in code:
- **Map:** seeded city blocks that thicken around neighbourhood centres (replacing flat district discs),
  tree crowns in parks, ripple marks on water, street grid.
- **Lines:** darker edge under every line for crisp crossings.
- **Stations:** soft contact shadow, breathing blue halo when selected, glow pulse when a station appears.
- **Trains:** soft shadow, headlight on the leading end, new trains face along their line.
- **Effects:** `VisualEffectsManager` sparkle on deliveries (throttled per station).
- **App icon and menu logo** (`Tools/make-icon.swift`): three lines meeting at an interchange over a river;
  all macOS sizes plus iOS 1024.
- **Menu:** logo beside the title, map-style backdrop with a calm centre. **iPhone line card:** two short
  columns instead of one tall card.
- **Debug demo mode:** `MetroNetwork -MetroDemo 0 [-MetroDemoSelect]` opens a city and builds lines by itself,
  for screenshots without input (compiled out of Release).

Verified on macOS and the iPhone 18 Pro simulator (56–60 fps with 3 lines, 6 trains, 150 nodes); 59/59 tests
pass; Debug and Release builds have no warnings.

Still open for Phase 6: sound and music, more map themes, menu transitions, passenger boarding animation.

## Phase 2 — what was built

- **Trains (`TrainManager`):** every new line gets a train; up to 4 per line (+/− on the line card, or
  withdraw a specific train from its card). Trains run station to station with acceleration, braking and a
  crawl speed so they always arrive, dwell per stop (base + per passenger), turn round at the ends of open
  lines and keep circling on loops. Capacity 6.
- **Line edits while trains run — nothing teleports, nobody is lost:** a train whose next stop was taken off
  its line still arrives there, lets everyone off, then drives empty to the nearest station still on the
  line; a train whose line is deleted (or that is withdrawn) finishes its trip, lets everyone off, and leaves.
- **Passengers (`PassengerManager`):** each station generates passengers on its own jittered timer (separate
  RNG stream from station spawning), destination = a shape that exists at another station, never its own.
  Generation pauses at 18 waiting (real overcrowding rules are Phase 3).
- **Pathfinding (`NetworkGraph`):** one multi-source Dijkstra per shape over stations and directional
  platforms (station, line, direction), with ride-time and transfer-penalty costs. Rebuilt only when lines
  or stations change. Passengers board only trains that are (one of) their best options, stay on while
  that's best, change trains at interchanges, and wait if nothing reaches their shape.
- **Rendering:** trains as cars in the line colour carrying upright passenger glyphs, following the drawn
  (offset, bent) line; waiting passengers as one glyph node per station. Both scale up when zoomed out so
  they stay readable on iPhone. Withdrawn/retiring trains are faded and keep their path.
- **UI:** HUD shows passengers transported and trains in service; line card has train −/+; new train card
  (load, next stop, withdraw); station card shows how many are waiting. Click/tap a train to select it
  (stations keep priority so lines can still be drawn from a station with a train in it).
- **Tests:** 59 total (17 new): movement and turnaround, loops, speed limit, train limits, direct and
  transfer journeys, capacity, boarding direction, transfer cost, generation rules and cap, deleting a line
  and removing a stop mid-trip, a 6-seed random-edit fuzz asserting passengers are always conserved
  (spawned = delivered + waiting + on board), save/restore continuing identically, and a full-city timing test.

## Phase 2 — how it was verified

- 59/59 tests pass (`swift test`, `Scripts/test.sh`); Debug + Release builds for macOS and iOS, no warnings.
- Full city stress (45 stations, 7 lines, 28 trains, ~700 passengers, edits every 3 s): 0.17 ms per
  simulation step in Debug, 0.004 ms in Release.
- macOS app with real mouse/keyboard: trains deliver passengers, a second line created an interchange where
  passengers visibly transferred, a full train left 2 passengers for the next one, add-train, train card,
  withdraw (train finished its trip, delivered all 6, left). 54–60 fps.
- iPhone 18 Pro simulator with touch input: line drawing, trains running and delivering at 50–60 fps.

## Phase 2 — known limitations

- No game over, scoring, overcrowding or resource limits yet (Phase 3); queues simply stop growing at 18.
- New trains appear at the stop furthest from the line's other trains; you can't drag them to a spot.
- Two trains passing in opposite directions overlap for a moment at a shared station.
- Waiting-passenger glyphs are always drawn to the right of a station and can sit on top of a line.
- Train timing ignores bend radius and uses the same speed on every line (upgrades come in Phase 3).

## Phase 1 — what was built

- **Project:** one Xcode project, one multiplatform app target (macOS 14+, iOS 17+ iPhone/iPad) and the local
  `MetroCore` package. No third-party code. macOS build is sandboxed with no network entitlement.
- **Shared core (`MetroCore`):** `GameEngine` (command-based, state untouched on failure), `SimulationEngine`
  (fixed 1/30 s step), `StationManager` (seeded, district-weighted spawning with spacing and water clearance,
  city radius grows with station count, rare shapes after 8 stations, max 2 each), `RouteManager` (create /
  extend / insert / remove / replace / delete / recolour-with-swap / open loop, full validation),
  `MapGenerator` (river, coastal, lakes archetypes; parks; districts), `RouteGeometry` (octilinear segments,
  per-pair bend orientation chosen to avoid hairpins, parallel offsets, handles, hit testing),
  `RouteEditor` (drag state machine), `GameSessionManager`, all tunables in `GameConfiguration`.
- **App:** main menu (Endless enabled; Campaign / Challenges / Statistics / Settings marked "Coming soon"),
  map picker with live previews (3 presets + random seed), SpriteKit game scene with diff-based renderers,
  SwiftUI HUD (clock, station count, 7 line slots, pause, 1×/2×, fit, leave) and station/line context cards.
- **Input:** one shared `InputController`; macOS (mouse, right-drag, trackpad scroll + pinch, wheel zoom,
  keyboard shortcuts) and iOS (one-finger edit/pan, pinch, two-finger pan; second finger cancels an edit).
  Drags sweep every station between pointer samples, so fast swipes don't skip stations.
- **Tests:** 42 Swift Testing tests (route rules and edge cases, drag editing, geometry and hit testing,
  map determinism, spawn constraints over 8 simulated minutes, frame-rate independence, pause/speed,
  JSON round-trip of the whole state).

## Phase 1 — how it was verified

- `swift test` and `Scripts/test.sh`: 42/42 pass. macOS and iOS Simulator builds: Debug and Release, no warnings.
- macOS app driven with real mouse and keyboard events: draw a line through 3 stations, extend from the
  handle through 3 more, insert by segment drag, parallel line on a shared segment, select / recolour / swap,
  Delete key, remove a station from the station card, close a loop, wheel zoom, pan, Space / Tab. 60 fps.
- iPhone 18 Pro simulator (landscape) driven with real touch paths: menu → map → line drawing with sparse
  touch samples, pinch zoom, tap selection and cards. ~45–60 fps once the simulator warmed up.

## Known limitations (by design for Phase 1, or to revisit)

- Stations stop spawning at 45.
- Water is visual only: lines may cross rivers freely. Tunnels/bridges as a resource come with Phase 3.
- Line slots = the 7 palette colours; real resource limits arrive in Phase 3.
- Sessions are not saved (state is fully `Codable` and round-trip tested; saving is a later phase).
- Editing one line can re-shape bends on neighbouring segments (bend directions are re-optimised
  network-wide to avoid hairpins). Usually invisible; may revisit if it feels jumpy.
- iPad was built (device family 1,2; all orientations) but only the iPhone simulator was exercised.
  Not run on a physical device (no signing team configured).
- iPhone stations are small (~9 pt) when the opening stations are far apart; touch targets are 26 pt.
- Only one visual theme (Metropolitan); more themes and real station art are Phase 6.
