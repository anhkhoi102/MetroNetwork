import Foundation

/// Campaign part 2: drawbridges. On a fixed timetable every bridge over water lifts to let boats through;
/// while it is up, trains wait at the station before it. Off unless a level switches it on.
public struct BridgeRules: Codable, Hashable, Sendable {
    /// First week with lifts.
    public var fromWeek = 1
    /// Seconds from the start of that week to the first lift.
    public var firstLift = 25.0
    /// Seconds from one lift to the next, and how long the bridges stay up.
    public var interval = 40.0
    public var duration = 16.0
    /// Seconds before a lift from which the countdown shows.
    public var warning = 10.0

    public init() {}
}

/// A lift: bridges are up from `start` to `end`.
public struct BridgeLift: Hashable, Sendable {
    public var start: Double
    public var end: Double

    public func isActive(at time: Double) -> Bool { time >= start && time < end }
}

/// Campaign part 2: new districts. Once a week a whole neighbourhood opens at once, announced ahead and
/// shown on the map, so the player can have a line and trains ready. Off unless a level switches it on.
public struct DistrictRules: Codable, Hashable, Sendable {
    /// First week with a new district, then one every week.
    public var fromWeek = 2
    /// When in the week it opens (days from the week's start).
    public var opensOnDay = 1.5
    /// Stations that appear together, and the size of the area.
    public var stations = 4
    public var radius = 190.0
    /// Seconds of warning: the area is shown on the map this long before it opens.
    public var warning = 25.0

    public init() {}
}

/// A district that has been announced and not opened yet.
public struct NewDistrict: Codable, Hashable, Sendable {
    public var center: Vec2
    public var radius: Double
    public var opensAt: Double

    public init(center: Vec2, radius: Double, opensAt: Double) {
        self.center = center
        self.radius = radius
        self.opensAt = opensAt
    }
}

/// New-district bookkeeping, stored in `GameState` only when the level has new districts.
public struct DistrictState: Codable, Hashable, Sendable {
    /// Announced, opening soon.
    public var upcoming: NewDistrict?
    /// The last week whose district was announced.
    public var announcedWeek = 0
    /// Districts opened so far.
    public var opened = 0

    public init() {}
}
