import Testing
@testable import MetroCore

/// Quiet stations in a row (no automatic passengers), plenty of resources.
private func quiet(_ count: Int) -> GameState {
    var c = GameConfiguration.standard
    c.passengerSpawnInterval = 1e9
    c.firstPassengerDelay = 1e9
    var state = makeState(stations: count, config: c)
    for i in state.stations.indices { state.stations[i].nextPassengerTime = 1e9 }
    return state
}

private func addPassenger(at station: Int, wanting shape: StationShape, in state: inout GameState) {
    let i = state.stationIndex(StationID(station))!
    state.stations[i].waiting.append(Passenger(id: state.nextPassengerID, destination: shape,
                                               origin: StationID(station), spawnTime: state.elapsed))
    state.nextPassengerID += 1
    state.passengersSpawned += 1
}

private func run(_ state: inout GameState, seconds: Double, sim: inout SimulationEngine, events: inout [GameEvent]) {
    for _ in 0..<Int((seconds / state.config.simulationStep).rounded()) { sim.step(&state, events: &events) }
}

@Suite("Express lines and stop rules")
struct ExpressTests {

    @Test func expressStopsOnlyAtEndsInterchangesAndSpecials() throws {
        var state = quiet(5)
        let line = try RouteManager.createLine(stations: ids(1, 2, 3, 4, 5), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.createLine(stations: ids(3, 1), colorIndex: nil, isLoop: false, in: &state)   // 3 becomes an interchange
        try RouteManager.apply(.setExpress(line, true), to: &state)
        state.stations[3].special = .hub                                                               // station 4
        let l = try #require(state.line(line))
        #expect(StopRules.stopMask(for: l, in: state) == [true, false, true, true, true])
        // Without enough express stops the service stops everywhere.
        var loop = quiet(4)
        let ring = try RouteManager.createLine(stations: ids(1, 2, 3, 4), colorIndex: nil, isLoop: true, in: &loop)
        try RouteManager.apply(.setExpress(ring, true), to: &loop)
        #expect(StopRules.stopMask(for: loop.line(ring)!, in: loop) == [true, true, true, true])
    }

    @Test func expressRunsThroughAndPassengersPlanForIt() throws {
        func timeToFarEnd(express: Bool) throws -> (Double, GameState) {
            var state = quiet(5)                      // shapes: circle, triangle, square, circle, triangle
            let line = try RouteManager.createLine(stations: ids(1, 2, 3, 4, 5), colorIndex: nil, isLoop: false, in: &state)
            if express { try RouteManager.apply(.setExpress(line, true), to: &state) }
            addPassenger(at: 2, wanting: .circle, in: &state)       // at a skipped station
            addPassenger(at: 1, wanting: .triangle, in: &state)     // nearest triangle by express: station 5
            // Start the train at station 1 heading for 5.
            state.trains[0].from = StationID(1); state.trains[0].to = StationID(1); state.trains[0].direction = 1
            var sim = SimulationEngine()
            var events: [GameEvent] = []
            let net = sim.currentNetwork(for: state)
            if express {
                #expect(!net.shouldBoard(at: StationID(2), line: line, direction: 1, to: .circle))
                #expect(!net.shouldBoard(at: StationID(2), line: line, direction: -1, to: .circle))
            }
            var t = 0.0
            while !(state.trains[0].to == StationID(5) && state.trains[0].isDwelling), t < 120 {
                sim.step(&state, events: &events)
                t += state.config.simulationStep
            }
            return (t, state)
        }
        let (normal, _) = try timeToFarEnd(express: false)
        let (fast, state) = try timeToFarEnd(express: true)
        #expect(fast < normal - 2)
        // The passenger at the skipped station is still waiting; the other one rode to the far end.
        #expect(state.station(StationID(2))!.waiting.count == 1)
        #expect(state.passengersDelivered == 1)
    }

    @Test func closedStationIsRunThroughAndFrozen() throws {
        var state = quiet(3)
        try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        for _ in 0..<(state.config.stationCapacity + 2) { addPassenger(at: 2, wanting: .square, in: &state) }
        state.stations[1].overcrowding = 0.5
        state.stations[1].nextPassengerTime = 0
        state.events = [NetworkEvent(id: 1, kind: .closure(StationID(2)), announced: 0, start: 0, end: 30)]
        state.events[0].started = true
        state.revision += 1
        let waiting = state.stations[1].waiting.count
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        run(&state, seconds: 25, sim: &sim, events: &events)
        #expect(state.stations[1].waiting.count == waiting)       // nobody got on, nobody new arrived
        #expect(state.stations[1].overcrowding == 0.5)            // timer frozen
        #expect(state.passengersDelivered == 0)
        run(&state, seconds: 20, sim: &sim, events: &events)      // reopened at t = 30
        #expect(!state.isClosed(StationID(2)))
        #expect(state.passengersDelivered > 0)
    }
}

@Suite("Routing with headways, interchanges and special stations")
struct RoutingTests {

