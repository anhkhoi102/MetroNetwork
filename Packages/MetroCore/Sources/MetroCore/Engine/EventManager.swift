import Foundation

/// Network events (Phase 4): occasional, announced disruptions the player can react to. Only one at a time,
/// each announced `eventWarning` seconds ahead, never before `eventsFromWeek`. Uses `GameState.eventRNG`.
public enum EventManager {

    static func update(_ state: inout GameState, events: inout [GameEvent]) {
        let c = state.config
        // Start and finish what is scheduled.
        var i = 0
        while i < state.events.count {
            let event = state.events[i]
            if state.elapsed >= event.end {
                finish(event, in: &state)
                state.events.remove(at: i)
                events.append(.networkEventEnded(event))
                continue
            }
            i += 1
        }
        for index in state.events.indices where state.events[index].start <= state.elapsed && !state.events[index].started {
            state.events[index].started = true
            begin(state.events[index], in: &state, events: &events)
            events.append(.networkEventStarted(state.events[index]))
        }

        // Announce the next one.
        guard state.week >= c.eventsFromWeek, state.events.isEmpty, state.elapsed >= state.nextEventTime else { return }
        if let kind = chooseKind(in: &state) {
            let start = state.elapsed + c.eventWarning
            let duration: Double = switch kind {
            case .surge: c.surgeDuration
            case .touristGroup: 1
            case .maintenance: c.maintenanceDuration
            case .closure: c.closureDuration
            }
            let event = NetworkEvent(id: state.nextEventID, kind: kind, announced: state.elapsed,
                                     start: start, end: start + duration)
            state.nextEventID += 1
            state.events.append(event)
            events.append(.networkEventAnnounced(event))
            state.nextEventTime = event.end + state.eventRNG.double(in: c.eventGapMin...max(c.eventGapMin, c.eventGapMax))
        } else {
            state.nextEventTime = state.elapsed + c.eventGapMin * 0.5
        }
    }

    private static func begin(_ event: NetworkEvent, in state: inout GameState, events: inout [GameEvent]) {
        switch event.kind {
        case .surge:
            break                                              // read by DemandManager while active
        case let .touristGroup(station, shape, count):
            guard let i = state.stationIndex(station) else { return }
            // New passengers respect the station's safety cap, like ordinary generation.
            let room = max(0, state.config.maxWaitingPerStation - state.stations[i].waiting.count)
            for _ in 0..<min(count, room) {
                PassengerManager.spawnPassenger(at: i, in: &state, events: &events, destination: shape)
            }
        case .maintenance(let train):
            if let i = state.trains.firstIndex(where: { $0.id == train }), !state.trains[i].isRetiring {
                state.trains[i].maintenanceUntil = event.end
                state.revision += 1                            // the line's headway changes
            }
        case .closure:
            state.revision += 1                                // trains stop running through it
        }
    }

    private static func finish(_ event: NetworkEvent, in state: inout GameState) {
        switch event.kind {
        case .closure: state.revision += 1
        default: break                                         // maintenance ends when the train next departs
        }
    }

    // MARK: Choosing what happens

    private static func chooseKind(in state: inout GameState) -> NetworkEvent.Kind? {
        let served = state.stations.filter { s in state.lines.contains { $0.contains(s.id) } }
        guard !served.isEmpty else { return nil }
        // Weights: surge 3, tourist group 2, maintenance 2, closure 2 — falling back to a surge when the
        // network has nothing suitable for the others.
        let pick = state.eventRNG.weightedIndex([3, 2, 2, 2]) ?? 0
        switch pick {
        case 1:
            if let kind = touristGroup(served, in: &state) { return kind }
        case 2:
            if let kind = maintenance(in: &state) { return kind }
        case 3:
            if let kind = closure(served, in: &state) { return kind }
        default:
            break
        }
        return surge(served, in: &state)
    }

    private static func surge(_ served: [Station], in state: inout GameState) -> NetworkEvent.Kind? {
        guard let i = state.eventRNG.weightedIndex(served.map(\.demand)) else { return nil }
        return .surge(served[i].id)
    }

    /// A group heading for the rarest shape (other than their station's).
    private static func touristGroup(_ served: [Station], in state: inout GameState) -> NetworkEvent.Kind? {
        let counts = Dictionary(grouping: state.stations, by: \.shape).mapValues(\.count)
        let station = served[state.eventRNG.int(in: 0...(served.count - 1))]
        let shapes = StationShape.allCases.filter { $0 != station.shape && counts[$0] != nil }
        guard let rarest = shapes.min(by: { counts[$0]! < counts[$1]! }) else { return nil }
        return .touristGroup(station.id, rarest, count: state.config.touristGroupSize)
    }

    /// A train from a line that has at least two, so no line is left without service.
    private static func maintenance(in state: inout GameState) -> NetworkEvent.Kind? {
        let candidates = state.trains.filter { t in
            guard let line = t.lineID, t.maintenanceUntil == nil else { return false }
            return state.trains(on: line).count >= 2
        }
        guard !candidates.isEmpty else { return nil }
        return .maintenance(candidates[state.eventRNG.int(in: 0...(candidates.count - 1))].id)
    }

    /// An ordinary station whose shape exists elsewhere, so every destination stays reachable.
    private static func closure(_ served: [Station], in state: inout GameState) -> NetworkEvent.Kind? {
        let counts = Dictionary(grouping: state.stations, by: \.shape).mapValues(\.count)
        let candidates = served.filter { $0.special == nil && (counts[$0.shape] ?? 0) >= 2 }
        guard !candidates.isEmpty else { return nil }
        return .closure(candidates[state.eventRNG.int(in: 0...(candidates.count - 1))].id)
    }
}
