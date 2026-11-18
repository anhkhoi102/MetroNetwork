import Testing
@testable import MetroCore

/// Quiet stations (no automatic passengers) with Phase 3 starting resources from `config`.
private func resourceState(stations: Int, config: GameConfiguration = .standard,
                           water: [Polygon] = []) -> GameState {
    var c = config
    c.passengerSpawnInterval = 1e9
    c.firstPassengerDelay = 1e9
    var state = makeState(stations: stations, config: c)
    state.map.water = water
    state.resources = ResourceStock(config: c)
    for i in state.stations.indices { state.stations[i].nextPassengerTime = 1e9 }
    return state
}

/// A vertical strip of water between station 1 (x = 500) and station 2 (x = 700).
private let strip = Polygon(points: [Vec2(560, 0), Vec2(640, 0), Vec2(640, 2000), Vec2(560, 2000)])

private func fill(_ station: Int, with count: Int, in state: inout GameState) {
    let i = state.stationIndex(StationID(station))!
    for _ in 0..<count {
        state.stations[i].waiting.append(Passenger(id: state.nextPassengerID, destination: .star,
                                                   origin: StationID(station), spawnTime: state.elapsed))
        state.nextPassengerID += 1
        state.passengersSpawned += 1
    }
}

private func step(_ state: inout GameState, seconds: Double, events: inout [GameEvent]) {
    var sim = SimulationEngine()
    for _ in 0..<Int((seconds / state.config.simulationStep).rounded()) { sim.step(&state, events: &events) }
}

@Suite("Resources")
struct ResourceTests {

