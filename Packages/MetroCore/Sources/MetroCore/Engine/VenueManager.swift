import Foundation

/// Stadium and airport (campaign part 2): where they open, the match schedule, crowds at full time, and
/// travellers who give up. Does nothing unless the rules have venues, so nothing else changes. Draws no
/// random numbers of its own: match days are fixed, so the player can plan for them.
public enum VenueManager {

    // MARK: Opening

    /// The venue the next station should be, if the city has just reached its size.
    static func venueDue(in state: GameState) -> SpecialStation? {
        guard let rules = state.config.venues, let venues = state.venues else { return nil }
        let count = state.stations.count
        if venues.stadium == nil, let n = rules.stadiumAfterStations, count >= n { return .stadium }
        if venues.airport == nil, let n = rules.airportAfterStations, count >= n { return .airport }
        return nil
    }

    /// Turns a newly placed station into the venue.
    static func open(_ venue: SpecialStation, at station: inout Station, in state: inout GameState) {
        station.special = venue
        switch venue {
        case .stadium: state.venues?.stadium = station.id
        case .airport: state.venues?.airport = station.id
        default: break
        }
    }

    // MARK: Every step

    static func update(_ state: inout GameState, events: inout [GameEvent]) {
        guard state.venues != nil, let rules = state.config.venues else { return }
        planMatches(rules: rules, in: &state)
        releaseFans(rules: rules, in: &state, events: &events)
        travellersGiveUp(rules: rules, in: &state, events: &events)
    }

    /// The week's matches, once the stadium exists: fixed days, full time at a fixed hour.
    /// A stadium that opens mid-week gets the matches still ahead (at least the warning time away).
    static func planMatches(rules: VenueRules, in state: inout GameState) {
        guard let stadium = state.venues?.stadium, state.venues!.plannedWeek < state.week else { return }
        state.venues!.plannedWeek = state.week
        let c = state.config
        let weekStart = Double(state.week - 1) * c.weekLength
        let day = c.weekLength / 7
        for d in rules.matchDays.sorted() where (0..<7).contains(d) {
            let fullTime = weekStart + (Double(d) + rules.fullTime) * day
            guard fullTime >= state.elapsed + rules.matchWarning else { continue }
            state.venues!.matches.append(Match(stadium: stadium, fullTime: fullTime, crowd: rules.matchCrowd))
        }
    }

    /// From full time, fans leave at a steady pace until the whole crowd is out. Like any arrival, they only
    /// come while the station is below the safety cap; the rest go home some other way.
    static func releaseFans(rules: VenueRules, in state: inout GameState, events: inout [GameEvent]) {
        guard var venues = state.venues else { return }
        for m in venues.matches.indices where state.elapsed >= venues.matches[m].fullTime {
            let match = venues.matches[m]
            guard let i = state.stationIndex(match.stadium) else { venues.matches[m].released = match.crowd; continue }
            if match.released == 0 { events.append(.fullTime(match.stadium)) }
            let progress = (state.elapsed - match.fullTime) / max(rules.crowdRelease, state.config.simulationStep)
            let due = min(match.crowd, Int(progress * Double(match.crowd)) + 1)
            while venues.matches[m].released < due {
                venues.matches[m].released += 1
                guard state.stations[i].waiting.count < state.config.maxWaitingPerStation,
                      !state.isClosed(match.stadium) else { continue }
                state.venues = venues
                PassengerManager.spawnPassenger(at: i, in: &state, events: &events, kind: .fan)
                venues = state.venues!
            }
        }
        venues.matches.removeAll(where: \.isFinished)
        state.venues = venues
    }

    /// Travellers who have waited too long on a platform leave the network.
    static func travellersGiveUp(rules: VenueRules, in state: inout GameState, events: inout [GameEvent]) {
        guard state.venues?.airport != nil else { return }
        let now = state.elapsed
        for i in state.stations.indices {
            let before = state.stations[i].waiting.count
            state.stations[i].waiting.removeAll { $0.kind == .traveller && now - $0.queuedSince > rules.travellerPatience }
            let left = before - state.stations[i].waiting.count
            guard left > 0 else { continue }
            state.venues!.travellersGaveUp += left
            events.append(.travellersGaveUp(state.stations[i].id, count: left))
        }
    }

    // MARK: Deliveries

    /// Counts fans and travellers; returns bonus points (travellers on time).
    static func recordDelivery(_ passenger: Passenger, journey: Double, in state: inout GameState) -> Int {
        guard let kind = passenger.kind, state.venues != nil, let rules = state.config.venues else { return 0 }
        switch kind {
        case .fan:
            state.venues!.fansDelivered += 1
            return 0
        case .traveller:
            guard journey <= rules.travellerOnTime else { return 0 }
            state.venues!.travellersOnTime += 1
            return rules.travellerBonus
        }
    }

    // MARK: For the interface

    /// The next match still to come (or emptying), if any.
    public static func nextMatch(in state: GameState) -> Match? {
        state.venues?.matches.min { $0.fullTime < $1.fullTime }
    }
}
