import Foundation

/// Endless difficulty. The levels differ in resources, room, pressure and how complex the city gets — not
/// just in how fast passengers appear.
public enum Difficulty: String, Codable, CaseIterable, Sendable, Identifiable {
    case easy, normal, hard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .easy: "Easy"
        case .normal: "Normal"
        case .hard: "Hard"
        }
    }

    public var summary: String {
        switch self {
        case .easy: "More trains and credits, roomier stations, gentle growth. Good for learning."
        case .normal: "Balanced resources; the network needs regular rethinking."
        case .hard: "Tight budget, cramped stations, rare shapes early, stronger rush hours and frequent events."
        }
    }
}

extension GameConfiguration {

    /// Endless rules for a difficulty level.
    public static func make(_ difficulty: Difficulty) -> GameConfiguration {
        var c = GameConfiguration()
        c.difficulty = difficulty
        switch difficulty {
        case .easy:
            // More resources and room, slower growth, fewer surprises.
            c.startingCredits = 4
            c.startingLocomotives = 4
            c.startingCrossings = 4
            c.weeklyCredits = 4
            c.stationCapacity = 14
            c.overcrowdTime = 60
            c.passengerSpawnInterval = 13
            c.weeklyDemandGrowth = 0.94
            c.stationSpawnInterval = 22
            c.rareShapesAfterStations = 12
            c.rushIntensity = 1.6
            c.rushIntensityPerWeek = 0.08
            c.eventsFromWeek = 5
            c.eventGapMin = 80
            c.eventGapMax = 120
        case .normal:
            break
        case .hard:
            // Scarcer resources, less room, a more complex city, stronger rush hours, more events.
            c.startingCrossings = 2
            c.deliveriesPerBonusCredit = 25
            c.maxBonusCredits = 2
            c.priceLine = 5
            c.priceExpansion = 3
            c.stationCapacity = 10
            c.overcrowdTime = 40
            c.passengerSpawnInterval = 11
            c.rareShapesAfterStations = 5
            c.rareShapeChance = 0.18
            c.specialStationChance = 0.25
            c.rushIntensity = 2.3
            c.rushIntensityPerWeek = 0.15
            c.maxRushIntensity = 3.4
            c.rushHoursFromWeek = 2
            c.eventsFromWeek = 3
            c.eventGapMin = 45
            c.eventGapMax = 75
        }
        return c
    }
}
