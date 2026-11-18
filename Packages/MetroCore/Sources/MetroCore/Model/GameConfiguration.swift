import Foundation

/// Every gameplay tunable lives here instead of being hard-coded in the systems.
/// Difficulty levels and campaign levels (later phases) will be different `GameConfiguration` values.
public struct GameConfiguration: Codable, Hashable, Sendable {

    /// The difficulty these rules were made from (informational; scenarios start from `.normal`).
    public var difficulty: Difficulty = .normal

    // MARK: Lines

    /// Most lines a player can ever unlock (one per palette colour).
    public var maxLines = 7
    /// Number of colours in the palette; must be ≥ `maxLines`.
    public var lineColorCount = 7
    public var allowLoops = true

    // MARK: Stations

    public var initialStationCount = 3
    /// Shapes of the starting stations, in order (cycled if shorter than `initialStationCount`).
    public var initialShapes: [StationShape] = [.circle, .triangle, .square]
    /// Shapes that appear regularly, with relative weights.
    public var commonShapes: [StationShape] = [.circle, .triangle, .square]
    public var commonShapeWeights: [Double] = [5, 3, 2]
    /// Rarer shapes that start appearing once the city has grown.
    public var rareShapes: [StationShape] = [.diamond, .star, .hexagon]
    public var rareShapesAfterStations = 8
    public var rareShapeChance = 0.12
    public var maxStationsPerRareShape = 2

    public var maxStations = 45
    /// Simulation seconds between station spawns (before jitter).
    public var stationSpawnInterval = 20.0
    /// Random variation of the spawn interval, as a fraction (0.25 = ±25 %).
    public var stationSpawnJitter = 0.25
    /// Minimum distance between two stations.
    public var stationMinSpacing = 120.0
    /// Minimum distance between a station and any water.
    public var stationWaterClearance = 36.0

    // MARK: City growth

    public var initialCityRadius = 300.0
    public var cityRadiusGrowthPerStation = 26.0
    public var maxCityRadius = 1300.0

    // MARK: Trains

    /// Passengers one train carries.
    public var trainCapacity = 6
    /// Cruising speed, world units per second.
    public var trainMaxSpeed = 95.0
    /// Acceleration and braking, world units per second².
    public var trainAcceleration = 70.0
    /// Crawl speed used for the last few units before a stop, so trains always arrive.
    public var trainMinSpeed = 10.0
    /// Time stopped at every station, plus time per passenger getting on or off.
    public var dwellBase = 0.6
    public var dwellPerPassenger = 0.22
    /// Trains placed automatically on a newly built line.
    public var trainsPerNewLine = 1
    public var maxTrainsPerLine = 4

    // MARK: Passengers

    /// Simulation seconds between passengers appearing at one station (before jitter).
    public var passengerSpawnInterval = 12.0
    /// Random variation of the passenger interval, as a fraction.
    public var passengerSpawnJitter = 0.5
    /// Delay before a new station's first passenger.
    public var firstPassengerDelay = 3.0
    /// Hard safety cap: a station stops generating passengers at this many waiting. Overcrowding ends the
    /// game long before this in normal play; the cap only bounds memory if game over is switched off.
    public var maxWaitingPerStation = 40

    // MARK: Congestion and game over

    /// Passengers a station holds before it counts as overcrowded.
    public var stationCapacity = 12
    /// Extra room per station expansion, and how many expansions one station can take.
    public var expansionCapacity = 8
    public var maxExpansionsPerStation = 2
    /// Seconds a station can stay overcrowded before the network fails (game over).
    public var overcrowdTime = 50.0
    /// Seconds for a full overcrowding timer to drain once the queue is back under capacity.
    public var overcrowdRecoveryTime = 30.0

    // MARK: Resources

    public var startingCredits = 2
    public var startingLineSlots = 3
    public var startingLocomotives = 3
    public var startingCarriages = 0
    public var startingCrossings = 3
    public var startingExpansions = 0
    public var startingMotors = 0

    /// Depot prices, in credits.
    public var priceLocomotive = 3
    public var priceCarriage = 2
    public var priceLine = 4
    public var priceCrossings = 2
    public var priceExpansion = 2
    public var priceMotor = 3
    /// Water crossings in one purchase.
    public var crossingsPerPurchase = 2
    /// Depot items on sale (campaign levels introduce them gradually; some challenges sell nothing).
    public var availablePurchases: [Purchase] = Purchase.allCases
    /// Whether lines may be switched to express service.
    public var allowExpress = true

    // MARK: Train upgrades

    /// Seats added by one carriage, and the most carriages one train can pull.
    public var carriageCapacity = 4
    public var maxCarriagesPerTrain = 2
    /// Each carriage reduces acceleration by this fraction (heavier trains pick up speed more slowly).
    public var carriageAccelerationPenalty = 0.15
    /// A fast motor multiplies cruising speed and acceleration.
    public var motorSpeedFactor = 1.35
    public var motorAccelerationFactor = 1.3

