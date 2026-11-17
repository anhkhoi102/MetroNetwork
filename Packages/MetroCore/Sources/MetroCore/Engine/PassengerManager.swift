import Foundation

/// Passenger generation. Each station produces passengers at its own pace; each passenger wants to reach
/// any station of a shape that exists elsewhere in the city (never its own shape).
/// Uses only `GameState.passengerRNG`, so it never disturbs station spawning. Passengers keep coming when a
/// station is over capacity: that is what overcrowds it (see `StationManager.updateCongestion`).
public enum PassengerManager {

    /// Schedules the first passenger of a newly spawned station.
    static func scheduleFirstPassenger(at index: Int, in state: inout GameState) {
        let c = state.config
        state.stations[index].nextPassengerTime = state.elapsed + c.firstPassengerDelay
            + state.passengerRNG.unit() * DifficultyManager.passengerInterval(in: state) * c.passengerSpawnJitter
    }

    /// Called every simulation step.
    static func update(_ state: inout GameState, events: inout [GameEvent]) {
        let c = state.config
        let interval = DifficultyManager.passengerInterval(in: state)
        for i in state.stations.indices where state.elapsed >= state.stations[i].nextPassengerTime {
            // Demand patterns, rush hours and surges speed a station up; a closed station generates nobody.
            let multiplier = DemandManager.spawnMultiplier(forStationAt: i, in: state)
            if multiplier > 0, state.stations[i].waiting.count < c.maxWaitingPerStation {
                spawnPassenger(at: i, in: &state, events: &events)
            }
            let jitter = 1 + c.passengerSpawnJitter * (2 * state.passengerRNG.unit() - 1)
            state.stations[i].nextPassengerTime = state.elapsed + interval * jitter / max(multiplier, 0.25)
        }
    }

    /// Shapes a passenger at station `index` may want: shapes present at other stations, minus its own.
    /// In `StationShape.allCases` order, so the choice is deterministic.
    static func destinations(forStationAt index: Int, in state: GameState) -> [StationShape] {
        let own = state.stations[index].shape
        let present = Set(state.stations.map(\.shape))
        return StationShape.allCases.filter { $0 != own && present.contains($0) }
    }

    /// Adds a passenger at station `index`. The destination shape is drawn by attraction (central shapes are
    /// more popular) unless `destination` is given.
    @discardableResult
    static func spawnPassenger(at index: Int, in state: inout GameState, events: inout [GameEvent],
                               destination: StationShape? = nil) -> Passenger? {
        let shape: StationShape
        if let destination {
            shape = destination
        } else {
            let options = DemandManager.destinationWeights(forStationAt: index, in: state)
            guard !options.isEmpty,
                  let pick = state.passengerRNG.weightedIndex(options.map(\.1)) else { return nil }
            shape = options[pick].0
        }
        let passenger = Passenger(id: state.nextPassengerID, destination: shape,
                                  origin: state.stations[index].id, spawnTime: state.elapsed)
        state.nextPassengerID += 1
        state.passengersSpawned += 1
        state.stations[index].waiting.append(passenger)
        events.append(.passengerSpawned(state.stations[index].id))
        return passenger
    }
}
