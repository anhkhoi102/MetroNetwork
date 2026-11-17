import Foundation

public struct LineID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public static func < (a: LineID, b: LineID) -> Bool { a.raw < b.raw }
    public var description: String { "L\(raw)" }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(Int.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

public enum LineEnd: String, Codable, Sendable {
    case start, end
}

/// A transit line: an ordered list of stations, optionally closed into a loop.
public struct MetroLine: Identifiable, Hashable, Codable, Sendable {
    public let id: LineID
    /// Index into the line colour palette (`GameConfiguration.lineColorCount`).
    public var colorIndex: Int
    public var stations: [StationID]
    /// When true the last station connects back to the first.
    public var isLoop: Bool
    /// Bumped on every change, so renderers can rebuild only lines that changed.
    public var revision: Int
    /// Express service: trains stop only at interchanges, line ends and special stations (see `StopRules`).
    public var isExpress: Bool

    public init(id: LineID, colorIndex: Int, stations: [StationID], isLoop: Bool = false, revision: Int = 0,
                isExpress: Bool = false) {
        self.id = id
        self.colorIndex = colorIndex
        self.stations = stations
        self.isLoop = isLoop
        self.revision = revision
        self.isExpress = isExpress
    }

    /// Consecutive station pairs, including the closing pair of a loop.
    public var segments: [(StationID, StationID)] {
        guard stations.count > 1 else { return [] }
        var result: [(StationID, StationID)] = []
        result.reserveCapacity(stations.count)
        for i in 0..<(stations.count - 1) {
            result.append((stations[i], stations[i + 1]))
        }
        if isLoop, stations.count > 2 {
            result.append((stations[stations.count - 1], stations[0]))
        }
        return result
    }

    public func contains(_ station: StationID) -> Bool { stations.contains(station) }

    public func terminal(_ end: LineEnd) -> StationID? {
        guard !isLoop else { return nil }
        return end == .start ? stations.first : stations.last
    }
}
