import Foundation

/// Score and session statistics. Every delivery goes through `deliver`, so the passenger count, the score
/// and the weekly tally can never disagree.
public enum ScoringManager {

    /// Points for delivering a passenger whose journey took `journey` seconds (spawn to arrival).
    public static func points(forJourney journey: Double, config: GameConfiguration) -> Int {
        let span = config.slowTripTime - config.quickTripTime
        let speed = span > 0 ? (config.slowTripTime - journey) / span : (journey <= config.quickTripTime ? 1 : 0)
        let bonus = (Double(config.quickTripBonus) * min(1, max(0, speed))).rounded()
        return config.pointsPerPassenger + Int(bonus)
    }

    /// A passenger reached a station of their destination shape.
    static func deliver(_ passenger: Passenger, at station: StationID, in state: inout GameState,
                        events: inout [GameEvent]) {
        let journey = max(0, state.elapsed - passenger.spawnTime)
        state.passengersDelivered += 1
        let earned = points(forJourney: journey, config: state.config)
            + VenueManager.recordDelivery(passenger, journey: journey, in: &state)
        state.stats.score += earned
        events.append(.pointsScored(station, earned))
        state.stats.deliveredThisWeek += 1
        state.stats.journeyTimeTotal += journey
        EfficiencyManager.recordDelivery(passenger, journey: journey, in: &state)
        ScenarioManager.recordDelivery(in: &state)
        events.append(.passengerDelivered(station))
    }

    public static func summary(of state: GameState) -> SessionSummary {
        let delivered = state.passengersDelivered
        return SessionSummary(score: state.stats.score, delivered: delivered, elapsed: state.elapsed,
                              week: state.week, stations: state.stations.count,
                              averageJourney: delivered > 0 ? state.stats.journeyTimeTotal / Double(delivered) : nil,
                              bestWeek: max(state.stats.bestWeek, state.stats.deliveredThisWeek),
                              efficiency: state.efficiency.sessionAverage)
    }
}
