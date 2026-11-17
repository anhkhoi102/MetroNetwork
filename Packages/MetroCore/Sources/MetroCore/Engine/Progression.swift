import Foundation

/// What a session is: Endless on a map at a difficulty, or a scenario by id. Saved with the session.
public enum SessionMode: Codable, Hashable, Sendable {
    case endless(MapPreset, Difficulty)
    case scenario(String)

    public var displayName: String {
        switch self {
        case .endless(let preset, let difficulty): "\(preset.name) · \(difficulty.displayName)"
        case .scenario(let id): Scenarios.definition(id)?.title ?? "Scenario"
        }
    }
}

/// A session saved to disk, so the game can continue after the app is closed or killed.
public struct SavedSession: Codable, Sendable {
    public static let formatVersion = 1
    public var version: Int
    public var mode: SessionMode
    public var state: GameState
    public var savedAt: Date

    public init(mode: SessionMode, state: GameState, savedAt: Date = Date()) {
        self.version = Self.formatVersion
        self.mode = mode
        self.state = state
        self.savedAt = savedAt
    }
}

/// Everything the player has achieved. Plain data: the app stores it as JSON; unlock rules live here so
/// they are the same on both platforms and testable.
public struct PlayerProgress: Codable, Hashable, Sendable {

    public struct LevelRecord: Codable, Hashable, Sendable {
        public var stars = 0
        public var bestScore = 0
        public var attempts = 0

        public init(stars: Int = 0, bestScore: Int = 0, attempts: Int = 0) {
            self.stars = stars
            self.bestScore = bestScore
            self.attempts = attempts
        }
    }

    public struct EndlessRecord: Codable, Hashable, Sendable {
        public var bestScore = 0
        public var mostDelivered = 0
        public var longestWeeks = 0
        public var mostStations = 0
        public var bestEfficiency = 0
        public var games = 0
        public init() {}
    }

    public struct Totals: Codable, Hashable, Sendable {
        public var games = 0
        public var passengers = 0
        /// Simulated seconds played.
        public var playTime = 0.0
        public init() {}
    }

    public var campaign: [String: LevelRecord] = [:]
    public var challenges: [String: LevelRecord] = [:]
    /// Keyed by `endlessKey(map:difficulty:)`.
    public var endless: [String: EndlessRecord] = [:]
    public var totals = Totals()
    public var defaultDifficulty: Difficulty = .normal
    /// Sound settings (0…1 volumes).
    public var musicVolume = 0.6
    public var effectsVolume = 0.8
    public var muted = false
    /// Visual theme id (see the app's themes; unlocked by the campaign).
    public var theme = "metropolitan"
    /// Interface language code ("en", "vi"); nil = follow the device.
    public var language: String?

    public init() {}

    // Settings added after Phase 5 decode with defaults, so older progress files keep working.
    private enum CodingKeys: String, CodingKey {
        case campaign, challenges, endless, totals, defaultDifficulty, musicVolume, effectsVolume, muted, theme, language
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        campaign = try c.decodeIfPresent([String: LevelRecord].self, forKey: .campaign) ?? [:]
        challenges = try c.decodeIfPresent([String: LevelRecord].self, forKey: .challenges) ?? [:]
        endless = try c.decodeIfPresent([String: EndlessRecord].self, forKey: .endless) ?? [:]
        totals = try c.decodeIfPresent(Totals.self, forKey: .totals) ?? Totals()
        defaultDifficulty = try c.decodeIfPresent(Difficulty.self, forKey: .defaultDifficulty) ?? .normal
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? 0.6
        effectsVolume = try c.decodeIfPresent(Double.self, forKey: .effectsVolume) ?? 0.8
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "metropolitan"
        language = try c.decodeIfPresent(String.self, forKey: .language)
    }

    public static func endlessKey(map: String, difficulty: Difficulty) -> String { "\(map)|\(difficulty.rawValue)" }

    // MARK: Recording

