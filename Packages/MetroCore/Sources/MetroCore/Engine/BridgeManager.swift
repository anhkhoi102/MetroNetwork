import Foundation

/// Drawbridges (campaign part 2). The timetable is fixed (no random numbers), so the player can plan around
/// it; the only thing stored is whether the bridges were up, to announce each lift once. A segment is a bridge when it has to cross water.
public enum BridgeManager {

    /// The lift running at `time`, or the next one; nil without drawbridges.
    public static func lift(around time: Double, in state: GameState) -> BridgeLift? {
        lift(around: time, config: state.config)
    }

    static func lift(around time: Double, config: GameConfiguration) -> BridgeLift? {
        guard let r = config.drawbridges, r.interval > 0 else { return nil }
        let first = Double(max(0, r.fromWeek - 1)) * config.weekLength + r.firstLift
        guard time >= first else { return BridgeLift(start: first, end: first + r.duration) }
        let n = ((time - first) / r.interval).rounded(.down)
        let current = BridgeLift(start: first + n * r.interval, end: first + n * r.interval + r.duration)
        return current.isActive(at: time) ? current
            : BridgeLift(start: current.start + r.interval, end: current.end + r.interval)
    }

    /// True while the bridges are up.
    public static func isRaised(in state: GameState) -> Bool {
        lift(around: state.elapsed, in: state)?.isActive(at: state.elapsed) ?? false
    }

    /// When a train about to run from `a` to `b` may go, if a lifted bridge is in the way.
    static func holdUntil(from a: StationID, to b: StationID, in state: GameState) -> Double? {
        guard let lift = lift(around: state.elapsed, in: state), lift.isActive(at: state.elapsed),
              let pa = state.station(a)?.position, let pb = state.station(b)?.position else { return nil }
        let terrain = RouteGeometry.terrain(SegmentKey(a, b), positions: [a: pa, b: pb], map: state.map)
        return terrain == .water ? lift.end : nil
    }

    /// Announces lifts as they begin and end (for sound and the interface).
    static func update(_ state: inout GameState, events: inout [GameEvent]) {
        guard state.config.drawbridges != nil else { return }
        let now = isRaised(in: state)
        let was = state.bridgesUp ?? false
        state.bridgesUp = now
        if now && !was { events.append(.bridgesRaised) }
        if !now && was { events.append(.bridgesLowered) }
    }
}
