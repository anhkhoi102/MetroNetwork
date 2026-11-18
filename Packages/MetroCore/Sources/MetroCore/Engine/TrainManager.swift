import Foundation

/// Train lifecycle and movement. Trains travel station to station; everything that happens to passengers
/// happens at stations, so no passenger ever moves without a train carrying them.
///
/// Line edits never strand anyone:
/// - a train heading for a station that was taken off its line still arrives there, lets everyone off,
///   then drives (empty) to the nearest station still on the line and resumes service;
/// - a train whose line was deleted, or that was withdrawn, finishes its trip, lets everyone off and is removed.
public enum TrainManager {

    // MARK: Commands

    @discardableResult
    public static func addTrain(to lineID: LineID, in state: inout GameState) throws(RouteError) -> TrainID {
        guard let line = state.line(lineID) else { throw .unknownLine(lineID) }
        let existing = state.trains(on: lineID)
        guard existing.count < state.config.maxTrainsPerLine else { throw .trainLimitReached }
        guard state.resources.locomotives > 0 else { throw .noTrainsLeft }

        // Start at the stop furthest (in stops) from the trains already running, to spread them out.
        let n = line.stations.count
        let occupied = existing.compactMap { line.stations.firstIndex(of: $0.to) }
        func gap(_ i: Int) -> Int {
            occupied.map { j -> Int in
                let d = abs(i - j)
                return line.isLoop ? min(d, n - d) : d
            }.min() ?? Int.max
        }
        let start = (0..<n).max { a, b in gap(a) < gap(b) || (gap(a) == gap(b) && a > b) } ?? 0
        let direction = (!line.isLoop && start == n - 1) ? -1 : 1

        state.resources.locomotives -= 1
        let id = TrainID(state.nextTrainID)
        state.nextTrainID += 1
        state.trains.append(Train(id: id, lineID: lineID, capacity: state.config.trainCapacity,
                                  at: line.stations[start], direction: direction,
                                  phase: .dwelling(remaining: state.config.dwellBase)))
        state.revision += 1          // headways changed: route planning must be rebuilt
        return id
    }

    /// Withdraws one train from a line (the emptiest). It finishes its trip and is then removed.
    @discardableResult
    public static func removeTrain(from lineID: LineID, in state: inout GameState) throws(RouteError) -> TrainID {
        guard state.line(lineID) != nil else { throw .unknownLine(lineID) }
        let candidates = state.trains.indices.filter { state.trains[$0].lineID == lineID }
        guard let index = candidates.min(by: { a, b in
            let pa = state.trains[a].passengers.count, pb = state.trains[b].passengers.count
            return pa < pb || (pa == pb && state.trains[a].id > state.trains[b].id)
        }) else { throw .noTrainToRemove }
        state.trains[index].lineID = nil
        state.revision += 1
        return state.trains[index].id
    }

    /// Withdraws a specific train. It finishes its trip, lets everyone off, then is removed.
    public static func withdraw(_ id: TrainID, in state: inout GameState) throws(RouteError) {
        guard let index = state.trains.firstIndex(where: { $0.id == id }), !state.trains[index].isRetiring else {
            throw .unknownTrain(id)
        }
        state.trains[index].lineID = nil
        state.revision += 1
    }

    /// Called when a line is built: it gets a train from stock if there is one (a line can exist without
    /// trains; the player adds one later).
    static func lineCreated(_ id: LineID, in state: inout GameState) {
        for _ in 0..<min(state.config.trainsPerNewLine, state.config.maxTrainsPerLine) {
            _ = try? addTrain(to: id, in: &state)
        }
    }

    /// Called when a line is deleted: its trains retire.
    static func lineDeleted(_ id: LineID, in state: inout GameState) {
        for i in state.trains.indices where state.trains[i].lineID == id {
            state.trains[i].lineID = nil
        }
    }

    // MARK: Simulation

