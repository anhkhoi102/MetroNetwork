import Testing
@testable import MetroCore

/// Config with automatic passenger generation switched off, so tests place passengers by hand.
private func quietConfig() -> GameConfiguration {
    var c = GameConfiguration.standard
    c.passengerSpawnInterval = 1e9
    c.firstPassengerDelay = 1e9
    return c
}

/// Stations in a row 200 apart: 1 circle, 2 triangle, 3 square, 4 circle, ...
private func quietState(stations: Int) -> GameState {
    var state = makeState(stations: stations, config: quietConfig())
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

/// Runs the simulation for `seconds`, returning (train, station) arrivals in order.
@discardableResult
private func run(_ state: inout GameState, seconds: Double, sim: inout SimulationEngine) -> [(TrainID, StationID)] {
    var events: [GameEvent] = []
    let steps = Int(seconds / state.config.simulationStep)
    for _ in 0..<steps { sim.step(&state, events: &events) }
    return events.compactMap { if case let .trainArrived(t, s) = $0 { (t, s) } else { nil } }
}

private func run(_ state: inout GameState, seconds: Double) -> [(TrainID, StationID)] {
    var sim = SimulationEngine()
    return run(&state, seconds: seconds, sim: &sim)
}

private func conserved(_ state: GameState) -> Bool {
    state.passengersSpawned == state.passengersDelivered + state.passengersInNetwork + state.passengersGaveUp
}

@Suite("Trains")
struct TrainTests {

    @Test func newLineGetsATrainAtItsFirstStation() throws {
        var state = quietState(stations: 3)
        let line = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let trains = state.trains(on: line)
        #expect(trains.count == 1)
        #expect(trains[0].to == StationID(1))
        #expect(trains[0].capacity == state.config.trainCapacity)
    }

    @Test func trainShuttlesAndTurnsAroundAtTheEnds() throws {
        var state = quietState(stations: 3)
        try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let stops = run(&state, seconds: 40).map(\.1)
        #expect(Array(stops.prefix(5)) == ids(2, 3, 2, 1, 2))
    }

    @Test func loopTrainKeepsGoingRound() throws {
        var state = quietState(stations: 3)
        try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: true, in: &state)
        let stops = run(&state, seconds: 40).map(\.1)
        #expect(Array(stops.prefix(5)) == ids(2, 3, 1, 2, 3))
    }

    @Test func trainAcceleratesBrakesAndRespectsSpeedLimit() throws {
        var state = quietState(stations: 2)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        var maxSpeed = 0.0
        var arrived = false
        for _ in 0..<600 where !arrived {
            sim.step(&state, events: &events)
            maxSpeed = max(maxSpeed, state.trains[0].speed)
            arrived = events.contains { if case .trainArrived = $0 { true } else { false } }
        }
        #expect(arrived)
        #expect(maxSpeed <= state.config.trainMaxSpeed + 1e-9)
        #expect(maxSpeed > state.config.trainMaxSpeed * 0.5)
        #expect(state.trains[0].speed == 0)
    }

    @Test func addAndRemoveTrainsWithinLimits() throws {
        var state = quietState(stations: 4)
        let line = try RouteManager.createLine(stations: ids(1, 2, 3, 4), colorIndex: nil, isLoop: false, in: &state)
        for _ in 1..<state.config.maxTrainsPerLine { try TrainManager.addTrain(to: line, in: &state) }
        #expect(state.trains(on: line).count == state.config.maxTrainsPerLine)
        #expect(throws: RouteError.trainLimitReached) { try TrainManager.addTrain(to: line, in: &state) }
        // Spread out: the second train starts at the far end, not on top of the first.
        #expect(Set(state.trains(on: line).map(\.to)).count > 1)

        try TrainManager.removeTrain(from: line, in: &state)
        #expect(state.trains(on: line).count == state.config.maxTrainsPerLine - 1)
        let specific = state.trains(on: line)[0].id
        try TrainManager.withdraw(specific, in: &state)
        #expect(throws: RouteError.unknownTrain(specific)) { try TrainManager.withdraw(specific, in: &state) }
        try TrainManager.addTrain(to: line, in: &state)              // back to max − 1 serving
        #expect(state.trains.count == state.config.maxTrainsPerLine + 1) // two withdrawn trains still finishing
        run(&state, seconds: 30)
        #expect(state.trains.count == state.config.maxTrainsPerLine - 1)
    }
}

