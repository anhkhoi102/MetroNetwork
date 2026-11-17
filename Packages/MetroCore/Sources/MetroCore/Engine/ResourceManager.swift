import Foundation

/// The player's limited resources: the depot (spending weekly credits), train upgrades, station expansions,
/// water crossings and the weekly budget. Every item is either in stock or in use — nothing is created or
/// lost except by buying (a retiring train hands its locomotive, carriages and motor back to stock).
public enum ResourceManager {

    static func apply(_ command: GameCommand, to state: inout GameState) throws(RouteError) -> CommandOutcome {
        switch command {
        case .purchase(let item):
            try purchase(item, in: &state)
            return .purchased(item)
        case .attachCarriage(let id):
            try attachCarriage(to: id, in: &state)
            return .trainUpgraded(id)
        case .detachCarriage(let id):
            try detachCarriage(from: id, in: &state)
            return .trainUpgraded(id)
        case .fitMotor(let id):
            try fitMotor(to: id, in: &state)
            return .trainUpgraded(id)
        case .removeMotor(let id):
            try removeMotor(from: id, in: &state)
            return .trainUpgraded(id)
        case .expandStation(let id):
            try expand(id, in: &state)
            return .stationExpanded(id)
        default:
            throw .noChange
        }
    }

    // MARK: Depot

    public static func canAfford(_ item: Purchase, in state: GameState) -> Bool {
        state.resources.credits >= state.config.price(of: item)
    }

    public static func purchase(_ item: Purchase, in state: inout GameState) throws(RouteError) {
        guard state.config.availablePurchases.contains(item) else { throw .notForSale }
        let price = state.config.price(of: item)
        guard state.resources.credits >= price else { throw .notEnoughCredits }
        switch item {
        case .locomotive: state.resources.locomotives += 1
        case .carriage: state.resources.carriages += 1
        case .line:
            guard state.resources.lineSlots < state.config.maxLines else { throw .allLinesUnlocked }
            state.resources.lineSlots += 1
        case .crossings: state.resources.crossings += state.config.crossingsPerPurchase
        case .expansion: state.resources.expansions += 1
        case .motor: state.resources.motors += 1
        }
        state.resources.credits -= price
    }

    // MARK: Train upgrades

    public static func attachCarriage(to id: TrainID, in state: inout GameState) throws(RouteError) {
        let i = try serviceTrain(id, in: state)
        guard state.trains[i].carriages < state.config.maxCarriagesPerTrain else { throw .carriageLimitReached }
        guard state.resources.carriages > 0 else { throw .noCarriagesLeft }
        state.resources.carriages -= 1
        state.trains[i].carriages += 1
        state.trains[i].capacity += state.config.carriageCapacity
    }

    public static func detachCarriage(from id: TrainID, in state: inout GameState) throws(RouteError) {
        let i = try serviceTrain(id, in: state)
        guard state.trains[i].carriages > 0 else { throw .noCarriageToRemove }
        let newCapacity = state.trains[i].capacity - state.config.carriageCapacity
        guard state.trains[i].passengers.count <= newCapacity else { throw .carriageInUse }
        state.trains[i].carriages -= 1
        state.trains[i].capacity = newCapacity
        state.resources.carriages += 1
    }

    public static func fitMotor(to id: TrainID, in state: inout GameState) throws(RouteError) {
        let i = try serviceTrain(id, in: state)
        guard !state.trains[i].hasMotor else { throw .motorAlreadyFitted }
        guard state.resources.motors > 0 else { throw .noMotorsLeft }
        state.resources.motors -= 1
        state.trains[i].hasMotor = true
    }

    public static func removeMotor(from id: TrainID, in state: inout GameState) throws(RouteError) {
        let i = try serviceTrain(id, in: state)
        guard state.trains[i].hasMotor else { throw .noMotorFitted }
        state.trains[i].hasMotor = false
        state.resources.motors += 1
    }

    /// Index of a train still in service (retiring trains can't be upgraded).
    private static func serviceTrain(_ id: TrainID, in state: GameState) throws(RouteError) -> Int {
        guard let i = state.trains.firstIndex(where: { $0.id == id }), !state.trains[i].isRetiring else {
            throw .unknownTrain(id)
        }
        return i
    }

    /// A train left service for good: its locomotive, carriages and motor go back to stock.
    static func returnToStock(_ train: Train, in state: inout GameState) {
        state.resources.locomotives += 1
        state.resources.carriages += train.carriages
        if train.hasMotor { state.resources.motors += 1 }
    }

    // MARK: Stations

    public static func expand(_ id: StationID, in state: inout GameState) throws(RouteError) {
        guard let i = state.stationIndex(id) else { throw .unknownStation(id) }
        guard state.stations[i].special != .grand else { throw .cantExpandGrand }
        guard state.stations[i].expansions < state.config.maxExpansionsPerStation else { throw .stationFullyExpanded }
        guard state.resources.expansions > 0 else { throw .noExpansionsLeft }
        state.resources.expansions -= 1
        state.stations[i].expansions += 1
    }

    // MARK: Water crossings

    /// Crossings in use: one per line segment whose path has to cross water.
    public static func crossingsUsed(in state: GameState) -> Int {
        guard !state.map.water.isEmpty else { return 0 }
        let positions = state.stationPositions
        var cache: [SegmentKey: Bool] = [:]
        var used = 0
        for line in state.lines {
            for (a, b) in line.segments {
                let key = SegmentKey(a, b)
                let wet: Bool
                if let known = cache[key] {
                    wet = known
                } else {
                    wet = RouteGeometry.terrain(key, positions: positions, map: state.map) == .water
                    cache[key] = wet
                }
                if wet { used += 1 }
            }
        }
        return used
    }

    public static func crossingsAvailable(in state: GameState) -> Int {
        max(0, state.resources.crossings - crossingsUsed(in: state))
    }

    // MARK: Weekly budget

    /// Credits for the week that is starting, given last week's deliveries.
    static func weeklyGrant(startingWeek week: Int, deliveredLastWeek delivered: Int,
                            config: GameConfiguration) -> WeeklyGrant {
        let bonus = config.deliveriesPerBonusCredit > 0
            ? min(config.maxBonusCredits, delivered / config.deliveriesPerBonusCredit) : 0
        return WeeklyGrant(week: week, base: config.weeklyCredits, performance: bonus, delivered: delivered)
    }
}
