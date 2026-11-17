import Foundation

/// All rules for building and editing lines. Pure functions over `GameState`: a command is either applied
/// completely or rejected with a `RouteError`, never half-applied.
public enum RouteManager {

    /// Applies any player command. Line edits must leave enough water crossings for every segment that
    /// crosses water; nothing is changed when a command fails.
    public static func apply(_ command: GameCommand, to state: inout GameState) throws(RouteError) -> CommandOutcome {
        guard !state.isOver else { throw .sessionOver }
        var copy = state
        let outcome = try applyUnchecked(command, to: &copy)
        if command.changesLines {
            let used = ResourceManager.crossingsUsed(in: copy)
            if used > copy.resources.crossings, used > ResourceManager.crossingsUsed(in: state) {
                throw .noCrossingsLeft
            }
            // Heritage stations: no edit may add a line beyond the limit.
            for station in copy.stations where station.special == .heritage {
                let after = copy.lines(serving: station.id).count
                if after > copy.config.heritageMaxLines, after > state.lines(serving: station.id).count {
                    throw .heritageLineLimit
                }
            }
        }
        ScenarioManager.recordLines(in: &copy)
        state = copy
        return outcome
    }

    private static func applyUnchecked(_ command: GameCommand, to state: inout GameState) throws(RouteError) -> CommandOutcome {
        switch command {
        case let .createLine(stations, colorIndex, isLoop):
            return .lineCreated(try createLine(stations: stations, colorIndex: colorIndex, isLoop: isLoop, in: &state))
        case let .extendLine(id, end, station):
            try extendLine(id, end: end, with: station, in: &state)
            return .lineChanged(id)
        case let .insertStation(id, station, segment):
            try insertStation(station, into: id, segment: segment, in: &state)
            return .lineChanged(id)
        case let .removeStation(id, station):
            return try removeStation(station, from: id, in: &state)
        case let .setStations(id, stations, isLoop):
            return try setStations(id, stations: stations, isLoop: isLoop, in: &state)
        case let .deleteLine(id):
            try deleteLine(id, in: &state)
            return .lineDeleted(id)
        case let .setLineColor(id, colorIndex):
            try setColor(id, colorIndex: colorIndex, in: &state)
            return .lineChanged(id)
        case let .openLoop(id):
            try openLoop(id, in: &state)
            return .lineChanged(id)
        case let .addTrain(id):
            return .trainAdded(try TrainManager.addTrain(to: id, in: &state))
        case let .removeTrain(id):
            return .trainWithdrawn(try TrainManager.removeTrain(from: id, in: &state))
        case let .withdrawTrain(id):
            try TrainManager.withdraw(id, in: &state)
            return .trainWithdrawn(id)
        case .purchase, .attachCarriage, .detachCarriage, .fitMotor, .removeMotor, .expandStation:
            return try ResourceManager.apply(command, to: &state)
        case let .setExpress(id, express):
            guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
            guard !express || state.config.allowExpress else { throw .expressNotAllowed }
            guard state.lines[index].isExpress != express else { throw .noChange }
            var line = state.lines[index]
            line.isExpress = express
            commit(line, at: index, in: &state)
            return .lineChanged(id)
        }
    }

    // MARK: Validation

    /// Checks a full station sequence for a line (shared by create and drag-edit).
    public static func validate(stations: [StationID], isLoop: Bool, in state: GameState) throws(RouteError) {
        guard stations.count >= 2 else { throw .notEnoughStations }
        var seen = Set<StationID>()
        for id in stations {
            guard state.station(id) != nil else { throw .unknownStation(id) }
            guard seen.insert(id).inserted else { throw .duplicateStation(id) }
        }
        if isLoop {
            guard state.config.allowLoops else { throw .loopsNotAllowed }
            guard stations.count >= 3 else { throw .loopTooShort }
        }
    }

    // MARK: Commands

    @discardableResult
    public static func createLine(stations: [StationID], colorIndex: Int?, isLoop: Bool,
                                  in state: inout GameState) throws(RouteError) -> LineID {
        guard state.availableLineSlots > 0 else { throw .noLineAvailable }
        try validate(stations: stations, isLoop: isLoop, in: state)
        let color: Int
        if let colorIndex {
            guard (0..<state.config.lineColorCount).contains(colorIndex),
                  !state.usedColorIndices.contains(colorIndex) else { throw .invalidColor(colorIndex) }
            color = colorIndex
        } else {
            guard let free = state.firstFreeColorIndex else { throw .noLineAvailable }
            color = free
        }
        let id = LineID(state.nextLineID)
        state.nextLineID += 1
        state.lines.append(MetroLine(id: id, colorIndex: color, stations: stations, isLoop: isLoop))
        state.revision += 1
        TrainManager.lineCreated(id, in: &state)
        return id
    }