    @Test func startingStockComesFromTheConfiguration() {
        let state = resourceState(stations: 3)
        let c = state.config
        #expect(state.resources == ResourceStock(credits: c.startingCredits, lineSlots: c.startingLineSlots,
                                                 locomotives: c.startingLocomotives, carriages: c.startingCarriages,
                                                 crossings: c.startingCrossings, expansions: c.startingExpansions,
                                                 motors: c.startingMotors))
        #expect(state.availableLineSlots == c.startingLineSlots)
    }

    @Test func lineSlotsLimitLinesUntilOneIsBought() throws {
        var state = resourceState(stations: 8)
        for k in 0..<3 {
            try RouteManager.apply(.createLine(stations: ids(2 * k + 1, 2 * k + 2), colorIndex: nil, isLoop: false), to: &state)
        }
        #expect(throws: RouteError.noLineAvailable) {
            try RouteManager.apply(.createLine(stations: ids(7, 8), colorIndex: nil, isLoop: false), to: &state)
        }
        state.resources.credits = state.config.priceLine
        try RouteManager.apply(.purchase(.line), to: &state)
        #expect(state.resources.credits == 0)
        try RouteManager.apply(.createLine(stations: ids(7, 8), colorIndex: nil, isLoop: false), to: &state)
        #expect(state.lines.count == 4)
    }

    @Test func purchasesCostCreditsAndFailCleanly() throws {
        let engine = GameEngine(state: resourceState(stations: 3))
        let before = engine.state
        #expect(engine.apply(.purchase(.locomotive)) == .failure(.notEnoughCredits))
        #expect(engine.state == before)

        var state = before
        state.resources.credits = 100
        for item in Purchase.allCases { try RouteManager.apply(.purchase(item), to: &state) }
        let spent = Purchase.allCases.reduce(0) { $0 + state.config.price(of: $1) }
        #expect(state.resources.credits == 100 - spent)
        #expect(state.resources.locomotives == before.resources.locomotives + 1)
        #expect(state.resources.crossings == before.resources.crossings + state.config.crossingsPerPurchase)
        #expect(state.resources.lineSlots == before.resources.lineSlots + 1)
        #expect(state.resources.carriages == 1 && state.resources.expansions == 1 && state.resources.motors == 1)

        state.resources.lineSlots = state.config.maxLines
        #expect(throws: RouteError.allLinesUnlocked) { try RouteManager.apply(.purchase(.line), to: &state) }
    }

    @Test func trainsComeFromStockAndGoBackWithTheirParts() throws {
        var state = resourceState(stations: 4)
        state.resources.locomotives = 1
        state.resources.carriages = 1
        state.resources.motors = 1
        let line = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        #expect(state.trains(on: line).count == 1 && state.resources.locomotives == 0)
        #expect(throws: RouteError.noTrainsLeft) { try RouteManager.apply(.addTrain(line), to: &state) }

        // A line built with no spare trains simply has none.
        let empty = try RouteManager.createLine(stations: ids(3, 4), colorIndex: nil, isLoop: false, in: &state)
        #expect(state.trains(on: empty).isEmpty)

        let train = state.trains[0].id
        try RouteManager.apply(.attachCarriage(train), to: &state)
        try RouteManager.apply(.fitMotor(train), to: &state)
        #expect(state.resources.carriages == 0 && state.resources.motors == 0)

        try RouteManager.apply(.withdrawTrain(train), to: &state)
        #expect(state.resources.locomotives == 0)            // still finishing its trip
        var events: [GameEvent] = []
        step(&state, seconds: 30, events: &events)
        #expect(state.trains.isEmpty)
        #expect(state.resources.locomotives == 1 && state.resources.carriages == 1 && state.resources.motors == 1)
    }

    @Test func carriagesAddSeatsWithinLimits() throws {
        var state = resourceState(stations: 3)
        state.resources.carriages = 5
        _ = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let train = state.trains[0].id
        let base = state.trains[0].capacity
        for _ in 0..<state.config.maxCarriagesPerTrain { try RouteManager.apply(.attachCarriage(train), to: &state) }
        #expect(state.train(train)!.capacity == base + state.config.maxCarriagesPerTrain * state.config.carriageCapacity)
        #expect(throws: RouteError.carriageLimitReached) { try RouteManager.apply(.attachCarriage(train), to: &state) }

        // Can't uncouple seats that people are sitting in.
        let full = state.train(train)!.capacity
        for k in 0..<full {
            state.trains[0].passengers.append(Passenger(id: 1000 + k, destination: .star, origin: StationID(1), spawnTime: 0))
        }
        #expect(throws: RouteError.carriageInUse) { try RouteManager.apply(.detachCarriage(train), to: &state) }
        state.trains[0].passengers.removeAll()
        try RouteManager.apply(.detachCarriage(train), to: &state)
        #expect(state.train(train)!.capacity == full - state.config.carriageCapacity)
        #expect(state.resources.carriages == 5 - state.config.maxCarriagesPerTrain + 1)
    }

    @Test func motorsMakeTrainsFasterAndCarriagesSlowerToAccelerate() {
        let c = GameConfiguration.standard
        var t = Train(id: TrainID(1), lineID: LineID(1), capacity: 6, at: StationID(1))
        let plain = (t.maxSpeed(c), t.acceleration(c))
        t.hasMotor = true
        #expect(t.maxSpeed(c) > plain.0 && t.acceleration(c) > plain.1)
        t.hasMotor = false
        t.carriages = 2
        #expect(t.maxSpeed(c) == plain.0 && t.acceleration(c) < plain.1)
    }

    @Test func motorTrainArrivesSooner() throws {
        func arrivalTime(motor: Bool) throws -> Double {
            var state = resourceState(stations: 6)
            state.resources.motors = 1
            _ = try RouteManager.createLine(stations: ids(1, 6), colorIndex: nil, isLoop: false, in: &state)
            if motor { try RouteManager.apply(.fitMotor(state.trains[0].id), to: &state) }
            var sim = SimulationEngine()
            var events: [GameEvent] = []
            while !events.contains(where: { if case .trainArrived(_, let s) = $0 { s == StationID(6) } else { false } }) {
                sim.step(&state, events: &events)
            }
            return state.elapsed
        }
        #expect(try arrivalTime(motor: true) < arrivalTime(motor: false) * 0.85)
    }
}

@Suite("Water crossings")
struct WaterCrossingTests {

