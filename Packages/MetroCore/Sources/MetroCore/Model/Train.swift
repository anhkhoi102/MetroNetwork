import Foundation

public struct TrainID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public static func < (a: TrainID, b: TrainID) -> Bool { a.raw < b.raw }
    public var description: String { "T\(raw)" }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(Int.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// A passenger who wants to reach any station of `destination` shape.
public struct Passenger: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let destination: StationShape
    public let origin: StationID
    public let spawnTime: Double
    /// Seconds spent waiting on platforms so far (for network efficiency).
    public var waited: Double
    /// Times this passenger changed trains.
    public var transfers: Int
    /// When they started waiting on the current platform.
    public var queuedSince: Double

    public init(id: Int, destination: StationShape, origin: StationID, spawnTime: Double) {
        self.id = id
        self.destination = destination
        self.origin = origin
        self.spawnTime = spawnTime
        self.waited = 0
        self.transfers = 0
        self.queuedSince = spawnTime
    }
}

/// A train always travels between two stations (`from` → `to`), so it never depends on line geometry
/// to know where it is. A train whose line was deleted (`lineID == nil`) finishes its trip, lets everyone
/// off and is removed.
public struct Train: Identifiable, Hashable, Codable, Sendable {

    public enum Phase: Hashable, Codable, Sendable {
        case moving
        /// Stopped at `to`, with seconds left before departure.
        case dwelling(remaining: Double)
    }

    public let id: TrainID
    /// nil = retiring (its line was deleted or it was withdrawn).
    public var lineID: LineID?
    /// Seats, carriages included.
    public var capacity: Int
    /// Carriages coupled to this train (each adds `GameConfiguration.carriageCapacity` seats).
    public var carriages: Int
    /// Fitted with a fast motor.
    public var hasMotor: Bool
    /// Out of service for maintenance until this time: lets everyone off at its next stop, then waits there.
    public var maintenanceUntil: Double?
    public var from: StationID
    public var to: StationID
    /// Distance travelled from `from` towards `to`.
    public var progress: Double
    public var speed: Double
    /// Travel direction along the line's station order: +1 or -1.
    public var direction: Int
    public var phase: Phase
    public var passengers: [Passenger]

    public init(id: TrainID, lineID: LineID?, capacity: Int, at station: StationID, direction: Int = 1,
                phase: Phase = .dwelling(remaining: 0.5)) {
        self.id = id
        self.lineID = lineID
        self.capacity = capacity
        self.carriages = 0
        self.hasMotor = false
        self.maintenanceUntil = nil
        self.from = station
        self.to = station
        self.progress = 0
        self.speed = 0
        self.direction = direction
        self.phase = phase
        self.passengers = []
    }

    public var isRetiring: Bool { lineID == nil }
    public var freeSeats: Int { max(0, capacity - passengers.count) }

    /// Cruising speed with this train's motor.
    public func maxSpeed(_ config: GameConfiguration) -> Double {
        config.trainMaxSpeed * (hasMotor ? config.motorSpeedFactor : 1)
    }

    /// Acceleration and braking with this train's motor and load of carriages.
    public func acceleration(_ config: GameConfiguration) -> Double {
        config.trainAcceleration * (hasMotor ? config.motorAccelerationFactor : 1)
            / (1 + config.carriageAccelerationPenalty * Double(carriages))
    }

    public var isDwelling: Bool {
        if case .dwelling = phase { return true }
        return false
    }
}