    /// Advances every train by `dt` seconds.
    static func update(_ state: inout GameState, dt: Double, network: NetworkGraph, events: inout [GameEvent]) {
        var finished: [TrainID] = []
        // Looked up once per step instead of per train (stations never move; skipping only happens with an
        // express line or a closure, which are rare).
        let lookup = MoveLookup(positions: state.stationPositions,
                                anySkips: state.lines.contains(where: \.isExpress) || !state.events.isEmpty)
        for index in state.trains.indices {
            switch state.trains[index].phase {
            case .dwelling(let remaining):
                if remaining - dt > 0 {
                    state.trains[index].phase = .dwelling(remaining: remaining - dt)
                } else if depart(index, in: &state, network: network, events: &events) {
                    finished.append(state.trains[index].id)
                }
            case .moving:
                if move(index, dt: dt, in: &state, lookup: lookup) {
                    if arrive(index, in: &state, network: network, events: &events) {
                        finished.append(state.trains[index].id)
                    }
                }
            }
        }
        if !finished.isEmpty {
            for train in state.trains where finished.contains(train.id) {
                ResourceManager.returnToStock(train, in: &state)
            }
            state.trains.removeAll { finished.contains($0.id) }
            state.revision += 1
            for id in finished { events.append(.trainRemoved(id)) }
        }
    }

    /// Length of the trip a train is on.
    public static func tripLength(_ train: Train, in state: GameState) -> Double {
        guard train.from != train.to, let a = state.station(train.from)?.position,
              let b = state.station(train.to)?.position else { return 0 }
        return RouteGeometry.octilinearLength(a, b)
    }

    /// Per-step lookups shared by all trains.
    private struct MoveLookup {
        let positions: [StationID: Vec2]
        let anySkips: Bool
    }

    /// Accelerates towards cruising speed and brakes to stop exactly at the next station.
    /// - Returns: true when the train has arrived.
    private static func move(_ index: Int, dt: Double, in state: inout GameState, lookup: MoveLookup) -> Bool {
        let c = state.config
        var train = state.trains[index]
        var length = 0.0
        if train.from != train.to, let a = lookup.positions[train.from], let b = lookup.positions[train.to] {
            length = RouteGeometry.octilinearLength(a, b)
        }
        let remaining = max(0, length - train.progress)
        let acceleration = train.acceleration(c)
        // A train running through a station (closed, or skipped by an express) doesn't brake for it,
        // unless it has to turn round there.
        let passing = lookup.anySkips && runsThrough(train, in: state)
        let brakingLimit = passing ? Double.infinity : (2 * acceleration * remaining).squareRoot()
        let speed = max(c.trainMinSpeed, min(train.maxSpeed(c), train.speed + acceleration * dt, brakingLimit))
        train.speed = speed
        train.progress += speed * dt
        let arrived = train.progress >= length - 1e-6
        if arrived {
            train.progress = length
            if !passing { train.speed = 0 }
        }
        state.trains[index] = train
        return arrived
    }

    /// True when the train will run through its next station without stopping or turning round there.
    static func runsThrough(_ train: Train, in state: GameState) -> Bool {
        guard let lineID = train.lineID, let line = state.line(lineID),
              let i = line.stations.firstIndex(of: train.to),
              !StopRules.stops(at: train.to, line: line, in: state) else { return false }
        return NetworkGraph.nextIndex(i, direction: train.direction, count: line.stations.count, loop: line.isLoop) != nil
    }

