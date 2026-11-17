import Foundation

/// How the pressure grows over a session: weeks tick over, each new week grants credits and makes every
/// station generate passengers a little more often (down to a floor). The city itself also grows
/// (`StationManager`), adding destinations and longer journeys.
public enum DifficultyManager {

    /// Multiplier on `passengerSpawnInterval` for a given week (1 in week 1, shrinking each week).
    public static func passengerIntervalFactor(week: Int, config: GameConfiguration) -> Double {
        max(config.minPassengerIntervalFactor, pow(config.weeklyDemandGrowth, Double(max(0, week - 1))))
    }

    public static func passengerInterval(in state: GameState) -> Double {
        state.config.passengerSpawnInterval * passengerIntervalFactor(week: state.week, config: state.config)
    }

    /// Called every simulation step: starts a new week when its time comes.
    static func update(_ state: inout GameState, events: inout [GameEvent]) {
        guard state.config.weekLength > 0, state.elapsed >= Double(state.week) * state.config.weekLength else { return }
        let delivered = state.stats.deliveredThisWeek
        state.week += 1
        let grant = ResourceManager.weeklyGrant(startingWeek: state.week, deliveredLastWeek: delivered,
                                                config: state.config)
        state.resources.credits += grant.total
        state.stats.bestWeek = max(state.stats.bestWeek, delivered)
        state.stats.deliveredThisWeek = 0
        state.stats.lastGrant = grant
        DemandManager.planRushHours(forWeek: state.week, in: &state)
        events.append(.weekStarted(grant))
    }
}