    @Test func moreTrainsMakeALineCheaperAndNoTrainsMakeItUnusable() throws {
        var state = quiet(3)
        let line = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let one = NetworkGraph(state: state).cost(from: StationID(1), to: .square)
        try TrainManager.addTrain(to: line, in: &state)
        try TrainManager.addTrain(to: line, in: &state)
        let three = NetworkGraph(state: state).cost(from: StationID(1), to: .square)
        #expect(three < one)
        state.trains.removeAll()
        #expect(NetworkGraph(state: state).cost(from: StationID(1), to: .square) == .infinity)
    }

    @Test func interchangeStationsMakeTransfersCheaper() throws {
        var state = quiet(3)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.createLine(stations: ids(2, 3), colorIndex: nil, isLoop: false, in: &state)
        let plain = NetworkGraph(state: state).cost(from: StationID(1), to: .square)
        state.stations[1].special = .interchange
        state.revision += 1
        #expect(NetworkGraph(state: state).cost(from: StationID(1), to: .square) < plain)
    }

    @Test func heritageStationsLimitLines() throws {
        let engine = GameEngine(state: {
            var s = quiet(5)
            s.stations[2].special = .heritage                     // station 3
            return s
        }())
        _ = engine.apply(.createLine(stations: ids(1, 3), colorIndex: nil, isLoop: false))
        _ = engine.apply(.createLine(stations: ids(2, 3), colorIndex: nil, isLoop: false))
        let before = engine.state
        #expect(engine.apply(.createLine(stations: ids(3, 4), colorIndex: nil, isLoop: false)) == .failure(.heritageLineLimit))
        #expect(engine.state == before)
        // Lines that don't add a third line there are fine.
        #expect(engine.apply(.extendLine(before.lines[0].id, end: .start, station: StationID(5))) == .success(.lineChanged(before.lines[0].id)))
    }

    @Test func specialStationCapacities() throws {
        var state = quiet(3)
        let c = state.config
        state.resources.expansions = 3
        state.stations[0].special = .grand
        state.stations[1].special = .hub
        #expect(state.stations[0].capacity(c) == c.stationCapacity + c.grandStationCapacity)
        #expect(state.stations[1].capacity(c) == c.stationCapacity + c.specialBonusCapacity)
        #expect(throws: RouteError.cantExpandGrand) { try RouteManager.apply(.expandStation(StationID(1)), to: &state) }
        #expect(DemandManager.spawnMultiplier(forStationAt: 1, in: state)
                > DemandManager.spawnMultiplier(forStationAt: 2, in: state))
    }
}

@Suite("Demand, rush hours and events")
struct DemandTests {

    @Test func centralShapesAttractMoreTrips() {
        var state = quiet(3)
        state.stations[1].attraction = 2                         // central triangle
        state.stations[2].attraction = 1                         // outlying square
        let weights = Dictionary(uniqueKeysWithValues: DemandManager.destinationWeights(forStationAt: 0, in: state))
        #expect(weights[.triangle] == 2 && weights[.square] == 1 && weights[.circle] == nil)
    }

