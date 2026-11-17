import Foundation

/// Every player action that changes the game. Commands are the only way UI and input mutate `GameState`.
public enum GameCommand: Hashable, Codable, Sendable {
    /// New line through `stations` in order. `colorIndex` nil = first free colour.
    case createLine(stations: [StationID], colorIndex: Int?, isLoop: Bool)
    /// Add a station at one end of a line. Adding the opposite terminal closes the line into a loop.
    case extendLine(LineID, end: LineEnd, station: StationID)
    /// Insert a station between `stations[segment]` and the next station (or the first one, for a loop's closing segment).
    case insertStation(LineID, station: StationID, segment: Int)
    /// Remove a station from a line. A line left with fewer than two stations is deleted.
    case removeStation(LineID, station: StationID)
    /// Replace a line's whole station sequence (used by drag editing). Fewer than two stations deletes the line.
    case setStations(LineID, stations: [StationID], isLoop: Bool)
    case deleteLine(LineID)
    /// Change colour; if another line already uses it, the two lines swap colours.
    case setLineColor(LineID, colorIndex: Int)
    /// Turn a loop into an ordinary line by removing its closing segment.
    case openLoop(LineID)
    /// Put another train on a line.
    case addTrain(LineID)
    /// Withdraw a train from a line (it finishes its trip, lets everyone off, then disappears).
    case removeTrain(LineID)
    /// Withdraw one specific train.
    case withdrawTrain(TrainID)

    // Resources (Phase 3)
    /// Spend credits in the depot.
    case purchase(Purchase)
    /// Couple a spare carriage to a train, or uncouple one back into stock.
    case attachCarriage(TrainID)
    case detachCarriage(TrainID)
    /// Fit a spare fast motor to a train, or take it off back into stock.
    case fitMotor(TrainID)
    case removeMotor(TrainID)
    /// Use a spare expansion on a station (permanent).
    case expandStation(StationID)

    // Route management (Phase 4)
    /// Express service: stop only at interchanges, line ends and special stations.
    case setExpress(LineID, Bool)

    /// True for commands that can change which station pairs lines run between.
    var changesLines: Bool {
        switch self {
        case .createLine, .extendLine, .insertStation, .removeStation, .setStations, .deleteLine, .openLoop: true
        default: false
        }
    }
}

public enum CommandOutcome: Hashable, Sendable {
    case lineCreated(LineID)
    case lineChanged(LineID)
    case lineDeleted(LineID)
    case trainAdded(TrainID)
    case trainWithdrawn(TrainID)
    case purchased(Purchase)
    case trainUpgraded(TrainID)
    case stationExpanded(StationID)
}

public enum RouteError: Error, Hashable, Sendable {
    case unknownStation(StationID)
    case unknownLine(LineID)
    case notEnoughStations
    case duplicateStation(StationID)
    case noLineAvailable
    case invalidColor(Int)
    case stationAlreadyOnLine(StationID)
    case stationNotOnLine(StationID)
    case lineIsLoop
    case lineIsNotLoop
    case loopsNotAllowed
    case loopTooShort
    case invalidSegment(Int)
    case noChange
    case trainLimitReached
    case noTrainToRemove
    case unknownTrain(TrainID)
    case noTrainsLeft
    case noCrossingsLeft
    case notEnoughCredits
    case allLinesUnlocked
    case noCarriagesLeft
    case carriageLimitReached
    case noCarriageToRemove
    case carriageInUse
    case noMotorsLeft
    case motorAlreadyFitted
    case noMotorFitted
    case noExpansionsLeft
    case stationFullyExpanded
    case cantExpandGrand
    case heritageLineLimit
    case notForSale
    case expressNotAllowed
    case sessionOver

    /// Short player-facing explanation.
    public var message: String {
        switch self {
        case .unknownStation, .unknownLine, .invalidSegment, .noChange: "That edit isn't possible."
        case .notEnoughStations: "A line needs at least two stations."
        case .duplicateStation, .stationAlreadyOnLine: "A line can only visit a station once."
        case .noLineAvailable: "No free lines left."
        case .invalidColor: "That colour isn't available."
        case .stationNotOnLine: "That station isn't on this line."
        case .lineIsLoop: "Loops have no ends to extend."
        case .lineIsNotLoop: "This line isn't a loop."
        case .loopsNotAllowed: "Loops aren't allowed here."
        case .loopTooShort: "A loop needs at least three stations."
        case .trainLimitReached: "This line already has the maximum number of trains."
        case .unknownTrain: "That train has already left."
        case .noTrainToRemove: "This line has no trains."
        case .noTrainsLeft: "No spare trains. Buy one in the depot."
        case .noCrossingsLeft: "Not enough tunnels to cross the water. Buy more in the depot."
        case .notEnoughCredits: "Not enough credits."
        case .allLinesUnlocked: "You already have every line."
        case .noCarriagesLeft: "No spare carriages. Buy one in the depot."
        case .carriageLimitReached: "This train can't pull any more carriages."
        case .noCarriageToRemove: "This train has no carriages."
        case .carriageInUse: "Too many passengers on board to uncouple a carriage."
        case .noMotorsLeft: "No spare motors. Buy one in the depot."
        case .motorAlreadyFitted: "This train already has a fast motor."
        case .noMotorFitted: "This train has no fast motor."
        case .noExpansionsLeft: "No spare expansions. Buy one in the depot."
        case .stationFullyExpanded: "This station can't be expanded any further."
        case .cantExpandGrand: "Grand stations can't be expanded."
        case .heritageLineLimit: "Heritage stations allow only a limited number of lines."
        case .notForSale: "That isn't sold here."
        case .expressNotAllowed: "Express service isn't available here."
        case .sessionOver: "The game is over."
        }
    }
}

/// Things that happened, for renderers, sound and UI feedback. Drained once per frame.
public enum GameEvent: Hashable, Sendable {
    case stationSpawned(StationID)
    case lineCreated(LineID)
    case lineChanged(LineID)
    case lineDeleted(LineID)
    case trainAdded(TrainID)
    case trainRemoved(TrainID)
    case trainArrived(TrainID, StationID)
    case passengerSpawned(StationID)
    case passengerDelivered(StationID)
    /// A new week began and credits were granted.
    case weekStarted(WeeklyGrant)
    /// A station just started to overcrowd (its timer left zero).
    case stationOvercrowding(StationID)
    case purchased(Purchase)
    case trainUpgraded(TrainID)
    case stationExpanded(StationID)
    case gameOver(GameOverInfo)
    /// A network event was announced (it starts `GameConfiguration.eventWarning` seconds later), started or ended.
    case networkEventAnnounced(NetworkEvent)
    case networkEventStarted(NetworkEvent)
    case networkEventEnded(NetworkEvent)
    /// A scenario's time limit was reached (the session is finished, not lost).
    case scenarioFinished
    /// For animation: passengers got on a train, or got off to change trains / wait (not delivered).
    case passengersBoarded(TrainID, StationID, count: Int)
    case passengersAlighted(TrainID, StationID, count: Int)
    /// Points earned by a delivery at a station.
    case pointsScored(StationID, Int)
}
