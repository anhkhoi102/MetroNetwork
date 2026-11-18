import Foundation

/// Decides when and where new stations appear. Uses only the RNG stored in `GameState.spawn`.
public enum StationManager {

    /// Places the opening stations around the city centre.
    public static func spawnInitialStations(in state: inout GameState, events: inout [GameEvent]) {
        for _ in 0..<state.config.initialStationCount {
            if let id = spawnStation(in: &state) { events.append(.stationSpawned(id)) }
        }
        scheduleNextSpawn(in: &state)
    }

    /// Called every simulation step.
    public static func update(_ state: inout GameState, events: inout [GameEvent]) {
        guard state.elapsed >= state.spawn.nextSpawnTime else { return }
        if state.stations.count < state.config.maxStations, let id = spawnStation(in: &state) {
            events.append(.stationSpawned(id))
        }
        scheduleNextSpawn(in: &state)
    }

    /// Called every simulation step: overcrowding timers fill while a station holds more passengers than
    /// its capacity and drain once it's back under. A full timer ends the session.
    static func updateCongestion(_ state: inout GameState, dt: Double, events: inout [GameEvent]) {
        let c = state.config
        for i in state.stations.indices where !state.isClosed(state.stations[i].id) {   // frozen while closed
            let before = state.stations[i].overcrowding
            if state.stations[i].isOvercrowded(c) {
                state.stations[i].overcrowding = min(1, before + dt / max(c.overcrowdTime, 1e-9))
                if before == 0 { events.append(.stationOvercrowding(state.stations[i].id)) }
            } else if before > 0 {
                state.stations[i].overcrowding = max(0, before - dt / max(c.overcrowdRecoveryTime, 1e-9))
            }
        }
        // Ties (two stations failing in the same step) go to the most crowded, then the oldest.
        let failed = state.stations.filter { $0.overcrowding >= 1 }
            .max { a, b in a.waiting.count < b.waiting.count || (a.waiting.count == b.waiting.count && a.id > b.id) }
        if let failed, !state.isOver {
            let info = GameOverInfo(station: failed.id, time: state.elapsed)
            state.status = .over(info)
            events.append(.gameOver(info))
        }
    }

    static func scheduleNextSpawn(in state: inout GameState) {
        let c = state.config
        let jitter = 1 + c.stationSpawnJitter * (2 * state.spawn.rng.unit() - 1)
        state.spawn.nextSpawnTime = state.elapsed + c.stationSpawnInterval * jitter
    }

    /// Adds one station, or returns nil when no valid spot exists inside the current city radius.
    @discardableResult
    public static func spawnStation(in state: inout GameState) -> StationID? {
        let shape = chooseShape(in: &state)
        let venue = VenueManager.venueDue(in: state)
        guard let position = venue.map({ choosePosition(for: $0, in: &state) }) ?? choosePosition(in: &state) else { return nil }
        let id = StationID(state.nextStationID)
        state.nextStationID += 1
        var station = Station(id: id, shape: shape, position: position, spawnTime: state.elapsed)
        DemandManager.characterize(&station, in: &state)
        if let venue { VenueManager.open(venue, at: &station, in: &state) }
        state.stations.append(station)
        PassengerManager.scheduleFirstPassenger(at: state.stations.count - 1, in: &state)
        state.revision += 1
        return id
    }

    // MARK: Shape

    static func chooseShape(in state: inout GameState) -> StationShape {
        let c = state.config
        let count = state.stations.count
        if count < c.initialStationCount, !c.initialShapes.isEmpty {
            return c.initialShapes[count % c.initialShapes.count]
        }
        if count >= c.rareShapesAfterStations, state.spawn.rng.chance(c.rareShapeChance) {
            let allowed = c.rareShapes.filter { shape in
                state.stations.lazy.filter { $0.shape == shape }.count < c.maxStationsPerRareShape
            }
            if !allowed.isEmpty {
                return allowed[state.spawn.rng.int(in: 0...(allowed.count - 1))]
            }
        }
        if let i = state.spawn.rng.weightedIndex(c.commonShapeWeights), i < c.commonShapes.count {
            return c.commonShapes[i]
        }
        return c.commonShapes.first ?? .circle
    }

    // MARK: Position

    static func choosePosition(in state: inout GameState) -> Vec2? {
        let spacing = state.config.stationMinSpacing
        // Relax spacing a little before giving up, so a crowded city still grows.
        for factor in [1.0, 0.85] {
            for _ in 0..<80 {
                let candidate = sampleCandidate(in: &state)
                if isValid(candidate, spacing: spacing * factor, in: state) { return candidate }
            }
        }
        return nil
    }

    /// A spot that suits a venue: the airport as far from the centre as the city allows (a little beyond its
    /// current edge), the stadium out of the centre but not on the edge. Falls back to any valid spot.
    static func choosePosition(for venue: SpecialStation, in state: inout GameState) -> Vec2? {
        let spacing = state.config.stationMinSpacing
        let centre = state.map.cityCenter
        let radius = state.cityRadius
        let reach = venue == .airport ? radius * 1.25 : radius
        let ideal = venue == .airport ? reach : radius * 0.6
        var best: (Vec2, Double)?
        for _ in 0..<60 {
            let p = pointInDisc(center: centre, radius: reach, rng: &state.spawn.rng)
            guard state.map.isBuildable(p, clearance: state.config.stationWaterClearance),
                  state.map.bounds.contains(p),
                  state.stations.allSatisfy({ $0.position.distanceSquared(to: p) >= spacing * spacing }) else { continue }
            let miss = abs(p.distance(to: centre) - ideal)
            if best == nil || miss < best!.1 { best = (p, miss) }
        }
        return best?.0 ?? choosePosition(in: &state)
    }

    private static func sampleCandidate(in state: inout GameState) -> Vec2 {
        let map = state.map
        let radius = state.cityRadius
        // Mostly sample around districts the city has already grown into, which clusters stations into
        // neighbourhoods; the rest uniformly over the city disc.
        let reachable = map.districts.filter { $0.center.distance(to: map.cityCenter) < radius + $0.radius * 0.5 }
        if !reachable.isEmpty, state.spawn.rng.chance(0.65),
           let i = state.spawn.rng.weightedIndex(reachable.map(\.weight)) {
            let d = reachable[i]
            return pointInDisc(center: d.center, radius: d.radius, rng: &state.spawn.rng)
        }
        return pointInDisc(center: map.cityCenter, radius: radius, rng: &state.spawn.rng)
    }

    static func isValid(_ p: Vec2, spacing: Double, in state: GameState) -> Bool {
        guard p.distance(to: state.map.cityCenter) <= state.cityRadius else { return false }
        guard state.map.isBuildable(p, clearance: state.config.stationWaterClearance) else { return false }
        let spacingSq = spacing * spacing
        return state.stations.allSatisfy { $0.position.distanceSquared(to: p) >= spacingSq }
    }

    private static func pointInDisc(center: Vec2, radius: Double, rng: inout SeededRandom) -> Vec2 {
        let r = radius * rng.unit().squareRoot()
        let a = rng.double(in: 0...(2 * .pi))
        return center + Vec2(cos(a), sin(a)) * r
    }
}