    /// The train has reached `to`. Passengers get off and on; the train starts dwelling.
    /// - Returns: true when the train should be removed (it was retiring).
    private static func arrive(_ index: Int, in state: inout GameState, network: NetworkGraph,
                               events: inout [GameEvent]) -> Bool {
        let stationID = state.trains[index].to
        events.append(.trainArrived(state.trains[index].id, stationID))
        guard let lineID = state.trains[index].lineID, let line = state.line(lineID) else {
            unloadAll(index, at: stationID, in: &state, events: &events)
            return true
        }
        guard let i = line.stations.firstIndex(of: stationID) else {
            // The station was taken off this line while we were on our way: everyone gets off here.
            let moved = unloadAll(index, at: stationID, in: &state, events: &events)
            state.trains[index].phase = .dwelling(remaining: dwellTime(moved: moved, at: stationID, in: state))
            return false
        }
        let direction = departingDirection(at: i, current: state.trains[index].direction, line: line)
        state.trains[index].direction = direction

        // Not stopping here (closed, or skipped by an express): carry straight on.
        guard StopRules.stops(at: stationID, line: line, in: state) else {
            continueThrough(index, from: i, line: line, in: &state)
            return false
        }
        // In maintenance: everyone gets off at this stop, and the train waits here until the work is done.
        if let until = state.trains[index].maintenanceUntil {
            let moved = unloadAll(index, at: stationID, in: &state, events: &events)
            state.trains[index].phase = .dwelling(remaining: max(dwellTime(moved: moved, at: stationID, in: state),
                                                                 until - state.elapsed))
            return false
        }

        var moved = 0
        if let s = state.stationIndex(stationID) {
            let shape = state.stations[s].shape
            var stayOn: [Passenger] = []
            var changing = 0
            for p in state.trains[index].passengers {
                if p.destination == shape {
                    ScoringManager.deliver(p, at: stationID, in: &state, events: &events)
                    moved += 1
                } else if network.shouldStayOn(at: stationID, line: lineID, direction: direction, to: p.destination) {
                    stayOn.append(p)
                } else {
                    var p = p                                 // change trains (or wait for a route) here
                    p.transfers += 1
                    p.queuedSince = state.elapsed
                    state.stations[s].waiting.append(p)
                    moved += 1
                    changing += 1
                }
            }
            state.trains[index].passengers = stayOn
            let train = state.trains[index].id
            if changing > 0 { events.append(.passengersAlighted(train, stationID, count: changing)) }
            let boarded = board(index, at: s, line: lineID, direction: direction, in: &state, network: network)
            if boarded > 0 { events.append(.passengersBoarded(train, stationID, count: boarded)) }
            moved += boarded
        }
        state.trains[index].phase = .dwelling(remaining: dwellTime(moved: moved, at: stationID, in: state))
        return false
    }

    /// Leaves stop `i` straight away towards the next station, keeping its speed.
    private static func continueThrough(_ index: Int, from i: Int, line: MetroLine, in state: inout GameState) {
        guard let j = NetworkGraph.nextIndex(i, direction: state.trains[index].direction, count: line.stations.count,
                                             loop: line.isLoop) else {
            state.trains[index].phase = .dwelling(remaining: 0)
            return
        }
        if let until = BridgeManager.holdUntil(from: line.stations[i], to: line.stations[j], in: state) {
            state.trains[index].phase = .dwelling(remaining: max(state.config.simulationStep, until - state.elapsed))
            return
        }
        let speed = state.trains[index].speed
        startTrip(index, from: line.stations[i], to: line.stations[j], in: &state)
        state.trains[index].speed = speed
    }