@Suite("Passengers")
struct PassengerTests {

    @Test func directJourney() throws {
        var state = quietState(stations: 3)
        addPassenger(at: 1, wanting: .square, in: &state)          // station 3 is the square
        try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        run(&state, seconds: 30)
        #expect(state.passengersDelivered == 1)
        #expect(conserved(state))
    }

    @Test func journeyWithTransfer() throws {
        var state = quietState(stations: 3)
        addPassenger(at: 1, wanting: .square, in: &state)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        try RouteManager.createLine(stations: ids(2, 3), colorIndex: nil, isLoop: false, in: &state)

        var sim = SimulationEngine()
        var waitedAtInterchange = false
        for _ in 0..<(60 * 30) {
            var events: [GameEvent] = []
            sim.step(&state, events: &events)
            if state.station(StationID(2))!.waiting.contains(where: { $0.destination == .square }) {
                waitedAtInterchange = true
            }
        }
        #expect(waitedAtInterchange)
        #expect(state.passengersDelivered == 1)
    }

    @Test func passengersOnlyBoardTrainsThatHelp() throws {
        var state = quietState(stations: 4)
        // Wants a square; the only line goes the other way (1-2), so nobody boards.
        addPassenger(at: 1, wanting: .square, in: &state)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        run(&state, seconds: 20)
        #expect(state.station(StationID(1))!.waiting.count == 1)
        #expect(state.trains.allSatisfy { $0.passengers.isEmpty })
    }

    @Test func capacityIsRespected() throws {
        var state = quietState(stations: 2)
        for _ in 0..<10 { addPassenger(at: 1, wanting: .triangle, in: &state) }
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        for _ in 0..<(30 * 40) {
            sim.step(&state, events: &events)
            #expect(state.trains.allSatisfy { $0.passengers.count <= $0.capacity })
        }
        #expect(state.passengersDelivered == 10)
    }

    @Test func passengerChoosesTheTrainHeadingTheRightWay() throws {
        var state = quietState(stations: 3)
        // Middle station 2 (triangle) wants the square at 3, not the circle end at 1.
        addPassenger(at: 2, wanting: .square, in: &state)
        try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let network = NetworkGraph(state: state)
        #expect(network.shouldBoard(at: StationID(2), line: state.lines[0].id, direction: 1, to: .square))
        #expect(!network.shouldBoard(at: StationID(2), line: state.lines[0].id, direction: -1, to: .square))
    }

    @Test func transfersCostMoreThanDirectRides() throws {
        var state = quietState(stations: 3)
        try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let direct = NetworkGraph(state: state).cost(from: StationID(1), to: .square)

        var split = quietState(stations: 3)
        try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &split)
        try RouteManager.createLine(stations: ids(2, 3), colorIndex: nil, isLoop: false, in: &split)
        let viaTransfer = NetworkGraph(state: split).cost(from: StationID(1), to: .square)

        #expect(direct.isFinite && viaTransfer.isFinite)
        // Same total expected wait (two short lines each run twice as often), plus one extra boarding.
        #expect(abs(viaTransfer - direct - split.config.boardingCost) < 1e-6)
        #expect(NetworkGraph(state: split).cost(from: StationID(1), to: .diamond) == .infinity)
    }

    @Test func generationOnlyTargetsShapesThatExistElsewhere() {
        var state = makeState(stations: 2)                       // circle + triangle
        var events: [GameEvent] = []
        for _ in 0..<50 { PassengerManager.spawnPassenger(at: 0, in: &state, events: &events) }
        #expect(state.stations[0].waiting.allSatisfy { $0.destination == .triangle })

        var lonely = makeState(stations: 1)
        #expect(PassengerManager.spawnPassenger(at: 0, in: &lonely, events: &events) == nil)
    }

    @Test func generationStopsAtTheWaitingCap() {
        var state = makeState(stations: 2)
        var events: [GameEvent] = []
        for _ in 0..<(30 * 600) {
            state.elapsed += state.config.simulationStep
            PassengerManager.update(&state, events: &events)
        }
        #expect(state.stations.allSatisfy { $0.waiting.count <= state.config.maxWaitingPerStation })
        #expect(state.stations[0].waiting.count == state.config.maxWaitingPerStation)
    }
}

@Suite("Line edits with trains running")
struct LineEditWithTrainsTests {

