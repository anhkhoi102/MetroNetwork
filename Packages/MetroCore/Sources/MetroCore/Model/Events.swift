import Foundation

/// A period of heavy demand. Two per week from `GameConfiguration.rushHoursFromWeek`, announced at the
/// start of the week so the player can prepare, on days drawn at random so it never becomes routine.
public struct RushHour: Codable, Hashable, Sendable {
    public enum Flow: String, Codable, Sendable {
        /// Morning: the outskirts (homes) generate far more passengers.
        case toCentre
        /// Evening: the centre generates far more passengers.
        case fromCentre
    }

    public var flow: Flow
    public var start: Double
    public var end: Double
    /// Spawn-rate multiplier at the stations this rush affects most.
    public var intensity: Double

    public init(flow: Flow, start: Double, end: Double, intensity: Double) {
        self.flow = flow
        self.start = start
        self.end = end
        self.intensity = intensity
    }

    public func isActive(at time: Double) -> Bool { time >= start && time < end }

    /// Extra demand at a station with the given centrality (0 outskirts … 1 centre).
    public func multiplier(centrality: Double) -> Double {
        let exposure = flow == .toCentre ? 1 - centrality : centrality
        return 1 + (intensity - 1) * min(1, max(0, exposure))
    }
}

/// Occasional disruptions. Each one is announced `GameConfiguration.eventWarning` seconds before it starts,
/// lasts a fixed time and never overlaps another one.
public struct NetworkEvent: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: Codable, Hashable, Sendable {
        /// The station generates passengers much faster (concert, match, festival).
        case surge(StationID)
        /// A group of passengers for one (usually rare) shape arrives at once.
        case touristGroup(StationID, StationShape, count: Int)
        /// A train lets everyone off at its next stop and waits there until the work is done.
        case maintenance(TrainID)
        /// Trains run through without stopping; nobody arrives there and its overcrowding timer is frozen.
        case closure(StationID)
    }

    public let id: Int
    public var kind: Kind
    /// When the warning appears.
    public var announced: Double
    public var start: Double
    public var end: Double
    /// Set once its effect has been applied.
    public var started = false

    public init(id: Int, kind: Kind, announced: Double, start: Double, end: Double) {
        self.id = id
        self.kind = kind
        self.announced = announced
        self.start = start
        self.end = end
    }

    public func isActive(at time: Double) -> Bool { time >= start && time < end }

    public var station: StationID? {
        switch kind {
        case .surge(let s), .closure(let s), .touristGroup(let s, _, _): s
        case .maintenance: nil
        }
    }
}

/// Rolling measures of how well the network works, and the 0–100 score built from them.
public struct NetworkEfficiency: Codable, Hashable, Sendable {
    /// Exponential moving averages over recent deliveries.
    public var averageWait: Double = 0
    public var averageJourney: Double = 0
    public var averageTransfers: Double = 0
    /// Sampled once a second: share of seats in use on trains in service, and share of stations that are
    /// more than three-quarters full.
    public var utilization: Double = 0
    public var congestion: Double = 0
    /// True once there has been at least one delivery.
    public var hasData = false
    /// 0–100.
    public var score: Double = 0
    /// Time-weighted running total, for the session average.
    public var scoreTimeTotal: Double = 0
    public var scoredTime: Double = 0
    public var nextSample: Double = 0

    public init() {}

    public var sessionAverage: Double? { scoredTime > 0 ? scoreTimeTotal / scoredTime : nil }

    /// Each factor 0 (bad) … 1 (good), for the breakdown card.
    public struct Factors: Hashable, Sendable {
        public var waiting: Double
        public var journey: Double
        public var load: Double
        public var crowding: Double
    }
}