    @Test func segmentsOverWaterUseCrossings() throws {
        let engine = GameEngine(state: resourceState(stations: 4, water: [strip]))
        #expect(RouteGeometry.terrain(SegmentKey(StationID(1), StationID(2)), positions: engine.state.stationPositions,
                                      map: engine.state.map) == .water)
        #expect(RouteGeometry.terrain(SegmentKey(StationID(2), StationID(3)), positions: engine.state.stationPositions,
                                      map: engine.state.map) == .dry)
        var state = engine.state
        state.resources.crossings = 0
        let dry = engine.state
        let blocked = GameEngine(state: state)
        #expect(blocked.apply(.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false)) == .failure(.noCrossingsLeft))
        #expect(blocked.state == state)
        _ = blocked.apply(.createLine(stations: ids(2, 3, 4), colorIndex: nil, isLoop: false))
        #expect(blocked.state.lines.count == 1)
        // Extending across the water is refused too.
        let line = blocked.state.lines[0].id
        #expect(blocked.apply(.extendLine(line, end: .start, station: StationID(1))) == .failure(.noCrossingsLeft))

        // With a crossing it works, and deleting the line frees the crossing again.
        var funded = dry
        funded.resources.crossings = 1
        let ok = GameEngine(state: funded)
        guard case .success(.lineCreated(let id)) = ok.apply(.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false)) else {
            Issue.record("line over water with a crossing was refused")
            return
        }
        #expect(ResourceManager.crossingsUsed(in: ok.state) == 1)
        #expect(ResourceManager.crossingsAvailable(in: ok.state) == 0)
        // A second line over the same water needs its own crossing.
        #expect(ok.apply(.createLine(stations: ids(2, 1), colorIndex: nil, isLoop: false)) == .failure(.noCrossingsLeft))
        _ = ok.apply(.deleteLine(id))
        #expect(ResourceManager.crossingsAvailable(in: ok.state) == 1)
    }

    @Test func linesAvoidWaterWhenOneBendStaysDry() throws {
        // A small pond on the diagonal-first path from A to B; the straight-first path misses it.
        let a = Vec2(1000, 1000), b = Vec2(1400, 1200)
        let pond = Polygon(points: [Vec2(1060, 1120), Vec2(1140, 1120), Vec2(1140, 1180), Vec2(1060, 1180)])
        var state = resourceState(stations: 2, water: [pond])
        state.stations[0].position = a
        state.stations[1].position = b
        let key = SegmentKey(StationID(1), StationID(2))
        #expect(RouteGeometry.terrain(key, positions: state.stationPositions, map: state.map) == .dryOnlyIf(straightFirst: true))
        let line = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        let g = try #require(RouteGeometry.build(lines: state.lines, positions: state.stationPositions, map: state.map)[line])
        #expect(!RouteGeometry.crossesWater(g.segments[0].points, map: state.map))
        #expect(ResourceManager.crossingsUsed(in: state) == 0)
    }

    @Test func waterSpansCoverOnlyTheWetPart() {
        var state = resourceState(stations: 2, water: [strip])
        state.stations[1].position = Vec2(700, 1000)
        let spans = RouteGeometry.waterSpans(of: [Vec2(500, 1000), Vec2(700, 1000)], map: state.map)
        #expect(spans.count == 1)
        #expect(abs(spans[0].first!.x - 560) < 1e-6 && abs(spans[0].last!.x - 640) < 1e-6)
    }
}

@Suite("Congestion, weeks and scoring")
struct ProgressionTests {

