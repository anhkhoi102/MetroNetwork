# Metro Network — Architecture

Working title: **Metro Network**. An original transit-network strategy puzzle game for macOS and iOS.
Swift 6, SwiftUI (app shell, menus, HUD), SpriteKit (map, lines, trains). No third-party dependencies.

## 1. Big picture

```
┌──────────────────────────── MetroNetwork app target (macOS + iOS, one target) ─────────────────────────────┐
│  SwiftUI shell          RootView → MainMenuView / MapPickerView / GameScreen (HUD + context cards)         │
│        │ observes                                                                                          │
│  GameSessionController  (@MainActor, @Observable) — owns one GameEngine + one GameScene, publishes a      │
│        │                 throttled HUD snapshot, turns button taps into GameCommands                       │
│  GameScene (SpriteKit)  ticks the engine every frame, renders state through renderers, owns the camera     │
│        ├─ MapRenderer / StationRenderer / RouteRenderer / DraftRenderer (diff-based, revision-driven)      │
│        ├─ TrainRenderer / PassengerRenderer (per frame) · VisualEffectsManager (event-driven, throttled)   │
│        └─ InputController — ONE pointer state machine for both platforms (tap / pan / draw / extend /     │
│                             insert); talks to MetroCore's RouteEditor                                      │
│  Platform/               MacGameView (mouse, trackpad scroll + pinch, keyboard)                            │
│                          IOSGameView (touches, pinch, two-finger pan)                                      │
│                          → both only translate raw events into InputController calls                       │
└──────────────────────────────────────────────┬─────────────────────────────────────────────────────────────┘
                                               │ import MetroCore
┌──────────────────────────── Packages/MetroCore (pure Swift, Foundation only) ──────────────────────────────┐
│  GameEngine          single entry point: apply(GameCommand) → Result, update(dt), drainEvents()           │
│  SimulationEngine    fixed-step clock (dt accumulator) → identical results at any frame rate              │
│  StationManager      deterministic station spawning (seeded RNG, city growth, spacing, water clearance)    │
│  RouteManager        all line rules: create / extend / insert / remove / reorder / loop / recolor / delete │
│  GameSessionManager  builds sessions from a MapPreset + seed (+ save/load in Phase 3+)                     │
│  TrainManager        train lifecycle, movement (accel/brake), stops, boarding, safe line-edit handling     │
│  PassengerManager    per-station passenger generation (own RNG stream)                                    │
│  ResourceManager     depot purchases, spare stock, carriages/motors, station expansions, water crossings  │
│  ScoringManager      points per delivery (quick-trip bonus), session stats and summary                    │
│  DifficultyManager   weeks, weekly credit grant, demand growing week by week                              │
│  DemandManager       station demand/attraction, special stations, rush-hour planning                      │
│  EventManager        announced network events: surge, tour group, maintenance, closure                    │
│  EfficiencyManager   0–100 network efficiency from waits, trip times, seat use, crowding                  │
│  StopRules           where trains stop (closures, express) — shared by trains and NetworkGraph             │
│  AutoPlayer          deterministic casual player for balance tests and the debug demo                     │
│  ScenarioManager     campaign/challenge time limits, objectives, stars;  CampaignManager / ChallengeManager │
│  Progression         SessionMode, SavedSession, PlayerProgress (records + unlock rules); Difficulty         │
│  NetworkGraph        passenger route planning: Dijkstra per shape over directional platforms (cached)      │
│  MapGenerator        procedural maps: river / coastal / lakes archetypes, parks, districts                │
│  RouteGeometry       octilinear segment paths, parallel-line offsets, terminal handles, hit testing        │
│  RouteEditor         drag-to-build state machine (pure logic, unit-tested, platform-agnostic)              │
│  Model               GameState, GameConfiguration, Station, MetroLine, MapDefinition, IDs, Vec2, RNG       │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Rule:** nothing in `MetroCore` imports SpriteKit, SwiftUI, AppKit or UIKit. Every gameplay decision
(including what a drag gesture does to a line, and where a line is drawn for hit testing) lives in the
package, so macOS and iOS cannot drift apart. The app target only renders and translates input.

## 2. Gameplay systems and dependencies

| System | Depends on | Phase |
|---|---|---|
| Map generation (`MapGenerator`) | RNG, geometry | 1 |
| Stations (`StationManager`) | map, config, RNG | 1 (spawn) → 2 (queues) → 4 (special stations) |
| Routes (`RouteManager`, `RouteGeometry`, `RouteEditor`) | stations | 1 |
| Simulation clock (`SimulationEngine`) | — | 1 (spawning only) |
| Trains (`TrainManager`) | routes, clock | 2 ✅ |
| Passengers (`PassengerManager`) + pathfinding (`NetworkGraph`) | stations, routes, trains | 2 ✅ |
| Resources (`ResourceManager`): line slots, trains, carriages, motors, tunnels, expansions | routes, trains | 3 ✅ |
| Congestion and game over (`StationManager`), `ScoringManager`, `DifficultyManager` | passengers, stations | 3 ✅ |
| Demand patterns, rush hour, events, special stations, efficiency metrics, express lines | passengers, clock | 4 ✅ |
| `CampaignManager`, `ChallengeManager`, map presets, unlocks, persistence | everything above | 5 ✅ |
| Animation / VFX / audio polish | renderers | 6 |

Phase 1 implements only the first four rows. The other managers are **not** stubbed: they will be added
when their phase starts, so there are no placeholder implementations in the code base.

## 3. Data models (Phase 1)

```swift
struct StationID / LineID              // Int-backed, Codable, Comparable
enum   StationShape                    // circle, triangle, square, diamond, star, hexagon
struct Station   { id, shape, position: Vec2, spawnTime }
struct MetroLine { id, colorIndex, stations: [StationID], isLoop, revision }
struct MapDefinition { name, archetype, seed, size, cityCenter, water: [Polygon], parks: [Polygon], districts }
struct GameConfiguration { every tunable number: line slots, spawn timing, spacing, city growth, shapes… }
struct GameState { config, map, stations, lines, elapsed, spawn (RNG + timer), id counters, revision }
enum   GameCommand { createLine, extendLine, insertStation, removeStation, setStations, deleteLine,
                     setLineColor, openLoop }
