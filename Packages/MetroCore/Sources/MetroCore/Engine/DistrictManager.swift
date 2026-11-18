import Foundation

/// New districts (campaign part 2): once a week, from `DistrictRules.fromWeek`, a neighbourhood the city
/// hasn't reached yet is announced and, `warning` seconds later, opens with several stations at once.
/// The place is chosen without random numbers (only where the stations go inside it uses the spawn RNG),
/// so the level is the same on every attempt.
public enum DistrictManager {

    static func update(_ state: inout GameState, events: inout [GameEvent]) {
        guard let rules = state.config.newDistricts, state.newDistricts != nil else { return }
        if let upcoming = state.newDistricts?.upcoming, state.elapsed >= upcoming.opensAt {
            open(upcoming, rules: rules, in: &state, events: &events)
        }
        // The next week due a district (the warning may start before that week does).
        let week = max(rules.fromWeek, state.newDistricts!.announcedWeek + 1)
        let c = state.config
        let opensAt = Double(week - 1) * c.weekLength + rules.opensOnDay * c.weekLength / 7
        guard state.elapsed >= opensAt - rules.warning else { return }
        state.newDistricts!.announcedWeek = week
        guard let center = chooseArea(rules: rules, in: state) else { return }
        let district = NewDistrict(center: center, radius: rules.radius, opensAt: max(opensAt, state.elapsed + 1))
        state.newDistricts!.upcoming = district
        events.append(.districtAnnounced(district))
    }

    /// A neighbourhood of the map with no stations yet, preferably just beyond the network (a short line
    /// away, not across the map). Falls back to nothing when every neighbourhood is built up.
    static func chooseArea(rules: DistrictRules, in state: GameState) -> Vec2? {
        let map = state.map
        let wanted = rules.radius * 2.2
        let candidates = map.districts.filter { d in
            d.center.distance(to: map.cityCenter) > 1
                && map.isBuildable(d.center, clearance: state.config.stationWaterClearance)
                && state.stations.allSatisfy { $0.position.distance(to: d.center) > rules.radius + 60 }
        }
        func gap(_ p: Vec2) -> Double {
            state.stations.map { $0.position.distance(to: p) }.min() ?? 0
        }
        if let best = candidates.min(by: { abs(gap($0.center) - wanted) < abs(gap($1.center) - wanted) }) {
            return best.center
        }
        // Every mapped neighbourhood is built up: open one just beyond the city's edge instead. Tried in a
        // fixed order of directions, so it needs no random numbers either.
        let reach = state.cityRadius + rules.radius
        for k in 0..<24 {
            let angle = Double(k) * 2 * .pi / 24 + Double(state.newDistricts?.opened ?? 0)
            let p = map.cityCenter + Vec2(cos(angle), sin(angle)) * reach
            guard map.isBuildable(p, clearance: rules.radius * 0.5),
                  state.stations.allSatisfy({ $0.position.distance(to: p) > rules.radius + 60 }) else { continue }
            return p
        }
        return nil
    }

    private static func open(_ district: NewDistrict, rules: DistrictRules, in state: inout GameState,
                             events: inout [GameEvent]) {
        state.newDistricts!.upcoming = nil
        state.newDistricts!.opened += 1
        for _ in 0..<rules.stations where state.stations.count < state.config.maxStations {
            if let id = StationManager.spawnStation(in: &state, near: district.center, radius: district.radius) {
                events.append(.stationSpawned(id))
            }
        }
        events.append(.districtOpened(district))
    }
}
