# Metro Network — Phase 7 test report (release candidate)

Date: 2026-11-17. Build: Debug and Release, macOS 14+ and iOS 17+ (one multiplatform target).

## Automated tests

`swift test --package-path Packages/MetroCore` → **113 tests in 25 suites, all passing.**

| Area | What is covered |
|---|---|
| Routes and editing | Every line rule and edge case, drag editing, octilinear geometry, hit testing |
| Simulation | Fixed step, frame-rate independence, pause/speed, determinism, JSON round trips |
| Trains and passengers | Movement, capacity, transfers, edits mid-trip, passenger conservation under random edits |
| Pathfinding (Phase 7) | 40 random networks: a route exists exactly when the destination is reachable by riding running lines (checked by an independent search); boarding advice only onto usable routes; adding a line never makes a journey worse |
| Resources, scoring, progression | Depot, tunnels, upgrades, overcrowding, weeks, scoring, efficiency, express, events, special stations |
| Modes | Difficulty differences and ordering, scenarios, time limits, objectives, stars, unlocks |
| Save and load (Phase 7) | Phase 5 progress files still load; damaged files are rejected cleanly; a game saved mid rush hour, event and express resumes identically |
| Long runs (Phase 7) | 30 weeks on Easy, Normal and Hard with the auto player; every invariant checked every simulated second (passengers and every item conserved, tunnels within budget, trains on real stations with finite positions, timers in range, one event at a time) |
| Balance | Auto player survives week 4+ on 6 maps; Easy 7.2 > Normal 4.6 > Hard 3.1 weeks; scenario report (the auto player earns 2★ or more on levels 1–6); every "stations on lines" target leaves at least two stations of slack |
| Performance | Full city (45 stations, 7 lines, 28 trains, express, rush hours, events): **0.03 ms per simulation step** in Release (one 120 Hz frame is 8.3 ms) |

## Profiling and optimisation

Measured on the iPhone 18 Pro simulator with a debug "stress" city (`-MetroDemoStress`: 45 stations, 7 lines,
28 trains, ~880 nodes, queues at the cap) and with `sample`, `heap` and `leaks`.

| Finding | Change | Result |
|---|---|---|
| HUD recomputed every water crossing 4× a second | cached until the network changes | gone from the profile |
| Each train looked up stations by linear search and the stop rules every step | per-step position table; stop rules only when an express line or event exists | train update roughly halved |
| Train renderer looked up stations by linear search every frame | position table rebuilt only when a station is added | gone from the profile |
| Music synthesiser: ~700,000 `sin` calls a second, array checks on the audio thread | sine table and fixed buffers | **3.5 % → 0.46 %** of one core (optimised build) |
| Crowded HUD (7 lines, two-digit counts) squeezed the depot button until the credit count vanished | button keeps its size | fixed (seen on iPhone 18 Pro and 17e) |
| Tour groups could push a queue past the safety cap | they respect it like normal passengers | fixed |

- **Memory:** node count stays flat (592 shape nodes after 30 s and later); `leaks` reports 178 small leaks
  (11 KB) all inside Apple's audio framework (`ListenerBinding`), none in game code; resident memory
  fluctuates 185–215 MB in the debug simulator build without growing.
- **Frame rate:** 55–60 fps in normal play on the simulator; the stress city runs at 34–47 fps in the *debug*
  simulator build (simulator rendering is slower than devices; not measured on a physical device).

## Compatibility and screen sizes

| Device | Language | Checked |
|---|---|---|
| iPhone 18 Pro (simulator) | EN, VI | All screens, play, saving, results, themes, effects |
| iPhone 17e (simulator, smaller) | EN, VI | Menu, campaign, challenges, Endless picker, statistics, settings, game with a full city, train card |
| iPad mini (simulator) | VI | Menu screens and game |
| Mac, smallest window 900×600 | EN, VI | Menu, campaign, settings, Endless picker, statistics, game with a full city |

Fixed from this pass:
- **In-game HUD on narrow screens:** on an iPad in portrait it was cut off at both sides. It now wraps to two rows when one doesn't fit. A phone also wraps in the extreme case of five-digit scores; normal games stay on one row.
- **Endless picker:** city names wrapped onto two lines on the phone.
- **Statistics:** "best efficiency" showed 0 % for records that predate efficiency.

## Not covered

- No physical iPhone, iPad or Mac other than this development Mac (no signing team configured).
- Sound and music not heard: the simulator here has no audio output.
- No human play-testing of balance; numbers come from the deterministic auto player.
- Simulator taps are unreliable on this machine, so most screens were reached with debug launch flags
  rather than by tapping through.