    @Test func deletingALineDropsPassengersAtTheNextStation() throws {
        var state = quietState(stations: 3)
        for _ in 0..<3 { addPassenger(at: 1, wanting: .square, in: &state) }
        let line = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        var sim = SimulationEngine()
        // Run until the train is under way with passengers, then delete the line.
        var events: [GameEvent] = []
        while !(state.trains[0].phase == .moving && !state.trains[0].passengers.isEmpty) {
            sim.step(&state, events: &events)
        }
        let heading = state.trains[0].to
        try RouteManager.deleteLine(line, in: &state)
        #expect(state.trains[0].isRetiring)
        run(&state, seconds: 20, sim: &sim)
        #expect(state.trains.isEmpty)
        #expect(state.station(heading)!.waiting.count == 3)
        #expect(conserved(state))
    }

    @Test func removingTheNextStopUnloadsThereThenRejoinsTheLine() throws {
        var state = quietState(stations: 4)
        for _ in 0..<2 { addPassenger(at: 1, wanting: .circle, in: &state) }   // station 4 is a circle
        let line = try RouteManager.createLine(stations: ids(1, 2, 3, 4), colorIndex: nil, isLoop: false, in: &state)
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        while state.trains[0].to != StationID(2) || state.trains[0].phase != .moving {
            sim.step(&state, events: &events)
        }
        _ = try RouteManager.removeStation(StationID(2), from: line, in: &state)
        let stops = run(&state, seconds: 60, sim: &sim).map(\.1)
        // Arrives at the removed station (no teleport), then continues on the line.
        #expect(stops.first == StationID(2))
        #expect(stops.dropFirst().allSatisfy { $0 != StationID(2) })
        #expect(state.trains.count == 1 && state.trains[0].lineID == line)
        #expect(conserved(state))
    }

    @Test func randomEditsNeverLoseOrDuplicatePassengers() {
        for seed in UInt64(1)...6 {
            var rng = SeededRandom(seed: seed)
            let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[Int(seed) % 3])
            for step in 0..<(30 * 240) {
                engine.update(realDelta: 1.0 / 30)
                if step % 45 == 0 { engine.apply(randomCommand(engine.state, rng: &rng)) }
                let s = engine.state
                guard conserved(s) else {
                    Issue.record("seed \(seed) step \(step): passengers not conserved")
                    return
                }
                for t in s.trains {
                    #expect(t.passengers.count <= t.capacity)
                    #expect(s.station(t.from) != nil && s.station(t.to) != nil)
                    if let line = t.lineID { #expect(s.line(line) != nil) }
                }
                for line in s.lines {
                    #expect(s.trains(on: line.id).count <= s.config.maxTrainsPerLine)
                }
            }
            #expect(engine.state.passengersDelivered > 0, "seed \(seed): nobody delivered")
        }
    }
}

/// A plausible random player action.
private func randomCommand(_ state: GameState, rng: inout SeededRandom) -> GameCommand {
    let stations = state.stations.map(\.id)
    func anyStation() -> StationID { stations[rng.int(in: 0...(stations.count - 1))] }
    guard let line = state.lines.isEmpty ? nil : state.lines[rng.int(in: 0...(state.lines.count - 1))],
          rng.chance(0.8) else {
        var picks: [StationID] = []
        for _ in 0..<rng.int(in: 2...4) {
            let s = anyStation()
            if !picks.contains(s) { picks.append(s) }
        }
        return .createLine(stations: picks, colorIndex: nil, isLoop: false)
    }
    switch rng.int(in: 0...6) {
    case 0: return .extendLine(line.id, end: rng.chance(0.5) ? .start : .end, station: anyStation())
    case 1: return .insertStation(line.id, station: anyStation(), segment: rng.int(in: 0...max(0, line.segments.count - 1)))
    case 2: return .removeStation(line.id, station: line.stations[rng.int(in: 0...(line.stations.count - 1))])
    case 3: return .deleteLine(line.id)
    case 4: return .addTrain(line.id)
    case 5: return rng.chance(0.5) || state.trains.isEmpty
        ? .removeTrain(line.id) : .withdrawTrain(state.trains[rng.int(in: 0...(state.trains.count - 1))].id)
    default: return .setStations(line.id, stations: line.stations.shuffled(using: &rng), isLoop: rng.chance(0.3))
    }
}
