import Foundation
import Testing
@testable import MetroCore

struct BalanceRun: CustomStringConvertible {
    let map: String
    let week: Int
    let day: Int
    let minutes: Double
    let delivered: Int
    let stations: Int
    let survived: Bool
    var cause = ""
    var description: String {
        "\(map.padding(toLength: 18, withPad: " ", startingAt: 0)) week \(week) day \(day + 1)  "
            + String(format: "%5.1f min", minutes) + "  delivered \(delivered)  stations \(stations)"
            + (survived ? "  (survived the cap)" : "  " + cause)
    }
}

/// Plays one session with the auto player, up to `maxWeeks`.
func autoPlay(_ preset: MapPreset, config: GameConfiguration = .standard, maxWeeks: Int = 16) -> BalanceRun {
    let engine = GameSessionManager.newSession(preset: preset, config: config)
    var player = AutoPlayer()
    let cap = Double(maxWeeks) * config.weekLength
    while !engine.state.isOver, engine.state.elapsed < cap {
        player.act(on: engine)
        engine.update(realDelta: config.simulationStep * 3)     // three steps per call at 1×
    }
    let s = engine.state
    var run = BalanceRun(map: preset.name, week: s.week, day: s.dayOfWeek, minutes: s.elapsed / 60,
                         delivered: s.passengersDelivered, stations: s.stations.count, survived: !s.isOver)
    if let over = s.gameOver, let st = s.station(over.station) {
        let lines = s.lines(serving: st.id)
        let trains = lines.reduce(0) { $0 + s.trains(on: $1.id).count }
        run.cause = "[\(st.shape) on \(lines.count) line(s), \(trains) train(s) there; network \(s.lines.count) lines \(s.trains.count) trains, "
            + "unserved \(s.stations.count - Set(s.lines.flatMap(\.stations)).count), waiting total \(s.stations.reduce(0) { $0 + $1.waiting.count })]"
    }
    return run
}

let balancePresets: [MapPreset] = MapPreset.builtIn + [101, 202, 303].map { MapPreset.random(seed: $0) }

@Suite("Balance")
struct BalanceTests {

    /// The early game must be forgiving: a simple player who just keeps every station connected and uses
    /// the weekly budget sensibly should not lose before week 4 on any map.
    @Test func casualPlayerSurvivesTheEarlyGame() {
        var runs: [BalanceRun] = []
        for preset in balancePresets {
            let run = autoPlay(preset)
            runs.append(run)
            #expect(run.week >= 4, "\(run)")
        }
        print("Balance (auto player):\n" + runs.map { "  \($0)" }.joined(separator: "\n"))
    }

    /// …but the game must still end: without any lines, a city overcrowds within the first weeks.
    @Test func idleNetworkStillFails() {
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[0])
        while !engine.state.isOver, engine.state.week < 6 { engine.update(realDelta: 0.1) }
        #expect(engine.state.isOver)
        print("Idle city fails in week \(engine.state.week), \(String(format: "%.1f", engine.state.elapsed / 60)) min")
    }
}

/// Plays a mode with the auto player until it ends (or `maxWeeks`).
func autoPlay(mode: SessionMode, maxWeeks: Int = 16, thinkInterval: Double = 2) -> GameEngine {
    let engine = GameSessionManager.newSession(mode: mode)!
    var player = AutoPlayer()
    player.thinkInterval = thinkInterval
    let cap = Double(maxWeeks) * engine.state.config.weekLength
    while !engine.state.isOver, engine.state.elapsed < cap {
        player.act(on: engine)
        engine.update(realDelta: engine.state.config.simulationStep * 3)
    }
    return engine
}

@Suite("Balance: difficulty and scenarios")
struct ScenarioBalanceTests {

    /// Easy must be clearly more forgiving than Normal, and Normal than Hard, for the same casual player.
    @Test func difficultiesAreOrdered() {
        var weeks: [Difficulty: Double] = [:]
        for d in Difficulty.allCases {
            let runs = balancePresets.map { autoPlay(mode: .endless($0, d), maxWeeks: 20).state.elapsed }
            weeks[d] = runs.reduce(0, +) / Double(runs.count) / GameConfiguration.standard.weekLength
        }
        print("Average weeks survived by the auto player: " + Difficulty.allCases.map {
            "\($0.displayName) \(String(format: "%.1f", weeks[$0]!))" }.joined(separator: ", "))
        #expect(weeks[.easy]! > weeks[.normal]! + 0.5)
        #expect(weeks[.normal]! > weeks[.hard]! + 0.5)
    }

    /// The casual player should get through the first campaign levels (they teach the basics); later
    /// levels and three stars need real planning.
    @Test func scenarioReport() {
        var lines: [String] = []
        for s in CampaignManager.levels + ChallengeManager.challenges {
            let e = autoPlay(mode: .scenario(s.id))
            let r = e.scenarioResult!
            let objectives = r.objectives.map { o in
                (o.met ? "✓" : "✗") + "\(o.objective) \(Int(o.current))/\(Int(o.target))"
            }.joined(separator: "  ")
            lines.append("\(s.id.padding(toLength: 16, withPad: " ", startingAt: 0)) \(r.passed ? "PASS" : "fail") "
                         + "\(r.stars)★ wk\(e.state.week) \(e.state.isFinished ? "time" : "lost")  \(objectives)")
            if CampaignManager.levels.prefix(3).contains(where: { $0.id == s.id }) {
                #expect(r.passed, "\(s.id) should be passable by a casual player")
            }
            // Players found the extra stars out of reach: a steady player should earn two on the first six levels.
            if CampaignManager.levels.prefix(6).contains(where: { $0.id == s.id }) {
                #expect(r.stars >= 2, "\(s.id): the casual player should earn at least two stars")
            }
        }
        print("Scenarios (auto player):\n" + lines.map { "  " + $0 }.joined(separator: "\n"))
    }

    /// "Have N stations on lines" must leave slack: the map has to have spawned comfortably more than N stations
    /// by the end, so the player never has to connect a station that appeared seconds before the level ends.
    @Test func stationTargetsAreReachable() {
        for s in CampaignManager.levels {
            for case .connectedStations(let n) in s.objectives {
                let e = GameSessionManager.newSession(mode: .scenario(s.id)) { $0.overcrowdTime = 1e12 }!
                var player = AutoPlayer()
                while !e.state.isOver {
                    player.act(on: e)
                    e.update(realDelta: e.state.config.simulationStep * 3)
                }
                #expect(n <= e.state.stations.count - 2, "\(s.id) asks for \(n) of \(e.state.stations.count) stations")
            }
        }
    }
}