    @Test func stationsGetCharacterFromWhereTheyAre() {
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[0], config: .noGameOver)
        for _ in 0..<(60 * 60 * 6) { engine.update(realDelta: 1.0 / 60) }
        let s = engine.state
        let c = s.config
        #expect(s.stations.allSatisfy { $0.demand >= c.minStationDemand - 1e-9 && $0.demand <= c.maxStationDemand + 1e-9 })
        #expect(s.stations.allSatisfy { $0.centrality >= 0 && $0.centrality <= 1 })
        let central = s.stations.max { $0.centrality < $1.centrality }!
        let outer = s.stations.min { $0.centrality < $1.centrality }!
        #expect(central.attraction > outer.attraction)
        #expect(s.stations.prefix(c.specialStationsAfter).allSatisfy { $0.special == nil })
        for kind in SpecialStation.allCases {
            #expect(s.stations.filter { $0.special == kind }.count <= c.maxStationsPerSpecial)
        }
    }

    @Test func rushHoursArePlannedForTheWeekOnWeekdays() {
        var state = quiet(3)
        let c = state.config
        state.week = c.rushHoursFromWeek
        state.elapsed = Double(state.week - 1) * c.weekLength
        DemandManager.planRushHours(forWeek: state.week, in: &state)
        #expect(state.rushHours.count == c.rushHoursPerWeek)
        let day = c.weekLength / 7
        for r in state.rushHours {
            let dayOfWeek = Int((r.start - state.elapsed) / day)
            #expect((0...4).contains(dayOfWeek))
            #expect(r.end > r.start)
        }
        #expect(state.rushHours[0].flow == .toCentre && state.rushHours[1].flow == .fromCentre)
        // Morning rush: the outskirts get busier, the centre barely changes.
        let morning = state.rushHours[0]
        #expect(morning.multiplier(centrality: 0) == morning.intensity)
        #expect(morning.multiplier(centrality: 1) == 1)
        // Later weeks are stronger, up to the cap.
        var later = state
        later.week = 30
        DemandManager.planRushHours(forWeek: 30, in: &later)
        #expect(later.rushHours.last!.intensity == c.maxRushIntensity)
        // Before the first rush week, none.
        var early = quiet(3)
        DemandManager.planRushHours(forWeek: 1, in: &early)
        #expect(early.rushHours.isEmpty)
    }

    @Test func maintenanceTakesATrainOutThenBringsItBack() throws {
        var state = quiet(4)
        let line = try RouteManager.createLine(stations: ids(1, 2, 3, 4), colorIndex: nil, isLoop: false, in: &state)
        try TrainManager.addTrain(to: line, in: &state)
        let train = state.trains[0].id
        for _ in 0..<3 { addPassenger(at: 1, wanting: .circle, in: &state) }     // station 4 is a circle
        state.events = [NetworkEvent(id: 1, kind: .maintenance(train), announced: 0, start: 3, end: 23)]
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        run(&state, seconds: 15, sim: &sim, events: &events)
        let t = state.train(train)!
        #expect(t.maintenanceUntil == 23)
        #expect(t.passengers.isEmpty && t.isDwelling)
        run(&state, seconds: 30, sim: &sim, events: &events)
        #expect(state.train(train)!.maintenanceUntil == nil)
        #expect(state.events.isEmpty)
        #expect(events.contains { if case .networkEventStarted = $0 { true } else { false } })
        #expect(events.contains { if case .networkEventEnded = $0 { true } else { false } })
    }

    @Test func eventsAreAnnouncedAheadAndNeverOverlap() {
        for seed in UInt64(31)...33 {
            let engine = GameSessionManager.newSession(preset: MapPreset.random(seed: seed), config: .noGameOver)
            var player = AutoPlayer()
            var announced: [Int: Double] = [:]
            var started: Set<Int> = []
            var kinds: Set<String> = []
            while engine.state.week < 10 {
                player.act(on: engine)
                engine.update(realDelta: 0.1)
                for event in engine.drainEvents() {
                    switch event {
                    case .networkEventAnnounced(let e):
                        #expect(engine.state.week >= engine.state.config.eventsFromWeek)
                        #expect(engine.state.events.count == 1)
                        announced[e.id] = e.announced
                        #expect(abs(e.start - e.announced - engine.state.config.eventWarning) < 1e-9)
                        kinds.insert("\(e.kind)".components(separatedBy: "(").first!)
                    case .networkEventStarted(let e):
                        #expect(announced[e.id] != nil)
                        started.insert(e.id)
                    default: break
                    }
                }
                #expect(engine.state.events.count <= 1)
                let st = engine.state
                guard st.passengersSpawned == st.passengersDelivered + st.passengersInNetwork + st.passengersGaveUp else {
                    Issue.record("seed \(seed) at \(st.elapsed): passengers not conserved with events running")
                    return
                }
            }
            #expect(announced.count >= 3, "seed \(seed): only \(announced.count) events")
            #expect(kinds.count >= 2, "seed \(seed): kinds \(kinds)")
            #expect(engine.state.trains.allSatisfy { t in t.maintenanceUntil.map { $0 > engine.state.elapsed - 60 } ?? true })
        }
    }
}

@Suite("Network efficiency")
struct EfficiencyTests {

    @Test func factorsAndScore() {
        let c = GameConfiguration.standard
        var e = NetworkEfficiency()
        e.averageWait = 0; e.averageJourney = c.efficiencyBestJourney; e.utilization = c.efficiencyGoodLoad; e.congestion = 0
        #expect(abs(EfficiencyManager.score(e, config: c) - 100) < 1e-9)
        e.averageWait = c.efficiencyWorstWait; e.averageJourney = c.efficiencyWorstJourney; e.utilization = 0; e.congestion = 1
        #expect(EfficiencyManager.score(e, config: c) == 0)
    }

    @Test func deliveriesFeedTheScore() throws {
        var state = quiet(2)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        for _ in 0..<4 { addPassenger(at: 1, wanting: .triangle, in: &state) }
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        run(&state, seconds: 20, sim: &sim, events: &events)
        #expect(state.passengersDelivered == 4)
        #expect(state.efficiency.hasData)
        #expect(state.efficiency.score > 0 && state.efficiency.score <= 100)
        #expect(state.efficiency.sessionAverage != nil)
        #expect(ScoringManager.summary(of: state).efficiency != nil)
    }
}
