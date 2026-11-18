import Foundation

/// Campaign part 2: venues, stations with an event of their own. A **stadium** sends a whole crowd of fans
/// out at full time; an **airport** sends travellers who are in a hurry and give up if they wait too long.
/// Off unless a level switches them on, so Endless and the first eight levels are unchanged.
public struct VenueRules: Codable, Hashable, Sendable {

    // MARK: Stadium

    /// The stadium is the station that appears when the city has this many; nil = no stadium.
    public var stadiumAfterStations: Int?
    /// Extra room on the stadium's platforms.
    public var stadiumBonusCapacity = 16
    /// Ordinary passengers at the stadium between matches, relative to a normal station.
    public var stadiumDemandFactor = 0.5
    /// Days of the week (0 = Monday) with a match, and when in the day the final whistle blows (0…1).
    public var matchDays: [Int] = [2, 5]
    public var fullTime = 0.55
    /// Fans who leave at full time, and the seconds over which they pour out.
    public var matchCrowd = 12
    public var crowdRelease = 12.0
    /// Seconds before full time from which the countdown shows.
    public var matchWarning = 20.0

    // MARK: Airport

    /// The airport is the station that appears when the city has this many; nil = no airport.
    public var airportAfterStations: Int?
    /// Extra room in the terminal.
    public var airportBonusCapacity = 6
    /// Travellers generated at the airport, relative to a normal station.
    public var airportDemandFactor = 2.0
    /// Seconds a traveller waits on one platform before giving up (taking a taxi).
    public var travellerPatience = 45.0
    /// A traveller delivered within this many seconds of landing is on time and earns `travellerBonus`.
    public var travellerOnTime = 60.0
    public var travellerBonus = 10

    public init() {}

    /// Venues in a level that has a stadium.
    public static func stadium(after stations: Int) -> VenueRules {
        var r = VenueRules()
        r.stadiumAfterStations = stations
        return r
    }

    /// Venues in a level that has an airport.
    public static func airport(after stations: Int) -> VenueRules {
        var r = VenueRules()
        r.airportAfterStations = stations
        return r
    }
}

/// One match: fans pour out of the stadium at full time.
public struct Match: Codable, Hashable, Sendable {
    public var stadium: StationID
    /// Full time: the crowd starts to leave.
    public var fullTime: Double
    public var crowd: Int
    /// Fans who have left the stadium so far.
    public var released = 0

    public init(stadium: StationID, fullTime: Double, crowd: Int) {
        self.stadium = stadium
        self.fullTime = fullTime
        self.crowd = crowd
    }

    public var isFinished: Bool { released >= crowd }
}

/// What the venues are doing. Stored in `GameState` only when the level has venues.
public struct VenueState: Codable, Hashable, Sendable {
    public var stadium: StationID?
    public var airport: StationID?
    /// Matches of the current week still to come or still emptying.
    public var matches: [Match] = []
    /// The last week whose matches were planned.
    public var plannedWeek = 0
    public var fansDelivered = 0
    public var travellersOnTime = 0
    /// Travellers who waited too long and left (they are no longer in the network).
    public var travellersGaveUp = 0

    public init() {}
}

/// Who a passenger is, when it matters.
public enum PassengerKind: String, Codable, Hashable, Sendable {
    /// Left the stadium at full time.
    case fan
    /// Landed at the airport: in a hurry.
    case traveller
}
