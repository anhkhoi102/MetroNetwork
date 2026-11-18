import Foundation
import Testing
@testable import MetroCore

@Suite("Difficulty levels")
struct DifficultyTests {

    /// Hard must differ in more than passenger rate: resources, room, pressure and city complexity.
    @Test func levelsDifferInSeveralWays() {
        let e = GameConfiguration.make(.easy), n = GameConfiguration.make(.normal), h = GameConfiguration.make(.hard)
        #expect(n == .standard.withDifficulty(.normal))
        #expect(e.startingLocomotives > n.startingLocomotives && e.weeklyCredits > n.weeklyCredits)
        #expect(e.stationCapacity > n.stationCapacity && n.stationCapacity > h.stationCapacity)
        #expect(e.overcrowdTime > n.overcrowdTime && n.overcrowdTime > h.overcrowdTime)
        #expect(h.rareShapesAfterStations < n.rareShapesAfterStations)
        #expect(h.rushIntensity > n.rushIntensity && h.eventsFromWeek < n.eventsFromWeek)
        #expect(h.startingCrossings < n.startingCrossings && h.priceLine > n.priceLine)
    }
}

extension GameConfiguration {
    func withDifficulty(_ d: Difficulty) -> GameConfiguration { var c = self; c.difficulty = d; return c }
}

@Suite("Scenarios")
struct ScenarioTests {

    @Test func definitionsAreWellFormed() {
        let all = CampaignManager.levels + ChallengeManager.challenges
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.preset.id)).count == all.count)
        #expect(CampaignManager.levels.count == 10 && ChallengeManager.challenges.count == 5)
        for s in all {
            #expect(s.objectives.count == 3, "\(s.id)")
            #expect(GameSessionManager.newSession(mode: .scenario(s.id))?.state.scenario?.id == s.id)
        }
        #expect(CampaignManager.levels.allSatisfy { $0.weekLimit != nil })
        // Levels introduce depot items gradually; the first one sells only trains and lines.
        #expect(CampaignManager.levels[0].config.availablePurchases == [.locomotive, .line])
        #expect(!CampaignManager.levels[0].config.allowExpress)
    }

    @Test func restrictedItemsAndExpressAreRefused() {
        let engine = GameSessionManager.newSession(mode: .scenario("c1-first-line"))!
        #expect(engine.apply(.purchase(.motor)) == .failure(.notForSale))
        let ids = engine.state.stations.prefix(2).map(\.id)
        guard case .success(.lineCreated(let line)) = engine.apply(.createLine(stations: ids, colorIndex: nil, isLoop: false)) else {
            Issue.record("line not created"); return
        }
        #expect(engine.apply(.setExpress(line, true)) == .failure(.expressNotAllowed))
    }

    @Test func timeLimitFinishesExactlyAtTheEndOfTheLastWeek() {
        let engine = autoPlay(mode: .scenario("c1-first-line"))
        let s = engine.state
        #expect(s.isFinished && s.gameOver == nil)
        #expect(s.week == 2)                                       // no rollover into week 3
        #expect(abs(s.elapsed - 2 * s.config.weekLength) < s.config.simulationStep * 1.5)
        let r = engine.scenarioResult!
        #expect(r.passed && r.stars >= 1)
        // Nothing moves after the end.
        let frozen = engine.state
        engine.update(realDelta: 0.1)
        #expect(engine.state == frozen)
    }

    /// The pass objective is "to pass": once it is met, a later network failure doesn't take the level away
    /// (a player reported failing Old Port on the last day with 553 of 260 passengers delivered).
    @Test func networkFailureAfterThePassObjectiveStillPasses() {
        for id in ["c7-disruptions", "x1-two-lines"] {
            var state = GameSessionManager.newSession(mode: .scenario(id))!.state
            state.passengersDelivered = 553
            state.stats.score = 7_877
            state.scenario?.tracking.peakOvercrowding = 1
            state.status = .over(GameOverInfo(station: state.stations[0].id, time: 4.9 * state.config.weekLength))
            let r = ScenarioManager.result(of: state)!
            #expect(r.passed, "\(id)")
            if id == "c7-disruptions" {
                #expect(r.stars == 2)                                  // deliver and score; calm stations lost
                #expect(r.objectives[1].lost)
            }
        }
    }

    /// Failing before the pass objective is met still fails the level.
    @Test func networkFailureBeforeThePassObjectiveFails() {
        var state = GameSessionManager.newSession(mode: .scenario("c7-disruptions"))!.state
        state.passengersDelivered = 259
        state.stats.score = 100_000
        state.status = .over(GameOverInfo(station: state.stations[0].id, time: 10))
        let r = ScenarioManager.result(of: state)!
        #expect(!r.passed && r.stars == 0)
        #expect(r.objectives[0].lost)
    }

    @Test func historyObjectives() {
        var state = makeState(stations: 6)
        state.scenario = ScenarioState(id: "t", kind: .campaign, weekLimit: 1,
                                       objectives: [.calmStations, .maxLines(1), .rushDeliveries(1)])
        state.stations[0].overcrowding = 0.6
        var events: [GameEvent] = []
        ScenarioManager.update(&state, events: &events)
        try? RouteManager.apply(.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false), to: &state)
        try? RouteManager.apply(.createLine(stations: ids(3, 4), colorIndex: nil, isLoop: false), to: &state)
        try? RouteManager.apply(.deleteLine(state.lines[1].id), to: &state)       // too late: two were running
        state.rushHours = [RushHour(flow: .toCentre, start: 0, end: 100, intensity: 2)]
        ScenarioManager.recordDelivery(in: &state)
        let p = ScenarioManager.progress(of: state)
        #expect(p[0].lost && !p[0].met)
        #expect(p[1].lost)
        #expect(p[2].met)
    }

    /// Challenges must be reproducible: the same actions give the same result.
    @Test func scenariosAreDeterministic() {
        let a = autoPlay(mode: .scenario("x4-islands"), maxWeeks: 3)
        let b = autoPlay(mode: .scenario("x4-islands"), maxWeeks: 3)
        #expect(a.state == b.state)
    }
}

