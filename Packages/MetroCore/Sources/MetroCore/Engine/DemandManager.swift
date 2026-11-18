import Foundation

/// Where passengers come from and where they want to go (Phase 4):
/// - every station has a **demand** (busy districts generate more passengers, quiet outskirts fewer) and an
///   **attraction** (trips favour shapes found in the city centre);
/// - **rush hours** (two a week, announced at the start of the week) multiply demand — homes in the
///   outskirts in the morning, the centre in the evening;
/// - **special stations** are assigned as the city grows.
public enum DemandManager {

    // MARK: Station character

    /// Fills in demand, attraction, centrality and (sometimes) a special role for a newly placed station.
    /// Uses the station-spawning RNG, so it is part of the deterministic city layout.
    static func characterize(_ station: inout Station, in state: inout GameState) {
        let c = state.config
        let map = state.map
        let distance = station.position.distance(to: map.cityCenter)
        let centrality = max(0, min(1, 1 - distance / max(c.outskirtsDistance, 1)))
        // Density of the surrounding districts (0 … 1).
        let maxWeight = map.districts.map(\.weight).max() ?? 1
        let density = map.districts.reduce(0.0) { best, d in
            let falloff = max(0, 1 - station.position.distance(to: d.center) / max(d.radius * 1.4, 1))
            return max(best, falloff * d.weight / max(maxWeight, 1e-9))
        }
        station.centrality = centrality
        station.demand = c.minStationDemand + (c.maxStationDemand - c.minStationDemand) * density
        station.attraction = 1 + (c.centralAttraction - 1) * centrality

        guard state.stations.count >= c.specialStationsAfter, state.spawn.rng.chance(c.specialStationChance) else { return }
        let allowed = SpecialStation.allCases.filter { kind in
            !kind.isVenue && state.stations.lazy.filter { $0.special == kind }.count < c.maxStationsPerSpecial
        }
        guard !allowed.isEmpty else { return }
        station.special = allowed[state.spawn.rng.int(in: 0...(allowed.count - 1))]
    }

    // MARK: Passenger generation

    /// How many times faster than normal station `index` generates passengers right now (0 = not at all).
    public static func spawnMultiplier(forStationAt index: Int, in state: GameState) -> Double {
        let station = state.stations[index]
        if state.isClosed(station.id) { return 0 }
        var m = station.demand
        if station.special == .hub { m *= state.config.hubDemandMultiplier }
        if let v = state.config.venues {
            if station.special == .stadium { m *= v.stadiumDemandFactor }
            if station.special == .airport { m *= v.airportDemandFactor }
        }
        if let rush = state.activeRushHour { m *= rush.multiplier(centrality: station.centrality) }
        for event in state.activeEvents {
            if case .surge(let s) = event.kind, s == station.id { m *= state.config.surgeMultiplier }
        }
        return m
    }

    /// Destination shapes for a passenger at station `index`, with weights: the summed attraction of the
    /// other stations of each shape. In `StationShape.allCases` order, so the choice is deterministic.
    static func destinationWeights(forStationAt index: Int, in state: GameState) -> [(StationShape, Double)] {
        let own = state.stations[index].shape
        var weights: [StationShape: Double] = [:]
        for (i, s) in state.stations.enumerated() where i != index && s.shape != own {
            weights[s.shape, default: 0] += s.attraction
        }
        return StationShape.allCases.compactMap { shape in weights[shape].map { (shape, $0) } }
    }

    // MARK: Rush hours

    /// Plans this week's rush hours (called when a week starts). Days are drawn from Monday–Friday.
    static func planRushHours(forWeek week: Int, in state: inout GameState) {
        let c = state.config
        state.rushHours.removeAll { $0.end <= state.elapsed }
        guard week >= c.rushHoursFromWeek, c.rushHoursPerWeek > 0 else { return }
        let weekStart = Double(week - 1) * c.weekLength
        let day = c.weekLength / 7
        var days = Array(0..<5)
        var picked: [Int] = []
        for _ in 0..<min(c.rushHoursPerWeek, days.count) {
            picked.append(days.remove(at: state.eventRNG.int(in: 0...(days.count - 1))))
        }
        picked.sort()
        let intensity = min(c.maxRushIntensity,
                            c.rushIntensity + c.rushIntensityPerWeek * Double(week - c.rushHoursFromWeek))
        for (n, d) in picked.enumerated() {
            let flow: RushHour.Flow = n % 2 == 0 ? .toCentre : .fromCentre
            let start = weekStart + (Double(d) + (flow == .toCentre ? 0.1 : 0.45)) * day
            state.rushHours.append(RushHour(flow: flow, start: start, end: start + c.rushHourDays * day,
                                            intensity: intensity))
        }
    }
}
