import Foundation

/// Network efficiency (Phase 4): one 0–100 number that tells the player how well the network is working,
/// built from four things they can act on — how long passengers wait, how long trips take, how full the
/// trains run, and how many stations are close to overcrowding.
public enum EfficiencyManager {

    /// Called for every delivered passenger.
    static func recordDelivery(_ passenger: Passenger, journey: Double, in state: inout GameState) {
        let a = state.config.efficiencySmoothing
        var e = state.efficiency
        if e.hasData {
            e.averageWait += a * (passenger.waited - e.averageWait)
            e.averageJourney += a * (journey - e.averageJourney)
            e.averageTransfers += a * (Double(passenger.transfers) - e.averageTransfers)
        } else {
            e.averageWait = passenger.waited
            e.averageJourney = journey
            e.averageTransfers = Double(passenger.transfers)
            e.hasData = true
        }
        state.efficiency = e
    }

    /// Called every simulation step; samples the network once a second.
    static func update(_ state: inout GameState) {
        guard state.elapsed >= state.efficiency.nextSample else { return }
        let c = state.config
        var e = state.efficiency
        e.nextSample = state.elapsed + 1

        let running = state.trains.filter { !$0.isRetiring && $0.maintenanceUntil == nil }
        let seats = running.reduce(0) { $0 + $1.capacity }
        let utilization = seats > 0 ? Double(running.reduce(0) { $0 + $1.passengers.count }) / Double(seats) : 0
        let crowded = state.stations.filter { Double($0.waiting.count) > 0.75 * Double($0.capacity(c)) }.count
        let congestion = state.stations.isEmpty ? 0 : Double(crowded) / Double(state.stations.count)
        let a = c.efficiencySmoothing
        e.utilization += a * (utilization - e.utilization)
        e.congestion += a * (congestion - e.congestion)

        if e.hasData {
            e.score = score(e, config: c)
            e.scoreTimeTotal += e.score
            e.scoredTime += 1
        }
        state.efficiency = e
    }

    public static func factors(_ e: NetworkEfficiency, config c: GameConfiguration) -> NetworkEfficiency.Factors {
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        return .init(
            waiting: clamp(1 - e.averageWait / max(c.efficiencyWorstWait, 1)),
            journey: clamp(1 - (e.averageJourney - c.efficiencyBestJourney)
                           / max(c.efficiencyWorstJourney - c.efficiencyBestJourney, 1)),
            load: clamp(e.utilization / max(c.efficiencyGoodLoad, 1e-9)),
            crowding: clamp(1 - e.congestion * 2))
    }

    public static func score(_ e: NetworkEfficiency, config c: GameConfiguration) -> Double {
        let f = factors(e, config: c)
        let total = c.efficiencyWaitWeight + c.efficiencyJourneyWeight + c.efficiencyLoadWeight + c.efficiencyCrowdingWeight
        let sum = f.waiting * c.efficiencyWaitWeight + f.journey * c.efficiencyJourneyWeight
            + f.load * c.efficiencyLoadWeight + f.crowding * c.efficiencyCrowdingWeight
        return 100 * sum / max(total, 1e-9)
    }
}
