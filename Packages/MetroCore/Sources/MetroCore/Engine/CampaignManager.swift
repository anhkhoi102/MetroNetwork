import Foundation

/// A playable scenario: a fixed city, its own rules, a time limit and three objectives.
public struct ScenarioDefinition: Identifiable, Sendable {
    public let id: String
    public let kind: ScenarioKind
    public let title: String
    /// What this level introduces, in a few words ("Tunnels", "Rush hour"…).
    public let feature: String
    public let briefing: String
    public let preset: MapPreset
    public let weekLimit: Int?
    public let objectives: [Objective]
    public let config: GameConfiguration

    init(id: String, kind: ScenarioKind, title: String, feature: String, briefing: String, preset: MapPreset,
         weekLimit: Int?, objectives: [Objective], base: Difficulty = .normal,
         rules: (inout GameConfiguration) -> Void = { _ in }) {
        self.id = id
        self.kind = kind
        self.title = title
        self.feature = feature
        self.briefing = briefing
        self.preset = preset
        self.weekLimit = weekLimit
        self.objectives = objectives
        var c = GameConfiguration.make(base)
        rules(&c)
        self.config = c
    }

    var state: ScenarioState { ScenarioState(id: id, kind: kind, weekLimit: weekLimit, objectives: objectives) }
}

/// The campaign: eight cities, each introducing one idea, so no two levels are the same exercise.
/// Fixed seeds make every level identical on every attempt.
public enum CampaignManager {

