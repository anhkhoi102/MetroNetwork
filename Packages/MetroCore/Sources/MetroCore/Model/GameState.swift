import Foundation

/// Station-spawning bookkeeping, including the RNG that drives it.
public struct SpawnState: Hashable, Codable, Sendable {
    public var rng: SeededRandom
    /// Simulation time at which the next station appears.
    public var nextSpawnTime: Double

    public init(rng: SeededRandom, nextSpawnTime: Double) {
        self.rng = rng
        self.nextSpawnTime = nextSpawnTime
    }
}

/// The complete, serialisable state of one game session. A value type: copying it snapshots the game.
public struct GameState: Codable, Hashable, Sendable {
    public var config: GameConfiguration
    public var map: MapDefinition
    /// Stations in spawn order.
    public var stations: [Station]
    /// Lines in creation order.
    public var lines: [MetroLine]
    /// Simulation time in seconds.
    public var elapsed: Double
    public var spawn: SpawnState
    public var nextStationID: Int
    public var nextLineID: Int
    /// Bumped on every change to stations or lines (not on passenger or train movement).
    public var revision: Int

    // MARK: Trains and passengers
    public var trains: [Train]
    public var nextTrainID: Int
    /// Separate random stream for passengers, so station spawning is unaffected by passenger activity.
    public var passengerRNG: SeededRandom
    public var nextPassengerID: Int
    /// Passengers generated so far.
    public var passengersSpawned: Int
    /// Passengers who reached a station of their destination shape.
    public var passengersDelivered: Int

    // MARK: Resources, score and progression
    public var resources: ResourceStock
    /// Current week, starting at 1.
    public var week: Int
    public var stats: SessionStats
    public var status: GameStatus

    // MARK: Demand, events and efficiency (Phase 4)
    /// Separate random stream for rush hours and network events.
    public var eventRNG: SeededRandom
    /// Rush hours announced for the current week (and possibly still running from the last one).
    public var rushHours: [RushHour]
    /// Announced and running events, oldest first; finished ones are removed.
    public var events: [NetworkEvent]
    public var nextEventID: Int
    /// When the next event will be announced.
    public var nextEventTime: Double
    public var efficiency: NetworkEfficiency

    // MARK: Scenario (Phase 5)
    /// Set for campaign levels and challenges; nil in Endless.
    public var scenario: ScenarioState?

    // MARK: Venues (campaign part 2)
    /// Stadium and airport bookkeeping; nil when the rules have no venues (and in older saves).
    public var venues: VenueState?
    /// New districts announced and opened; nil when the rules have none (and in older saves).
    public var newDistricts: DistrictState?
    /// Whether the drawbridges were up at the last step (to announce lifts once); nil without drawbridges.
    public var bridgesUp: Bool?

    public init(config: GameConfiguration, map: MapDefinition, spawn: SpawnState) {
        self.config = config
        self.map = map
        self.stations = []
        self.lines = []
        self.elapsed = 0
        self.spawn = spawn
        self.nextStationID = 1
        self.nextLineID = 1
        self.revision = 0
        self.trains = []
        self.nextTrainID = 1
        self.passengerRNG = SeededRandom(seed: spawn.rng.state ^ 0x5EED_0F_9A55_E46E)
        self.nextPassengerID = 1
        self.passengersSpawned = 0
        self.passengersDelivered = 0
        self.resources = ResourceStock(config: config)
        self.week = 1
        self.stats = SessionStats()
        self.status = .running
        self.eventRNG = SeededRandom(seed: spawn.rng.state ^ 0xE7E7_0123_4567_89AB)
        self.rushHours = []
        self.events = []
        self.nextEventID = 1
        self.nextEventTime = Double(max(0, config.eventsFromWeek - 1)) * config.weekLength + config.eventGapMin * 0.5
        self.efficiency = NetworkEfficiency()
        self.scenario = nil
        self.venues = config.venues == nil ? nil : VenueState()
        self.newDistricts = config.newDistricts == nil ? nil : DistrictState()
    }

    /// The rush hour running now, if any.
    public var activeRushHour: RushHour? { rushHours.first { $0.isActive(at: elapsed) } }

    /// Events that have started and not yet ended.
    public var activeEvents: [NetworkEvent] { events.filter { $0.isActive(at: elapsed) } }

    public func isClosed(_ station: StationID) -> Bool {
        events.contains { if case .closure(let s) = $0.kind { s == station && $0.isActive(at: elapsed) } else { false } }
    }

    /// True once the session has ended, lost or finished; the simulation stops and commands are refused.
    public var isOver: Bool {
        if case .running = status { return false }
        return true
    }

    /// True when a scenario reached its time limit.
    public var isFinished: Bool {
        if case .finished = status { return true }
        return false
    }

    public var gameOver: GameOverInfo? {
        if case .over(let info) = status { return info }
        return nil
    }

    /// Day of the current week, 0 (first) … 6.
    public var dayOfWeek: Int {
        let into = elapsed - Double(week - 1) * config.weekLength
        return min(6, max(0, Int(into / config.weekLength * 7)))
    }

    // MARK: Lookups

    public func station(_ id: StationID) -> Station? {
        stations.first { $0.id == id }
    }

    public func line(_ id: LineID) -> MetroLine? {
        lines.first { $0.id == id }
    }

    public func lineIndex(_ id: LineID) -> Int? {
        lines.firstIndex { $0.id == id }
    }

    public func stationIndex(_ id: StationID) -> Int? {
        stations.firstIndex { $0.id == id }
    }

    public func train(_ id: TrainID) -> Train? {
        trains.first { $0.id == id }
    }

    /// Trains currently serving `line` (retiring trains excluded).
    public func trains(on line: LineID) -> [Train] {
        trains.filter { $0.lineID == line }
    }

    /// Passengers who gave up and left the network (airport travellers who waited too long).
    /// Every passenger ever spawned is delivered, in the network, or here.
    public var passengersGaveUp: Int { venues?.travellersGaveUp ?? 0 }

    /// Passengers waiting at stations plus passengers on trains.
    public var passengersInNetwork: Int {
        stations.reduce(0) { $0 + $1.waiting.count } + trains.reduce(0) { $0 + $1.passengers.count }
    }

    /// Lines that stop at `station`, in creation order.
    public func lines(serving station: StationID) -> [MetroLine] {
        lines.filter { $0.contains(station) }
    }

    /// Station positions keyed by id (for geometry).
    public var stationPositions: [StationID: Vec2] {
        Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0.position) })
    }

    public var usedColorIndices: Set<Int> { Set(lines.map(\.colorIndex)) }

    /// Lowest palette colour not used by any line.
    public var firstFreeColorIndex: Int? {
        let used = usedColorIndices
        return (0..<config.lineColorCount).first { !used.contains($0) }
    }

    /// Lines that can still be built with the slots the player owns.
    public var availableLineSlots: Int { max(0, min(resources.lineSlots, config.maxLines) - lines.count) }

    /// Current radius of the area in which new stations may appear.
    public var cityRadius: Double {
        let grown = config.initialCityRadius
            + Double(max(0, stations.count - config.initialStationCount)) * config.cityRadiusGrowthPerStation
        return min(config.maxCityRadius, grown)
    }
}