    @Test func overcrowdedStationEndsTheGameAfterItsTimer() {
        var state = resourceState(stations: 3)
        let c = state.config
        fill(2, with: c.stationCapacity + 1, in: &state)
        var events: [GameEvent] = []
        step(&state, seconds: c.overcrowdTime * 0.5, events: &events)
        #expect(!state.isOver)
        #expect(abs(state.stations[1].overcrowding - 0.5) < 0.01)
        #expect(events.contains(.stationOvercrowding(StationID(2))))

        step(&state, seconds: c.overcrowdTime * 0.5 + 0.1, events: &events)
        #expect(state.gameOver?.station == StationID(2))
        #expect(events.contains { if case .gameOver = $0 { true } else { false } })

        // Nothing moves and no command is accepted once it's over.
        let frozen = state
        step(&state, seconds: 5, events: &events)
        #expect(state == frozen)
        #expect(throws: RouteError.sessionOver) {
            try RouteManager.apply(.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false), to: &state)
        }
    }

    @Test func overcrowdingDrainsOnceTheQueueShrinks() {
        var state = resourceState(stations: 3)
        fill(1, with: state.config.stationCapacity + 3, in: &state)
        var events: [GameEvent] = []
        step(&state, seconds: state.config.overcrowdTime * 0.6, events: &events)
        let peak = state.stations[0].overcrowding
        state.stations[0].waiting.removeLast(4)
        step(&state, seconds: state.config.overcrowdRecoveryTime * 0.25, events: &events)
        #expect(state.stations[0].overcrowding < peak - 0.2)
        step(&state, seconds: state.config.overcrowdRecoveryTime, events: &events)
        #expect(state.stations[0].overcrowding == 0)
        #expect(!state.isOver)
    }

    @Test func expansionRaisesCapacity() throws {
        var state = resourceState(stations: 3)
        let c = state.config
        fill(1, with: c.stationCapacity + 2, in: &state)
        #expect(state.stations[0].isOvercrowded(c))
        #expect(throws: RouteError.noExpansionsLeft) { try RouteManager.apply(.expandStation(StationID(1)), to: &state) }
        state.resources.expansions = 5
        try RouteManager.apply(.expandStation(StationID(1)), to: &state)
        #expect(state.stations[0].capacity(c) == c.stationCapacity + c.expansionCapacity)
        #expect(!state.stations[0].isOvercrowded(c))
        for _ in 1..<c.maxExpansionsPerStation { try RouteManager.apply(.expandStation(StationID(1)), to: &state) }
        #expect(throws: RouteError.stationFullyExpanded) { try RouteManager.apply(.expandStation(StationID(1)), to: &state) }
    }

    @Test func weeksGrantCreditsWithAPerformanceBonus() {
        var state = resourceState(stations: 3)
        let c = state.config
        state.stats.deliveredThisWeek = c.deliveriesPerBonusCredit * 2 + 3
        var events: [GameEvent] = []
        step(&state, seconds: c.weekLength + 0.1, events: &events)
        #expect(state.week == 2)
        #expect(state.resources.credits == c.startingCredits + c.weeklyCredits + 2)
        #expect(state.stats.bestWeek == c.deliveriesPerBonusCredit * 2 + 3)
        #expect(state.stats.deliveredThisWeek == 0)
        #expect(events.contains(.weekStarted(WeeklyGrant(week: 2, base: c.weeklyCredits, performance: 2,
                                                          delivered: c.deliveriesPerBonusCredit * 2 + 3))))
        // The bonus is capped.
        let big = ResourceManager.weeklyGrant(startingWeek: 3, deliveredLastWeek: 10_000, config: c)
        #expect(big.performance == c.maxBonusCredits)
    }

    @Test func demandGrowsEachWeekDownToAFloor() {
        let c = GameConfiguration.standard
        #expect(DifficultyManager.passengerIntervalFactor(week: 1, config: c) == 1)
        let factors = (1...40).map { DifficultyManager.passengerIntervalFactor(week: $0, config: c) }
        #expect(zip(factors, factors.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(factors[3] < 1)
        #expect(factors.last == c.minPassengerIntervalFactor)
    }

    @Test func quickJourneysScoreMore() {
        let c = GameConfiguration.standard
        #expect(ScoringManager.points(forJourney: 5, config: c) == c.pointsPerPassenger + c.quickTripBonus)
        #expect(ScoringManager.points(forJourney: c.slowTripTime + 50, config: c) == c.pointsPerPassenger)
        let mid = ScoringManager.points(forJourney: (c.quickTripTime + c.slowTripTime) / 2, config: c)
        #expect(mid > c.pointsPerPassenger && mid < c.pointsPerPassenger + c.quickTripBonus)
    }

    @Test func deliveriesScoreAndFeedTheSummary() throws {
        var state = resourceState(stations: 2)              // 1 circle, 2 triangle
        let i = state.stationIndex(StationID(1))!
        state.stations[i].waiting.append(Passenger(id: 1, destination: .triangle, origin: StationID(1), spawnTime: 0))
        state.passengersSpawned = 1
        _ = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        var events: [GameEvent] = []
        step(&state, seconds: 15, events: &events)
        #expect(state.passengersDelivered == 1)
        #expect(state.stats.score == ScoringManager.points(forJourney: state.stats.journeyTimeTotal, config: state.config))
        let summary = ScoringManager.summary(of: state)
        #expect(summary.delivered == 1 && summary.score == state.stats.score && summary.bestWeek == 1)
        #expect(summary.averageJourney == state.stats.journeyTimeTotal)
    }

    /// Random play including every resource command: items are never created or lost (only bought), no
    /// station holds more crossings than owned, passengers are conserved, and the game ends cleanly.
    @Test func randomPlayKeepsResourcesBalanced() {
        for seed in UInt64(11)...14 {
            var rng = SeededRandom(seed: seed)
            let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[Int(seed) % 3])
            var bought: [Purchase: Int] = [:]
            let start = engine.state.resources
            for frame in 0..<(30 * 600) {
                engine.update(realDelta: 1.0 / 30)
                if frame % 40 == 0 {
                    let command = randomPlay(engine.state, rng: &rng)
                    if case .success(.purchased(let item)) = engine.apply(command) { bought[item, default: 0] += 1 }
                }
                let s = engine.state
                let r = s.resources
                let onTrains = (carriages: s.trains.reduce(0) { $0 + $1.carriages },
                                motors: s.trains.filter(\.hasMotor).count)
                guard r.locomotives + s.trains.count == start.locomotives + bought[.locomotive, default: 0],
                      r.carriages + onTrains.carriages == start.carriages + bought[.carriage, default: 0],
                      r.motors + onTrains.motors == start.motors + bought[.motor, default: 0],
                      r.expansions + s.stations.reduce(0, { $0 + $1.expansions })
                        == start.expansions + bought[.expansion, default: 0],
                      ResourceManager.crossingsUsed(in: s) <= r.crossings,
                      s.lines.count <= r.lineSlots, r.credits >= 0,
                      s.passengersSpawned == s.passengersDelivered + s.passengersInNetwork + s.passengersGaveUp else {
                    Issue.record("seed \(seed) frame \(frame): resources or passengers out of balance")
                    return
                }
                if s.isOver { break }
            }
        }
    }
}