enum   GameEvent   { stationSpawned, lineCreated, lineChanged, lineDeleted }
```

`GameState` is a value type and fully `Codable` (round-trip tested) so saving the current session later is a
JSON write, and Challenge mode can replay deterministic scenarios from a seed. All randomness comes from a
seeded SplitMix64 generator stored **inside** the state.

## 4. How the shared logic runs on both platforms

1. `GameScene.update(_:)` calls `engine.update(realDelta)` every frame. `SimulationEngine` clamps the delta,
   multiplies by game speed and advances in fixed `1/30 s` steps, so a 120 Hz ProMotion iPad and a 60 Hz Mac
   produce byte-identical states for the same seed and inputs.
2. Player actions become `GameCommand`s. The engine validates them through `RouteManager` and either applies
   them (bumping `revision`) or returns a typed `RouteError`. Commands are the only way to mutate state.
3. Renderers compare revisions and rebuild only what changed (one `SKShapeNode` per line, one node group per
   station; the map is drawn once).
4. Input: macOS `mouseDown/Dragged/Up`, iOS `touchesBegan/Moved/Ended` both call
   `InputController.pointerDown/Moved/Up(at:)` with a scene-space point. Hit tolerances are expressed in
   screen points and converted with the camera scale, so a 44 pt touch target stays 44 pt at any zoom.

## 5. Project structure

```
MetroNetwork/
├─ MetroNetwork.xcodeproj           hand-maintained, synchronized folder, one multiplatform app target
├─ MetroNetwork/                    app sources (synchronized group)
│  ├─ App/        MetroNetworkApp, RootView
│  ├─ UI/         MainMenuView, MapPickerView, GameScreen, HUDView, ContextCards, UITheme
│  ├─ Game/       GameSessionController, GameScene, CameraController, InputController, VisualTheme
│  │  └─ Renderers/  MapRenderer, StationRenderer, RouteRenderer, DraftRenderer, ShapePaths
│  └─ Platform/   GameViewContainer, MacGameView, IOSGameView
├─ Packages/MetroCore/              pure-Swift gameplay package + Swift Testing unit tests
├─ SupportingFiles/                 Info.plist (macOS), Info-iOS.plist, entitlements
├─ Scripts/                         build.sh, build-ios.sh, test.sh
└─ Docs/                            ARCHITECTURE.md, PHASES.md
```

## 6. Technical risks and mitigations

| Risk | Mitigation |
|---|---|
| **Passenger pathfinding cost** (Phase 2) | Passengers route by *destination shape*, not station. Build a line graph once per network revision, run one multi-source Dijkstra per shape (≤ 6 runs), cache "next hop per station per shape". Recompute only when lines change or a new shape appears — never per frame or per passenger. Cost weights: ride time + transfer penalty. |
| **Simulation performance** | Fixed-step sim decoupled from rendering; passengers are counters + small structs, rendered as a few glyph nodes per station (pooled, capped), not one node per passenger. |
| **Editing a line while trains run on it** (Phase 2) | `RouteManager` changes are diffs on the station list; `TrainManager` will re-anchor trains to the nearest valid segment and let passengers for removed stations alight at the next stop. Phase 1 keeps line edits as explicit commands so this hook has one place to live. |
| **Overlapping lines being unreadable** | `RouteGeometry` picks one bend direction per station pair (chosen network-wide so lines don't hairpin at stations) and gives each line sharing the pair a parallel offset; the same geometry is used for drawing and hit testing. |
| **Gesture conflicts** (pan vs draw on iOS) | One-finger drag on empty map pans, on a station/handle/line edits; two fingers always pan/zoom and cancel any edit in progress. |
| **Determinism drift** | All RNG in `GameState`, fixed step, no `Date()`/`random()` in core. Tests compare runs with different frame-delta patterns. |
| **8 GB dev machine / simulator speed** | Keep node counts low, avoid per-frame path rebuilds; verify release builds on device-class simulators. |

## 7. Phase 1 acceptance criteria

1. One Xcode project builds a macOS app and an iOS (iPhone + iPad) app from the same target and sources; `swift test` passes.
2. Main menu with Endless (prototype sandbox) enabled; Campaign / Challenges / Statistics / Settings shown as "Coming soon".
3. A map picker offers three procedurally generated maps (river, coastal, lakes) plus a random seed; the same seed always produces the same map.
4. The map renders land, water, parks and street texture; stations never spawn in water or too close to each other.
5. Three stations exist at start; more spawn over time as the city grows, with a pop-in animation. Pause and 2× speed work.
6. Drag from a station across others to build a new line (up to 7 lines, each with its own colour). Lines are drawn octilinearly; parallel lines on the same station pair are offset, not stacked.
7. Drag a line's end handle to extend it, or back along the line to shorten it; dragging onto its first station closes a loop.
8. Drag the middle of a segment onto a station to insert that station into the line.
9. Tap a station to see its lines and remove it from any of them; tap a line to recolour it, open a loop, remove stations, or delete it.
10. Zoom and pan: scroll / pinch / drag on macOS, pinch / drag / two-finger pan on iOS; "fit city" button; window resizing works.
11. Invalid edits (duplicates, < 2 stations, no free line) are rejected by `RouteManager` and never corrupt state.
