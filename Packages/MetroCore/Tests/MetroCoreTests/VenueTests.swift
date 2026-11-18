import Foundation
import Testing
@testable import MetroCore

/// Campaign part 2: the stadium (match crowds) and the airport (travellers in a hurry).
@Suite("Venues")
struct VenueTests {

    /// A test city whose first station is the stadium (or airport), overcrowding switched off.
    private func venueState(_ venue: SpecialStation, rules: VenueRules = VenueRules()) -> GameState {
        var config = GameConfiguration.noGameOver
        config.venues = rules
        var state = makeState(stations: 4, config: config)
        state.stations[0].special = venue
        if venue == .stadium { state.venues?.stadium = state.stations[0].id }
        if venue == .airport { state.venues?.airport = state.stations[0].id }
        return state
    }

    private func run(_ state: inout GameState, until time: Double) -> [GameEvent] {
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        while state.elapsed < time { sim.step(&state, events: &events) }
        return events
    }

    // MARK: Off by default

    @Test func endlessAndOlderLevelsHaveNoVenues() {
        #expect(GameConfiguration.standard.venues == nil)
        for s in CampaignManager.levels.prefix(8) + ChallengeManager.challenges {
            #expect(s.config.venues == nil, "\(s.id)")
        }
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[0])
        var player = AutoPlayer()
        while engine.state.week <= 3 && !engine.state.isOver {
            player.act(on: engine)
            engine.update(realDelta: engine.state.config.simulationStep * 3)
        }
        #expect(engine.state.venues == nil)
        #expect(engine.state.stations.allSatisfy { $0.special?.isVenue != true })
    }

    // MARK: Stadium

    @Test func stadiumOpensAsTheNthStation() throws {
        let engine = try #require(GameSessionManager.newSession(mode: .scenario("c9-match-day")))
        let after = try #require(engine.state.config.venues?.stadiumAfterStations)
        var player = AutoPlayer()
        while engine.state.stations.count <= after { player.act(on: engine); engine.update(realDelta: 0.1) }
        let stadium = engine.state.stations[after]
        #expect(stadium.special == .stadium)
        #expect(engine.state.venues?.stadium == stadium.id)
        #expect(engine.state.stations.filter { $0.special == .stadium }.count == 1)
        #expect(stadium.capacity(engine.state.config) == engine.state.config.stationCapacity + 16)
    }

    @Test func matchesArePlannedOnTheirDays() {
        var state = venueState(.stadium)
        _ = run(&state, until: 1)
        let c = state.config, rules = c.venues!
        let day = c.weekLength / 7
        #expect(state.venues?.matches.map(\.fullTime) == rules.matchDays.map { (Double($0) + rules.fullTime) * day })
        // Next week's matches are planned when it starts.
        _ = run(&state, until: c.weekLength + 1)
        #expect(state.venues?.matches.map(\.fullTime) == rules.matchDays.map { c.weekLength + (Double($0) + rules.fullTime) * day })
    }

    @Test func theCrowdLeavesAtFullTime() {
        var state = venueState(.stadium)
        let rules = state.config.venues!
        let fullTime = (Double(rules.matchDays[0]) + rules.fullTime) * state.config.weekLength / 7
        _ = run(&state, until: fullTime - 0.5)
        #expect(state.stations[0].waiting.allSatisfy { $0.kind == nil })
        let events = run(&state, until: fullTime + rules.crowdRelease + 0.5)
        #expect(events.contains(.fullTime(state.stations[0].id)))
        let fans = state.stations[0].waiting.filter { $0.kind == .fan }
        #expect(fans.count == rules.matchCrowd)
        #expect(fans.allSatisfy { $0.destination != state.stations[0].shape })
        #expect(state.venues?.matches.count == 1)                       // only Saturday's is left
        #expect(state.passengersSpawned == state.passengersDelivered + state.passengersInNetwork + state.passengersGaveUp)
    }

    @Test func theCrowdRespectsTheSafetyCap() {
        var rules = VenueRules()
        rules.matchCrowd = 30
        var state = venueState(.stadium, rules: rules)
        state.config.maxWaitingPerStation = 12
        _ = run(&state, until: (Double(rules.matchDays[0]) + rules.fullTime) * state.config.weekLength / 7 + rules.crowdRelease + 1)
        #expect(state.stations[0].waiting.count <= 12)
        #expect(state.venues?.matches.count == 1)                       // the capped match is still over
    }

    @Test func aStadiumOpeningMidweekOnlyGetsTheMatchesAhead() {
        var state = venueState(.stadium)
        state.venues?.stadium = nil
        let saturday = (Double(state.config.venues!.matchDays[1]) + state.config.venues!.fullTime) * state.config.weekLength / 7
        _ = run(&state, until: saturday - 30)
        state.venues?.stadium = state.stations[0].id
        _ = run(&state, until: saturday - 29)
        #expect(state.venues?.matches.map(\.fullTime) == [saturday])
    }

    @Test func fansAreCounted() {
        var state = venueState(.stadium)
        var events: [GameEvent] = []
        let fan = Passenger(id: 1, destination: .triangle, origin: state.stations[0].id, spawnTime: 0, kind: .fan)
        ScoringManager.deliver(fan, at: state.stations[1].id, in: &state, events: &events)
        ScoringManager.deliver(Passenger(id: 2, destination: .triangle, origin: state.stations[0].id, spawnTime: 0),
                               at: state.stations[1].id, in: &state, events: &events)
        #expect(state.venues?.fansDelivered == 1)
        #expect(state.passengersDelivered == 2)
    }

    // MARK: Airport

    @Test func airportOpensOnTheEdgeOfTown() throws {
        let engine = try #require(GameSessionManager.newSession(mode: .scenario("c10-airport")))
        let after = try #require(engine.state.config.venues?.airportAfterStations)
        var player = AutoPlayer()
        while engine.state.stations.count <= after { player.act(on: engine); engine.update(realDelta: 0.1) }
        let s = engine.state
        let airport = s.stations[after]
        #expect(airport.special == .airport && s.venues?.airport == airport.id)
        let centre = s.map.cityCenter
        let farthestOther = s.stations.filter { $0.id != airport.id }.map { $0.position.distance(to: centre) }.max()!
        #expect(airport.position.distance(to: centre) > farthestOther)
    }

    @Test func passengersFromTheAirportAreTravellers() {
        var state = venueState(.airport)
        _ = run(&state, until: 30)
        #expect(!state.stations[0].waiting.isEmpty)
        #expect(state.stations[0].waiting.allSatisfy { $0.kind == .traveller })
        #expect(state.stations.dropFirst().allSatisfy { $0.waiting.allSatisfy { $0.kind == nil } })
    }

    @Test func travellersOnTimeEarnABonus() {
        var state = venueState(.airport)
        let rules = state.config.venues!
        var events: [GameEvent] = []
        let base = ScoringManager.points(forJourney: 40, config: state.config)
        state.elapsed = 40
        ScoringManager.deliver(Passenger(id: 1, destination: .triangle, origin: state.stations[0].id, spawnTime: 0,
                                         kind: .traveller), at: state.stations[1].id, in: &state, events: &events)
        #expect(state.stats.score == base + rules.travellerBonus)
        #expect(events.contains(.pointsScored(state.stations[1].id, base + rules.travellerBonus)))
        state.elapsed = rules.travellerOnTime + 1
        ScoringManager.deliver(Passenger(id: 2, destination: .triangle, origin: state.stations[0].id, spawnTime: 0,
                                         kind: .traveller), at: state.stations[1].id, in: &state, events: &events)
        #expect(state.venues?.travellersOnTime == 1)
        #expect(state.passengersDelivered == 2)
    }

    @Test func travellersWhoWaitTooLongGiveUp() {
        var state = venueState(.airport)
        let patience = state.config.venues!.travellerPatience
        let events = run(&state, until: patience + 20)
        let gaveUp = state.venues?.travellersGaveUp ?? 0
        #expect(gaveUp > 0)
        #expect(events.contains { if case .travellersGaveUp(let s, _) = $0 { s == state.stations[0].id } else { false } })
        // Nobody left waits longer than their patience, and ordinary passengers never give up.
        #expect(state.stations.allSatisfy { $0.waiting.allSatisfy { $0.kind != .traveller || state.elapsed - $0.queuedSince <= patience } })
        #expect(state.stations.dropFirst().allSatisfy { !$0.waiting.isEmpty })
        #expect(state.passengersSpawned == state.passengersDelivered + state.passengersInNetwork + gaveUp)
    }

    // MARK: Whole levels

    /// Both levels, played to the end by the auto player: every invariant holds every simulated second, and
    /// a game saved halfway resumes identically.
    @Test(arguments: ["c9-match-day", "c10-airport"])
    func levelsKeepEveryInvariant(id: String) throws {
        let engine = try #require(GameSessionManager.newSession(mode: .scenario(id)) { $0.overcrowdTime = 1e12 })
        var player = AutoPlayer()
        let start = engine.state.resources
        var bought: [Purchase: Int] = [:]
        var nextCheck = 0.0
        var saved: GameState?
        while !engine.state.isOver {
            player.act(on: engine)
            engine.update(realDelta: engine.state.config.simulationStep * 3)
            for case .purchased(let item) in engine.drainEvents() { bought[item, default: 0] += 1 }
            let s = engine.state
            if saved == nil, s.week == 3 { saved = s }
            guard s.elapsed >= nextCheck else { continue }
            nextCheck = s.elapsed + 1
            let problems = invariantProblems(s, start: start, bought: bought)
            try #require(problems.isEmpty, "\(id) week \(s.week): \(problems.joined(separator: "; "))")
        }
        let v = try #require(engine.state.venues)
        #expect(v.fansDelivered + v.travellersOnTime > 0)
        let data = try JSONEncoder().encode(SavedSession(mode: .scenario(id), state: try #require(saved)))
        #expect(try JSONDecoder().decode(SavedSession.self, from: data).state == saved)
    }
}