    /// Adds a finished Endless session.
    public mutating func recordEndless(_ summary: SessionSummary, map: String, difficulty: Difficulty) {
        var r = endless[Self.endlessKey(map: map, difficulty: difficulty)] ?? EndlessRecord()
        r.bestScore = max(r.bestScore, summary.score)
        r.mostDelivered = max(r.mostDelivered, summary.delivered)
        r.longestWeeks = max(r.longestWeeks, summary.week)
        r.mostStations = max(r.mostStations, summary.stations)
        r.bestEfficiency = max(r.bestEfficiency, Int((summary.efficiency ?? 0).rounded()))
        r.games += 1
        endless[Self.endlessKey(map: map, difficulty: difficulty)] = r
        addTotals(summary)
    }

    /// Adds a finished scenario; keeps the best stars and score.
    public mutating func recordScenario(_ result: ScenarioResult, summary: SessionSummary) {
        func update(_ r: inout LevelRecord) {
            r.stars = max(r.stars, result.stars)
            r.bestScore = max(r.bestScore, result.score)
            r.attempts += 1
        }
        switch result.kind {
        case .campaign: var r = campaign[result.id] ?? LevelRecord(); update(&r); campaign[result.id] = r
        case .challenge: var r = challenges[result.id] ?? LevelRecord(); update(&r); challenges[result.id] = r
        }
        addTotals(summary)
    }

    private mutating func addTotals(_ s: SessionSummary) {
        totals.games += 1
        totals.passengers += s.delivered
        totals.playTime += s.elapsed
    }

    public func bestEndless(map: String, difficulty: Difficulty) -> EndlessRecord? {
        endless[Self.endlessKey(map: map, difficulty: difficulty)]
    }

    // MARK: Unlocks

    public var campaignStars: Int { campaign.values.reduce(0) { $0 + $1.stars } }

    /// Levels passed so far, counted in campaign order.
    public var levelsPassed: Int {
        CampaignManager.levels.prefix { (campaign[$0.id]?.stars ?? 0) > 0 }.count
    }

    public func isLevelUnlocked(_ index: Int) -> Bool { index <= levelsPassed }

    /// Endless maps: one to start with, more as the campaign goes on.
    public static let endlessMaps: [(preset: MapPreset, unlockedAfterLevel: Int)] = [
        (MapPreset.builtIn[0], 0),
        (MapPreset.builtIn[1], 2),
        (MapPreset.builtIn[2], 3),
        (MapPreset(id: "twin-rivers", name: "Twin Rivers", archetype: .river, seed: 4_455), 6),
        (MapPreset(id: "old-port", name: "Old Port", archetype: .coastal, seed: 7_070), 7),
    ]

    /// Random cities unlock after this many campaign levels.
    public static let randomCitiesAfterLevel = 5
    public static let hardAfterLevel = 4

    public func isMapUnlocked(_ preset: MapPreset) -> Bool {
        if preset.id.hasPrefix("random") { return levelsPassed >= Self.randomCitiesAfterLevel }
        guard let entry = Self.endlessMaps.first(where: { $0.preset.id == preset.id }) else { return true }
        return levelsPassed >= entry.unlockedAfterLevel
    }

    public func isDifficultyUnlocked(_ difficulty: Difficulty) -> Bool {
        difficulty != .hard || levelsPassed >= Self.hardAfterLevel
    }

    /// Challenges unlock as the campaign introduces what they test.
    public static let challengeUnlocks: [String: Int] = [
        "x1-two-lines": 2, "x2-commuters": 5, "x3-no-depot": 3, "x4-islands": 2, "x5-chaos": 7,
    ]

    public func isChallengeUnlocked(_ id: String) -> Bool { levelsPassed >= (Self.challengeUnlocks[id] ?? 0) }

    /// Visual themes unlock with campaign progress (ids match the app's theme palettes).
    public static let themeUnlocks: [String: Int] = ["metropolitan": 0, "coastal": 2, "old-town": 4, "industrial": 6]

    public func isThemeUnlocked(_ id: String) -> Bool { levelsPassed >= (Self.themeUnlocks[id] ?? 0) }
}