@Suite("Progress and saving")
struct ProgressTests {

    private func result(_ id: String, kind: ScenarioKind, stars: Int, score: Int) -> ScenarioResult {
        ScenarioResult(id: id, kind: kind, passed: stars > 0, stars: stars, objectives: [], score: score)
    }

    private let summary = SessionSummary(score: 100, delivered: 10, elapsed: 60, week: 1, stations: 5,
                                         averageJourney: 20, bestWeek: 10, efficiency: 70)

    @Test func campaignUnlocksInOrderAndKeepsTheBest() {
        var p = PlayerProgress()
        #expect(p.isLevelUnlocked(0) && !p.isLevelUnlocked(1))
        p.recordScenario(result("c1-first-line", kind: .campaign, stars: 2, score: 500), summary: summary)
        #expect(p.isLevelUnlocked(1) && !p.isLevelUnlocked(2))
        p.recordScenario(result("c1-first-line", kind: .campaign, stars: 1, score: 900), summary: summary)
        #expect(p.campaign["c1-first-line"] == PlayerProgress.LevelRecord(stars: 2, bestScore: 900, attempts: 2))
        // A failed level doesn't unlock the next one.
        p.recordScenario(result("c2-river", kind: .campaign, stars: 0, score: 50), summary: summary)
        #expect(!p.isLevelUnlocked(2))
        #expect(p.totals.games == 3 && p.totals.passengers == 30)
    }

    @Test func endlessContentUnlocksWithTheCampaign() {
        var p = PlayerProgress()
        #expect(p.isMapUnlocked(MapPreset.builtIn[0]))
        #expect(!p.isMapUnlocked(MapPreset.builtIn[1]))
        #expect(!p.isMapUnlocked(.random(seed: 5)))
        #expect(p.isDifficultyUnlocked(.easy) && !p.isDifficultyUnlocked(.hard))
        #expect(!p.isChallengeUnlocked("x1-two-lines"))
        for level in CampaignManager.levels.prefix(5) {
            p.recordScenario(result(level.id, kind: .campaign, stars: 1, score: 1), summary: summary)
        }
        #expect(p.levelsPassed == 5)
        #expect(p.isMapUnlocked(MapPreset.builtIn[2]) && p.isMapUnlocked(.random(seed: 5)))
        #expect(p.isDifficultyUnlocked(.hard))
        #expect(p.isChallengeUnlocked("x2-commuters") && !p.isChallengeUnlocked("x5-chaos"))
    }

    @Test func endlessRecordsPerMapAndDifficulty() throws {
        var p = PlayerProgress()
        p.recordEndless(summary, map: "riverside", difficulty: .hard)
        #expect(p.bestEndless(map: "riverside", difficulty: .hard)?.bestScore == 100)
        #expect(p.bestEndless(map: "riverside", difficulty: .normal) == nil)
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(PlayerProgress.self, from: data) == p)
    }

    /// A saved session restores exactly and carries on as if it had never stopped.
    @Test func savedSessionResumesIdentically() throws {
        let engine = autoPlay(mode: .scenario("c5-rush"), maxWeeks: 2)
        let saved = SavedSession(mode: .scenario("c5-rush"), state: engine.state)
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(SavedSession.self, from: data)
        #expect(loaded.state == engine.state && loaded.mode == .scenario("c5-rush"))
        let resumed = GameSessionManager.resume(loaded)
        #expect(resumed.isPaused)
        resumed.isPaused = false
        var original = engine.state, restored = resumed.state
        var simA = SimulationEngine(), simB = SimulationEngine()
        var events: [GameEvent] = []
        for _ in 0..<900 {
            simA.step(&original, events: &events)
            simB.step(&restored, events: &events)
        }
        #expect(original == restored)
    }
}
