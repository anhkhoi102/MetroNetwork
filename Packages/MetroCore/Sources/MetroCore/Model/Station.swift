import Foundation

public struct StationID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public static func < (a: StationID, b: StationID) -> Bool { a.raw < b.raw }
    public var description: String { "S\(raw)" }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(Int.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// Destination category of a station. Passengers (Phase 2) travel to "any station of shape X".
public enum StationShape: String, Codable, CaseIterable, Sendable {
    case circle, triangle, square, diamond, star, hexagon

    public var displayName: String {
        switch self {
        case .circle: "Circle"
        case .triangle: "Triangle"
        case .square: "Square"
        case .diamond: "Diamond"
        case .star: "Star"
        case .hexagon: "Hexagon"
        }
    }
}

/// Stations with a character of their own (Phase 4). Each one changes a decision, not just a number.
public enum SpecialStation: String, Codable, CaseIterable, Sendable {
    /// Busy: generates many more passengers, and has a little more room.
    case hub
    /// Built for changing trains: transfers here are much quicker, and it has a little more room.
    case interchange
    /// Listed building: only a limited number of lines may stop here.
    case heritage
    /// Large concourse: lots of room, but it can't be expanded.
    case grand

    public var displayName: String {
        switch self {
        case .hub: "Hub"
        case .interchange: "Interchange"
        case .heritage: "Heritage"
        case .grand: "Grand"
        }
    }
}

public struct Station: Identifiable, Hashable, Codable, Sendable {
    public let id: StationID
    public var shape: StationShape
    public var position: Vec2
    /// Simulation time (seconds) at which the station appeared.
    public var spawnTime: Double
    /// Passengers waiting here, oldest first.
    public var waiting: [Passenger]
    /// Simulation time at which the next passenger appears here.
    public var nextPassengerTime: Double
    /// Expansions built here (each adds `GameConfiguration.expansionCapacity` room).
    public var expansions: Int
    /// Overcrowding timer, 0…1. Fills while more passengers wait than the station holds; 1 ends the game.
    public var overcrowding: Double
    /// Special character, if any.
    public var special: SpecialStation?
    /// How many passengers this station generates relative to normal (busy districts > 1, quiet outskirts < 1).
    public var demand: Double
    /// How strongly the station attracts trips (central, commercial areas > 1).
    public var attraction: Double
    /// 0 (outskirts) … 1 (city centre): who travels in which rush hour.
    public var centrality: Double

    public init(id: StationID, shape: StationShape, position: Vec2, spawnTime: Double,
                waiting: [Passenger] = [], nextPassengerTime: Double = 0, expansions: Int = 0,
                overcrowding: Double = 0, special: SpecialStation? = nil, demand: Double = 1,
                attraction: Double = 1, centrality: Double = 0.5) {
        self.id = id
        self.shape = shape
        self.position = position
        self.spawnTime = spawnTime
        self.waiting = waiting
        self.nextPassengerTime = nextPassengerTime
        self.expansions = expansions
        self.overcrowding = overcrowding
        self.special = special
        self.demand = demand
        self.attraction = attraction
        self.centrality = centrality
    }

    /// Passengers this station holds before it counts as overcrowded.
    public func capacity(_ config: GameConfiguration) -> Int {
        var base = config.stationCapacity
        switch special {
        case .hub, .interchange: base += config.specialBonusCapacity
        case .grand: base += config.grandStationCapacity
        default: break
        }
        return base + expansions * config.expansionCapacity
    }

    /// Expansions this station can still take.
    public func canExpand(_ config: GameConfiguration) -> Bool {
        special != .grand && expansions < config.maxExpansionsPerStation
    }

    public func isOvercrowded(_ config: GameConfiguration) -> Bool {
        waiting.count > capacity(config)
    }
}
