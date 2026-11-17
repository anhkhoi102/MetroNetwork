import Foundation

/// Things the player can buy in the depot with weekly credits.
public enum Purchase: String, Codable, CaseIterable, Sendable {
    /// A spare train, placed on a line from the line card.
    case locomotive
    /// Extra seats, coupled to one train.
    case carriage
    /// One more line (colour) to build with.
    case line
    /// A pack of water crossings (tunnels), used by line segments that cross water.
    case crossings
    /// More room at one station before it becomes overcrowded.
    case expansion
    /// A faster motor for one train.
    case motor
}

/// What the player owns. Spare items sit here until they are used; items in use are counted elsewhere
/// (trains on lines, carriages and motors on trains, crossings on line segments).
public struct ResourceStock: Codable, Hashable, Sendable {
    public var credits: Int
    /// Lines the player may have at once (unlocked slots), never more than `GameConfiguration.maxLines`.
    public var lineSlots: Int
    /// Spare trains.
    public var locomotives: Int
    /// Spare carriages.
    public var carriages: Int
    /// Water crossings owned in total (used ones included; see `ResourceManager.crossingsUsed`).
    public var crossings: Int
    /// Spare station expansions.
    public var expansions: Int
    /// Spare fast motors.
    public var motors: Int

    public init(credits: Int = 0, lineSlots: Int = 0, locomotives: Int = 0, carriages: Int = 0,
                crossings: Int = 0, expansions: Int = 0, motors: Int = 0) {
        self.credits = credits
        self.lineSlots = lineSlots
        self.locomotives = locomotives
        self.carriages = carriages
        self.crossings = crossings
        self.expansions = expansions
        self.motors = motors
    }

    /// The opening stock defined by a configuration.
    public init(config: GameConfiguration) {
        self.init(credits: config.startingCredits,
                  lineSlots: min(config.startingLineSlots, config.maxLines),
                  locomotives: config.startingLocomotives,
                  carriages: config.startingCarriages,
                  crossings: config.startingCrossings,
                  expansions: config.startingExpansions,
                  motors: config.startingMotors)
    }
}

/// Credits handed out at the start of a week.
public struct WeeklyGrant: Codable, Hashable, Sendable {
    /// The week that just began.
    public var week: Int
    public var base: Int
    /// Extra credits for passengers delivered last week.
    public var performance: Int
    /// Passengers delivered last week.
    public var delivered: Int

    public init(week: Int, base: Int, performance: Int, delivered: Int) {
        self.week = week
        self.base = base
        self.performance = performance
        self.delivered = delivered
    }

    public var total: Int { base + performance }
}

/// Running score and the numbers shown in the end-of-session summary.
public struct SessionStats: Codable, Hashable, Sendable {
    public var score = 0
    public var deliveredThisWeek = 0
    /// Most passengers delivered in one completed week.
    public var bestWeek = 0
    /// Sum of door-to-door journey times of delivered passengers (seconds).
    public var journeyTimeTotal = 0.0
    public var lastGrant: WeeklyGrant?

    public init() {}
}

/// Why and when a session ended.
public struct GameOverInfo: Codable, Hashable, Sendable {
    /// The station that stayed overcrowded for too long.
    public var station: StationID
    public var time: Double

    public init(station: StationID, time: Double) {
        self.station = station
        self.time = time
    }
}

public enum GameStatus: Codable, Hashable, Sendable {
    case running
    /// Lost: a station stayed overcrowded too long.
    case over(GameOverInfo)
    /// A scenario's time limit was reached.
    case finished(time: Double)
}

/// End-of-session numbers, derived from `GameState`.
public struct SessionSummary: Hashable, Sendable {
    public var score: Int
    public var delivered: Int
    /// Simulation seconds played.
    public var elapsed: Double
    public var week: Int
    public var stations: Int
    /// Average door-to-door journey (seconds); nil before the first delivery.
    public var averageJourney: Double?
    /// Most passengers delivered in a single week.
    public var bestWeek: Int
    /// Average network efficiency (0–100) over the session; nil before the first delivery.
    public var efficiency: Double?
}
