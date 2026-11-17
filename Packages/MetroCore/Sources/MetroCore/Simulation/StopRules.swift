import Foundation

/// Where trains stop. Shared by the trains (`TrainManager`) and route planning (`NetworkGraph`), so a
/// passenger never plans to get on or off where the train won't stop.
///
/// - A closed station is never a stop: trains run through it.
/// - An express line stops only at its ends, at interchanges (stations on two or more lines) and at
///   special stations — as long as that leaves at least two stops; otherwise it stops everywhere.
public enum StopRules {

    /// Does a train of `line` stop at `station` now?
    public static func stops(at station: StationID, line: MetroLine, in state: GameState) -> Bool {
        if state.isClosed(station) { return false }
        guard line.isExpress, expressServiceApplies(line, in: state) else { return true }
        return isExpressStop(station, line: line, in: state)
    }

    /// Stations of `line` where its trains stop now, in line order.
    public static func stopMask(for line: MetroLine, in state: GameState) -> [Bool] {
        let express = line.isExpress && expressServiceApplies(line, in: state)
        return line.stations.map { s in
            !state.isClosed(s) && (!express || isExpressStop(s, line: line, in: state))
        }
    }

    /// Stations an express service on `line` would stop at.
    public static func expressStops(of line: MetroLine, in state: GameState) -> [StationID] {
        line.stations.filter { isExpressStop($0, line: line, in: state) }
    }

    static func expressServiceApplies(_ line: MetroLine, in state: GameState) -> Bool {
        line.stations.lazy.filter { isExpressStop($0, line: line, in: state) }.prefix(2).count >= 2
    }

    static func isExpressStop(_ station: StationID, line: MetroLine, in state: GameState) -> Bool {
        if !line.isLoop, station == line.stations.first || station == line.stations.last { return true }
        if state.station(station)?.special != nil { return true }
        var serving = 0
        for other in state.lines where other.contains(station) {
            serving += 1
            if serving >= 2 { return true }
        }
        return false
    }
}