    /// Dwell finished: pick the next stop and go.
    /// - Returns: true when the train should be removed (it was retiring).
    private static func depart(_ index: Int, in state: inout GameState, network: NetworkGraph,
                               events: inout [GameEvent]) -> Bool {
        let stationID = state.trains[index].to
        guard let lineID = state.trains[index].lineID, let line = state.line(lineID) else {
            unloadAll(index, at: stationID, in: &state, events: &events)
            return true
        }
        guard let i = line.stations.firstIndex(of: stationID) else {
            // Not on our line (any more): drive empty to the nearest station that is, and resume there.
            unloadAll(index, at: stationID, in: &state, events: &events)
            let here = state.station(stationID)?.position ?? .zero
            let target = line.stations.min { a, b in
                (state.station(a)?.position.distanceSquared(to: here) ?? .infinity)
                    < (state.station(b)?.position.distanceSquared(to: here) ?? .infinity)
            }
            if let target { startTrip(index, from: stationID, to: target, in: &state) }
            return false
        }
        if let until = state.trains[index].maintenanceUntil {
            if state.elapsed < until {
                state.trains[index].phase = .dwelling(remaining: until - state.elapsed)
                return false
            }
            state.trains[index].maintenanceUntil = nil
            state.revision += 1                       // back in service: headways change
        }
        let direction = departingDirection(at: i, current: state.trains[index].direction, line: line)
        state.trains[index].direction = direction
        // Last call for anyone who arrived on the platform during the stop.
        if let s = state.stationIndex(stationID), StopRules.stops(at: stationID, line: line, in: state) {
            let boarded = board(index, at: s, line: lineID, direction: direction, in: &state, network: network)
            if boarded > 0 { events.append(.passengersBoarded(state.trains[index].id, stationID, count: boarded)) }
        }
        guard let j = NetworkGraph.nextIndex(i, direction: direction, count: line.stations.count, loop: line.isLoop) else {
            state.trains[index].phase = .dwelling(remaining: state.config.dwellBase)
            return false
        }
        // A drawbridge is up ahead: wait here (passengers can still board) until it comes down.
        if let until = BridgeManager.holdUntil(from: stationID, to: line.stations[j], in: state) {
            state.trains[index].phase = .dwelling(remaining: max(state.config.simulationStep, until - state.elapsed))
            return false
        }
        startTrip(index, from: stationID, to: line.stations[j], in: &state)
        return false
    }

    private static func startTrip(_ index: Int, from: StationID, to: StationID, in state: inout GameState) {
        state.trains[index].from = from
        state.trains[index].to = to
        state.trains[index].progress = 0
        state.trains[index].speed = 0
        state.trains[index].phase = .moving
    }

    /// Direction the train leaves stop `i` in: turns round at the ends of an open line.
    static func departingDirection(at i: Int, current: Int, line: MetroLine) -> Int {
        let d = current >= 0 ? 1 : -1
        let n = line.stations.count
        return NetworkGraph.nextIndex(i, direction: d, count: n, loop: line.isLoop) == nil ? -d : d
    }

    /// Waiting passengers whose best route is this train get on, oldest first, while there is room.
    @discardableResult
    private static func board(_ index: Int, at s: Int, line: LineID, direction: Int, in state: inout GameState,
                              network: NetworkGraph) -> Int {
        guard state.trains[index].freeSeats > 0, !state.stations[s].waiting.isEmpty else { return 0 }
        let stationID = state.stations[s].id
        var remaining: [Passenger] = []
        var boarded = 0
        for p in state.stations[s].waiting {
            if state.trains[index].freeSeats > 0,
               network.shouldBoard(at: stationID, line: line, direction: direction, to: p.destination) {
                var p = p
                p.waited += max(0, state.elapsed - p.queuedSince)
                state.trains[index].passengers.append(p)
                boarded += 1
            } else {
                remaining.append(p)
            }
        }
        state.stations[s].waiting = remaining
        return boarded
    }

    /// Everyone gets off at `station`: delivered if it's their shape, otherwise they wait there.
    @discardableResult
    private static func unloadAll(_ index: Int, at station: StationID, in state: inout GameState,
                                  events: inout [GameEvent]) -> Int {
        let passengers = state.trains[index].passengers
        guard !passengers.isEmpty, let s = state.stationIndex(station) else { return 0 }
        state.trains[index].passengers = []
        var waiting = 0
        for p in passengers {
            if p.destination == state.stations[s].shape {
                ScoringManager.deliver(p, at: station, in: &state, events: &events)
            } else {
                var p = p
                p.transfers += 1
                p.queuedSince = state.elapsed
                state.stations[s].waiting.append(p)
                waiting += 1
            }
        }
        if waiting > 0 { events.append(.passengersAlighted(state.trains[index].id, station, count: waiting)) }
        return passengers.count
    }

    /// Time stopped: a base plus time per passenger getting on or off (quicker at an interchange).
    private static func dwellTime(moved: Int, at station: StationID, in state: GameState) -> Double {
        let c = state.config
        let perPassenger = c.dwellPerPassenger
            * (state.station(station)?.special == .interchange ? c.interchangeDwellFactor : 1)
        return c.dwellBase + Double(moved) * perPassenger
    }
}