    public static let levels: [ScenarioDefinition] = [
        ScenarioDefinition(
            id: "c1-first-line", kind: .campaign, title: "First Line", feature: "Lines and trains",
            briefing: "A quiet town needs its first metro. Drag between stations to build lines; each new line takes a spare train. Only the three basic shapes appear.",
            preset: MapPreset(id: "c1", name: "Millbrook", archetype: .lakes, seed: 4_211),
            weekLimit: 2, objectives: [.deliver(45), .connectedStations(10), .deliver(70)]
        ) { c in
            c.rareShapes = []
            c.specialStationChance = 0
            c.rushHoursFromWeek = 99
            c.eventsFromWeek = 99
            c.availablePurchases = [.locomotive, .line]
            c.allowExpress = false
            c.startingCredits = 3
        },
        ScenarioDefinition(
            id: "c2-river", kind: .campaign, title: "Across the River", feature: "Tunnels",
            briefing: "The city sits on both banks. A line can only cross the water through a tunnel: you have three, and the depot sells more.",
            preset: MapPreset(id: "c2", name: "Riverside", archetype: .river, seed: 1_107),
            weekLimit: 3, objectives: [.deliver(150), .connectedStations(16), .efficiency(80)]
        ) { c in
            c.rareShapes = []
            c.specialStationChance = 0
            c.rushHoursFromWeek = 99
            c.eventsFromWeek = 99
            c.availablePurchases = [.locomotive, .line, .crossings]
            c.allowExpress = false
            c.stationSpawnInterval = 17
        },
        ScenarioDefinition(
            id: "c3-platforms", kind: .campaign, title: "Busy Platforms", feature: "Carriages and expansions",
            briefing: "Crowds build up fast here. Couple carriages to busy trains and expand the stations that fill up. Keep every station calm for the extra star.",
            preset: MapPreset(id: "c3", name: "Lakeland", archetype: .lakes, seed: 3_779),
            weekLimit: 4, objectives: [.deliver(230), .calmStations, .deliver(340)]
        ) { c in
            c.rareShapes = []
            c.specialStationChance = 0
            c.rushHoursFromWeek = 99
            c.eventsFromWeek = 99
            c.availablePurchases = [.locomotive, .line, .crossings, .carriage, .expansion]
            c.allowExpress = false
            c.passengerSpawnInterval = 10.5
        },
        ScenarioDefinition(
            id: "c4-shapes", kind: .campaign, title: "New Shapes", feature: "Rare stations and fast motors",
            briefing: "Diamonds, stars and hexagons appear early. Passengers for them travel far: fit fast motors to the trains that carry them.",
            preset: MapPreset(id: "c4", name: "Westhaven", archetype: .coastal, seed: 5_903),
            weekLimit: 4, objectives: [.deliver(220), .connectedStations(16), .score(4_300)]
        ) { c in
            c.rareShapesAfterStations = 4
            c.rareShapeChance = 0.25
            c.specialStationChance = 0
            c.rushHoursFromWeek = 99
            c.eventsFromWeek = 99
            c.availablePurchases = [.locomotive, .line, .crossings, .carriage, .expansion, .motor]
            c.allowExpress = false
        },
        ScenarioDefinition(
            id: "c5-rush", kind: .campaign, title: "Rush Hour", feature: "Rush hours",
            briefing: "Commuters! Twice a week the outskirts (mornings) or the centre (evenings) explode with passengers. The depot tells you which days.",
            preset: MapPreset(id: "c5", name: "Harbour Bay", archetype: .coastal, seed: 2_311),
            weekLimit: 4, objectives: [.deliver(260), .rushDeliveries(120), .efficiency(78)]
        ) { c in
            c.specialStationChance = 0
            c.rushHoursFromWeek = 1
            c.eventsFromWeek = 99
            c.allowExpress = false
        },
        ScenarioDefinition(
            id: "c6-transfers", kind: .campaign, title: "Changing Trains", feature: "Special stations and express",
            briefing: "Hubs, interchanges, heritage and grand stations appear. Express lines skip ordinary stops. Can you keep it to four lines?",
            preset: MapPreset(id: "c6", name: "Twin Lakes", archetype: .lakes, seed: 6_421),
            weekLimit: 5, objectives: [.deliver(380), .maxLines(4), .efficiency(76)]
        ) { c in
            c.specialStationsAfter = 4
            c.specialStationChance = 0.4
            c.eventsFromWeek = 99
        },
        ScenarioDefinition(
            id: "c7-disruptions", kind: .campaign, title: "Disruptions", feature: "Network events",
            briefing: "Closures, crowds, tour groups and train maintenance — each announced a few seconds ahead. Keep the network running through it all.",
            preset: MapPreset(id: "c7", name: "Old Port", archetype: .river, seed: 7_717),
            weekLimit: 5, objectives: [.deliver(260), .surviveWeeks(5), .score(5_200)]
        ) { c in
            c.eventsFromWeek = 2
            c.eventGapMin = 40
            c.eventGapMax = 65
        },
        ScenarioDefinition(
            id: "c8-metropolis", kind: .campaign, title: "Metropolis", feature: "Everything, on Hard",
            briefing: "A big, demanding city with every mechanic switched on and a Hard budget. Plan for growth.",
            preset: MapPreset(id: "c8", name: "Grand Central", archetype: .river, seed: 8_888),
            weekLimit: 6, objectives: [.deliver(300), .efficiency(72), .connectedStations(20)], base: .hard
        ),
        // Part 2: each level adds a new mechanic.
        ScenarioDefinition(
            id: "c9-match-day", kind: .campaign, title: "Match Day", feature: "Stadium crowds",
            briefing: "The city has a stadium, with a match every Wednesday and Saturday. At full time a whole crowd of fans pours out at once: have trains and room ready before the whistle.",
            preset: MapPreset(id: "c9", name: "Kingsfield", archetype: .coastal, seed: 9_901),
            weekLimit: 4, objectives: [.deliver(220), .fansDelivered(36), .surviveWeeks(4)]
        ) { c in
            c.venues = .stadium(after: 4)
            c.startingCarriages = 2
            c.startingCredits = 4
            c.specialStationChance = 0
            c.rushHoursFromWeek = 99
            c.eventsFromWeek = 99
        },
        ScenarioDefinition(
            id: "c10-airport", kind: .campaign, title: "Airport", feature: "Travellers in a hurry",
            briefing: "An airport opens on the edge of town. Travellers who wait too long on a platform give up and take a taxi; get them there quickly for bonus points.",
            preset: MapPreset(id: "c10", name: "Northgate", archetype: .lakes, seed: 10_303),
            weekLimit: 4, objectives: [.deliver(260), .travellersOnTime(35), .score(6_400)]
        ) { c in
            c.venues = .airport(after: 5)
            c.rushHoursFromWeek = 2
            c.eventsFromWeek = 99
        },
    ]