    // MARK: Weeks, budget and difficulty

    /// Simulation seconds per week. Credits are granted and demand rises at the start of every week.
    public var weekLength = 90.0
    public var weeklyCredits = 3
    /// One bonus credit per this many passengers delivered in the week…
    public var deliveriesPerBonusCredit = 20
    /// …up to this many bonus credits.
    public var maxBonusCredits = 3
    /// Passenger intervals are multiplied by this every week (demand grows)…
    public var weeklyDemandGrowth = 0.92
    /// …but never below this fraction of `passengerSpawnInterval`.
    public var minPassengerIntervalFactor = 0.34

    // MARK: Scoring

    public var pointsPerPassenger = 10
    /// Extra points for a fast journey: full bonus up to `quickTripTime`, none from `slowTripTime`.
    public var quickTripBonus = 5
    public var quickTripTime = 30.0
    public var slowTripTime = 90.0

    // MARK: Routing (Phase 4)

    /// Fixed part of the cost of boarding a train (walking to the platform); the expected wait for the
    /// line's next train (half its headway) is added on top, so more trains make a line more attractive.
    public var boardingCost = 3.0
    /// Transfer costs at an interchange station are multiplied by this.
    public var interchangeTransferFactor = 0.35
    /// Time per passenger getting on or off at an interchange station is multiplied by this.
    public var interchangeDwellFactor = 0.5

    // MARK: Special stations

    /// Special stations start appearing at this many stations, with this chance per new station.
    public var specialStationsAfter = 6
    public var specialStationChance = 0.2
    public var maxStationsPerSpecial = 2
    public var hubDemandMultiplier = 1.7
    /// Extra room at hubs and interchanges, and at grand stations (which can't be expanded).
    public var specialBonusCapacity = 4
    public var grandStationCapacity = 14
    /// Lines that may stop at a heritage station.
    public var heritageMaxLines = 2
    /// Stadium and airport (campaign part 2). Nil everywhere else, which also keeps older saves loading.
    public var venues: VenueRules?

    // MARK: Demand patterns

    /// Station demand ranges from `minStationDemand` (quiet outskirts) to `maxStationDemand` (dense districts).
    public var minStationDemand = 0.8
    public var maxStationDemand = 1.3
    /// Destination attraction: central stations up to this many times more popular than outlying ones.
    public var centralAttraction = 2.2
    /// Distance from the centre at which a station counts as fully "outskirts".
    public var outskirtsDistance = 650.0

    // MARK: Rush hour

    public var rushHoursFromWeek = 3
    public var rushHoursPerWeek = 2
    /// Length of a rush hour in days (a day is `weekLength / 7`).
    public var rushHourDays = 1.4
    public var rushIntensity = 2.0
    public var rushIntensityPerWeek = 0.1
    public var maxRushIntensity = 3.0

    // MARK: Network events

    public var eventsFromWeek = 4
    /// Seconds between events (random within the range) and warning before each one.
    public var eventGapMin = 55.0
    public var eventGapMax = 95.0
    public var eventWarning = 8.0
    public var surgeDuration = 25.0
    public var surgeMultiplier = 3.0
    public var touristGroupSize = 5
    public var maintenanceDuration = 25.0
    public var closureDuration = 20.0

    // MARK: Network efficiency

    /// Weight of each factor in the 0–100 score.
    public var efficiencyWaitWeight = 0.35
    public var efficiencyJourneyWeight = 0.25
    public var efficiencyLoadWeight = 0.15
    public var efficiencyCrowdingWeight = 0.25
    /// Waiting time / journey time that scores 0 for its factor.
    public var efficiencyWorstWait = 60.0
    public var efficiencyBestJourney = 20.0
    public var efficiencyWorstJourney = 100.0
    /// Average seat use that counts as fully used.
    public var efficiencyGoodLoad = 0.6
    /// Moving-average weight of each new delivery / sample.
    public var efficiencySmoothing = 0.05

    // MARK: Simulation

    /// Fixed simulation step in seconds.
    public var simulationStep = 1.0 / 30.0
    /// Largest real-time delta accepted per frame (protects against hitches and app resume).
    public var maxFrameDelta = 0.1
    /// Speed multipliers the player can pick from.
    public var speedOptions: [Double] = [1, 2]

    public init() {}

    public func price(of item: Purchase) -> Int {
        switch item {
        case .locomotive: priceLocomotive
        case .carriage: priceCarriage
        case .line: priceLine
        case .crossings: priceCrossings
        case .expansion: priceExpansion
        case .motor: priceMotor
        }
    }

    /// Normal-difficulty Endless rules.
    public static let standard = GameConfiguration()
}