private func randomPlay(_ state: GameState, rng: inout SeededRandom) -> GameCommand {
    let stations = state.stations.map(\.id)
    func anyStation() -> StationID { stations[rng.int(in: 0...(stations.count - 1))] }
    let trains = state.trains.filter { !$0.isRetiring }
    switch rng.int(in: 0...10) {
    case 10 where !state.lines.isEmpty:
        let line = state.lines[rng.int(in: 0...(state.lines.count - 1))]
        return .setExpress(line.id, !line.isExpress)
    case 0: return .purchase(Purchase.allCases[rng.int(in: 0...(Purchase.allCases.count - 1))])
    case 1 where !trains.isEmpty:
        let t = trains[rng.int(in: 0...(trains.count - 1))].id
        return [GameCommand.attachCarriage(t), .detachCarriage(t), .fitMotor(t), .removeMotor(t), .withdrawTrain(t)][rng.int(in: 0...4)]
    case 2: return .expandStation(anyStation())
    case 3 where !state.lines.isEmpty: return .deleteLine(state.lines[rng.int(in: 0...(state.lines.count - 1))].id)
    case 4 where !state.lines.isEmpty: return .addTrain(state.lines[rng.int(in: 0...(state.lines.count - 1))].id)
    case 5 where !state.lines.isEmpty:
        let line = state.lines[rng.int(in: 0...(state.lines.count - 1))]
        return .extendLine(line.id, end: rng.chance(0.5) ? .start : .end, station: anyStation())
    default:
        var picks: [StationID] = []
        for _ in 0..<rng.int(in: 2...4) {
            let s = anyStation()
            if !picks.contains(s) { picks.append(s) }
        }
        return .createLine(stations: picks, colorIndex: nil, isLoop: false)
    }
}
