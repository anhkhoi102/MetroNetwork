import Foundation

/// The drag-to-build state machine, shared by mouse and touch input.
///
/// The input layer reports which station (if any) is under the pointer via `hover(_:)`. The editor turns
/// that into a draft line and, on release, into a single `GameCommand`:
/// - **New line:** drag from a station through others. Dragging back onto the previous station undoes the
///   last stop; dragging onto the first station (3+ stops) closes a loop.
/// - **Extend:** drag a terminal handle. Same rules; dragging back along the line shortens it.
/// - **Insert:** drag the middle of a segment onto a station that isn't on the line yet.
public struct RouteEditor: Hashable, Sendable {

    public enum Mode: Hashable, Sendable {
        case newLine
        case extend(LineID, LineEnd)
        case insert(LineID, segment: Int)
    }

    /// Id used for the not-yet-created line while drawing.
    public static let draftLineID = LineID(-1)

    public let mode: Mode
    public let colorIndex: Int
    /// Working station list. For `.extend(_, .start)` it is stored reversed so the active end is always last.
    private var sequence: [StationID]
    public private(set) var isLoop = false
    public private(set) var insertCandidate: StationID?
    private var lastHovered: StationID?
    private let allowLoops: Bool
    private let originalStations: [StationID]

    private init(mode: Mode, colorIndex: Int, sequence: [StationID], originalStations: [StationID],
                 isLoop: Bool = false, allowLoops: Bool, hovered: StationID?) {
        self.mode = mode
        self.isLoop = isLoop
        self.colorIndex = colorIndex
        self.sequence = sequence
        self.originalStations = originalStations
        self.allowLoops = allowLoops
        self.lastHovered = hovered
    }

    // MARK: Starting a drag

    public static func newLine(from station: StationID, in state: GameState) -> Result<RouteEditor, RouteError> {
        guard state.station(station) != nil else { return .failure(.unknownStation(station)) }
        guard state.availableLineSlots > 0, let color = state.firstFreeColorIndex else {
            return .failure(.noLineAvailable)
        }
        return .success(RouteEditor(mode: .newLine, colorIndex: color, sequence: [station], originalStations: [],
                                    allowLoops: state.config.allowLoops, hovered: station))
    }

    public static func extend(_ id: LineID, from end: LineEnd, in state: GameState) -> Result<RouteEditor, RouteError> {
        guard let line = state.line(id) else { return .failure(.unknownLine(id)) }
        guard !line.isLoop else { return .failure(.lineIsLoop) }
        let sequence = end == .start ? Array(line.stations.reversed()) : line.stations
        return .success(RouteEditor(mode: .extend(id, end), colorIndex: line.colorIndex, sequence: sequence,
                                    originalStations: line.stations, allowLoops: state.config.allowLoops,
                                    hovered: sequence.last))
    }

    public static func insert(into id: LineID, segment: Int, in state: GameState) -> Result<RouteEditor, RouteError> {
        guard let line = state.line(id) else { return .failure(.unknownLine(id)) }
        guard segment >= 0, segment < line.segments.count else { return .failure(.invalidSegment(segment)) }
        return .success(RouteEditor(mode: .insert(id, segment: segment), colorIndex: line.colorIndex,
                                    sequence: line.stations, originalStations: line.stations,
                                    isLoop: line.isLoop, allowLoops: state.config.allowLoops, hovered: nil))
    }

    // MARK: Dragging

    /// Report the station under the pointer (nil when over empty map). Only changes trigger edits.
    public mutating func hover(_ station: StationID?) {
        guard station != lastHovered else { return }
        lastHovered = station

        if case .insert = mode {
            insertCandidate = station.flatMap { originalStations.contains($0) ? nil : $0 }
            return
        }
        guard let s = station else { return }

        if isLoop {
            // A closed draft can only be reopened by moving back to the stop before the closure.
            if s == sequence.last { isLoop = false }
            return
        }
        if sequence.count >= 2, s == sequence[sequence.count - 2] {
            sequence.removeLast()
        } else if allowLoops, sequence.count >= 3, s == sequence.first {
            isLoop = true
        } else if !sequence.contains(s) {
            sequence.append(s)
        }
    }

    // MARK: Results

    public var lineID: LineID {
        switch mode {
        case .newLine: Self.draftLineID
        case .extend(let id, _), .insert(let id, _): id
        }
    }

    /// Station order as it would be committed.
    public var stations: [StationID] {
        switch mode {
        case .newLine: return sequence
        case .extend(_, let end): return end == .start ? sequence.reversed() : sequence
        case .insert(_, let segment):
            guard let c = insertCandidate else { return originalStations }
            var s = originalStations
            s.insert(c, at: min(segment + 1, s.count))
            return s
        }
    }

    /// The line as it should be drawn right now.
    public var draftLine: MetroLine {
        MetroLine(id: lineID, colorIndex: colorIndex, stations: stations, isLoop: isLoop)
    }

    /// Station the rubber band to the pointer starts from (nil while a loop is closed, or in insert mode).
    public var tailAnchor: StationID? {
        switch mode {
        case .newLine, .extend: isLoop ? nil : sequence.last
        case .insert: nil
        }
    }

    /// The command to apply on release, or nil when the drag changed nothing.
    public func commitCommand() -> GameCommand? {
        switch mode {
        case .newLine:
            guard sequence.count >= 2 else { return nil }
            return .createLine(stations: sequence, colorIndex: colorIndex, isLoop: isLoop)
        case .extend(let id, _):
            let final = stations
            guard final != originalStations || isLoop else { return nil }
            return .setStations(id, stations: final, isLoop: isLoop)
        case .insert(let id, let segment):
            guard let c = insertCandidate else { return nil }
            return .insertStation(id, station: c, segment: segment)
        }
    }
}