    public static func extendLine(_ id: LineID, end: LineEnd, with station: StationID,
                                  in state: inout GameState) throws(RouteError) {
        guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
        guard state.station(station) != nil else { throw .unknownStation(station) }
        var line = state.lines[index]
        guard !line.isLoop else { throw .lineIsLoop }

        let opposite = end == .start ? line.stations.last : line.stations.first
        if station == opposite, line.stations.count >= 3 {
            guard state.config.allowLoops else { throw .loopsNotAllowed }
            line.isLoop = true
        } else {
            guard !line.contains(station) else { throw .stationAlreadyOnLine(station) }
            if end == .start { line.stations.insert(station, at: 0) } else { line.stations.append(station) }
        }
        commit(line, at: index, in: &state)
    }

    public static func insertStation(_ station: StationID, into id: LineID, segment: Int,
                                     in state: inout GameState) throws(RouteError) {
        guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
        guard state.station(station) != nil else { throw .unknownStation(station) }
        var line = state.lines[index]
        guard !line.contains(station) else { throw .stationAlreadyOnLine(station) }
        guard segment >= 0, segment < line.segments.count else { throw .invalidSegment(segment) }
        // Segment i runs from stations[i] to stations[i + 1]; a loop's closing segment wraps to stations[0],
        // so inserting after the last station is the same as appending inside the loop.
        line.stations.insert(station, at: segment + 1)
        commit(line, at: index, in: &state)
    }

    public static func removeStation(_ station: StationID, from id: LineID,
                                     in state: inout GameState) throws(RouteError) -> CommandOutcome {
        guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
        var line = state.lines[index]
        guard let position = line.stations.firstIndex(of: station) else { throw .stationNotOnLine(station) }
        line.stations.remove(at: position)
        if line.stations.count < 2 {
            removeLine(at: index, in: &state)
            return .lineDeleted(id)
        }
        // A loop needs three stations; with two left it becomes an ordinary line.
        if line.isLoop, line.stations.count < 3 {
            line.isLoop = false
        }
        commit(line, at: index, in: &state)
        return .lineChanged(id)
    }

    public static func setStations(_ id: LineID, stations: [StationID], isLoop: Bool,
                                   in state: inout GameState) throws(RouteError) -> CommandOutcome {
        guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
        if stations.count < 2 {
            removeLine(at: index, in: &state)
            return .lineDeleted(id)
        }
        try validate(stations: stations, isLoop: isLoop, in: state)
        var line = state.lines[index]
        guard line.stations != stations || line.isLoop != isLoop else { throw .noChange }
        line.stations = stations
        line.isLoop = isLoop
        commit(line, at: index, in: &state)
        return .lineChanged(id)
    }

    public static func deleteLine(_ id: LineID, in state: inout GameState) throws(RouteError) {
        guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
        removeLine(at: index, in: &state)
    }

    /// The only place lines are removed: its trains retire and finish their trips.
    private static func removeLine(at index: Int, in state: inout GameState) {
        let id = state.lines[index].id
        state.lines.remove(at: index)
        state.revision += 1
        TrainManager.lineDeleted(id, in: &state)
    }

    public static func setColor(_ id: LineID, colorIndex: Int, in state: inout GameState) throws(RouteError) {
        guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
        guard (0..<state.config.lineColorCount).contains(colorIndex) else { throw .invalidColor(colorIndex) }
        let oldColor = state.lines[index].colorIndex
        guard oldColor != colorIndex else { throw .noChange }
        if let other = state.lines.firstIndex(where: { $0.colorIndex == colorIndex }) {
            var swapped = state.lines[other]
            swapped.colorIndex = oldColor
            swapped.revision += 1
            state.lines[other] = swapped
        }
        var line = state.lines[index]
        line.colorIndex = colorIndex
        commit(line, at: index, in: &state)
    }

    public static func openLoop(_ id: LineID, in state: inout GameState) throws(RouteError) {
        guard let index = state.lineIndex(id) else { throw .unknownLine(id) }
        var line = state.lines[index]
        guard line.isLoop else { throw .lineIsNotLoop }
        line.isLoop = false
        commit(line, at: index, in: &state)
    }

    private static func commit(_ line: MetroLine, at index: Int, in state: inout GameState) {
        var line = line
        line.revision += 1
        state.lines[index] = line
        state.revision += 1
    }
}