    public static func level(_ id: String) -> ScenarioDefinition? { levels.first { $0.id == id } }
}

/// Challenges: fixed cities with one unusual rule each, played for the best result. Deterministic, so a
/// better plan always gives a better result.
public enum ChallengeManager {

    public static let challenges: [ScenarioDefinition] = [
        ScenarioDefinition(
            id: "x1-two-lines", kind: .challenge, title: "Two Lines Only", feature: "Line limit",
            briefing: "Two lines, never more. Survive as long as you can; medals for score.",
            preset: MapPreset(id: "x1", name: "Twofold", archetype: .lakes, seed: 9_102),
            weekLimit: nil, objectives: [.score(4_000), .score(6_000), .score(8_000)]
        ) { c in
            c.startingLineSlots = 2
            c.availablePurchases = Purchase.allCases.filter { $0 != .line }
        },
        ScenarioDefinition(
            id: "x2-commuters", kind: .challenge, title: "Commuter Belt", feature: "Rush every weekday",
            briefing: "Four strong rush hours every week from the start. Six weeks; medals for passengers delivered.",
            preset: MapPreset(id: "x2", name: "Commuter Belt", archetype: .coastal, seed: 9_215),
            weekLimit: 6, objectives: [.deliver(100), .deliver(140), .deliver(180)]
        ) { c in
            c.rushHoursFromWeek = 1
            c.rushHoursPerWeek = 4
            c.rushIntensity = 2.4
            c.eventsFromWeek = 99
        },
        ScenarioDefinition(
            id: "x3-no-depot", kind: .challenge, title: "Closed Depot", feature: "No purchases",
            briefing: "The depot is shut. You get six trains, two carriages and five tunnels, and that's it.",
            preset: MapPreset(id: "x3", name: "Fixed Fleet", archetype: .river, seed: 9_333),
            weekLimit: nil, objectives: [.score(3_500), .score(5_000), .score(6_000)]
        ) { c in
            c.availablePurchases = []
            c.startingLocomotives = 6
            c.startingCarriages = 2
            c.startingCrossings = 5
            c.startingLineSlots = 4
        },
        ScenarioDefinition(
            id: "x4-islands", kind: .challenge, title: "Islands", feature: "Expensive tunnels",
            briefing: "Lakes everywhere and tunnels cost twice as much. Medals for score after five weeks.",
            preset: MapPreset(id: "x4", name: "Archipelago", archetype: .lakes, seed: 9_471),
            weekLimit: 5, objectives: [.score(3_000), .score(4_500), .score(6_000)]
        ) { c in
            c.startingCrossings = 1
            c.priceCrossings = 4
            c.eventsFromWeek = 99
        },
        ScenarioDefinition(
            id: "x5-chaos", kind: .challenge, title: "Chaos Week", feature: "Events non-stop",
            briefing: "Something goes wrong every half minute from day one. Survive as long as you can.",
            preset: MapPreset(id: "x5", name: "Mayhem", archetype: .river, seed: 9_559),
            weekLimit: nil, objectives: [.surviveWeeks(3), .surviveWeeks(4), .surviveWeeks(5)]
        ) { c in
            c.eventsFromWeek = 1
            c.eventGapMin = 22
            c.eventGapMax = 34
            c.eventWarning = 6
        },
    ]

    public static func challenge(_ id: String) -> ScenarioDefinition? { challenges.first { $0.id == id } }
}

/// Every scenario by id (campaign and challenges).
public enum Scenarios {
    public static func definition(_ id: String) -> ScenarioDefinition? {
        CampaignManager.level(id) ?? ChallengeManager.challenge(id)
    }
}
