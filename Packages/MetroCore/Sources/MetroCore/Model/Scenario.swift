import Foundation

/// One goal of a campaign level or challenge. Levels mix different kinds so they don't all feel the same.
public enum Objective: Codable, Hashable, Sendable {
    /// Deliver at least this many passengers.
    case deliver(Int)
    /// Reach this score.
    case score(Int)
    /// Have at least this many stations on lines when the level ends.
    case connectedStations(Int)
    /// Average network efficiency of at least this many percent.
    case efficiency(Int)
    /// Never let any station's overcrowding timer pass the halfway mark.
    case calmStations
    /// Deliver this many passengers during rush hours.
    case rushDeliveries(Int)
    /// Never run more than this many lines at once.
    case maxLines(Int)
    /// Reach the end of this week without the network failing (for challenges without a time limit).
    case surviveWeeks(Int)
    /// Deliver this many fans who left the stadium at full time.
    case fansDelivered(Int)
    /// Deliver this many airport travellers on time.
    case travellersOnTime(Int)
}

public enum ScenarioKind: String, Codable, Sendable {
    case campaign
    case challenge
}

/// Numbers a scenario tracks during play (some objectives depend on history, not just the end state).
public struct ScenarioTracking: Codable, Hashable, Sendable {
    public var peakOvercrowding = 0.0
    public var rushDeliveries = 0
    public var peakLines = 0

    public init() {}
}

/// The scenario a session is playing, stored in `GameState` so a saved session restores it exactly.
public struct ScenarioState: Codable, Hashable, Sendable {
    public var id: String
    public var kind: ScenarioKind
    /// The level ends (finished, not lost) when this week ends; nil = until the network fails.
    public var weekLimit: Int?
    /// One star per objective met; the first one is required to pass a campaign level.
    public var objectives: [Objective]
    public var tracking = ScenarioTracking()

    public init(id: String, kind: ScenarioKind, weekLimit: Int?, objectives: [Objective]) {
        self.id = id
        self.kind = kind
        self.weekLimit = weekLimit
        self.objectives = objectives
    }
}

/// How an objective stands right now.
public struct ObjectiveProgress: Hashable, Sendable {
    public var objective: Objective
    /// Current value and target (for progress bars). For "keep below" goals current is the worst so far.
    public var current: Double
    public var target: Double
    public var met: Bool
    /// True when it can no longer be met.
    public var lost: Bool
}

/// The outcome of a finished (or failed) scenario.
public struct ScenarioResult: Hashable, Sendable {
    public var id: String
    public var kind: ScenarioKind
    public var passed: Bool
    /// 0…3 (campaign stars, or challenge medals: bronze, silver, gold).
    public var stars: Int
    public var objectives: [ObjectiveProgress]
    public var score: Int
}
