import Foundation

/// Route planning for passengers. Rebuilt only when the network changes (lines edited, stations added),
/// never per frame or per passenger.
///
/// Passengers travel to *any* station of a shape, so for every shape present we run one multi-source
/// Dijkstra backwards from all stations of that shape. Nodes are stations and directional "platforms":
/// `(station, line, direction)` = "on a train of `line` at `station`, about to depart in `direction`".
///
/// Edges (forward):
/// - board: station → platform, cost = boarding cost + expected wait (half the line's headway, so a line
///   with more trains is more attractive and a line with no trains is unusable); much cheaper at an
///   interchange station
/// - alight: platform → station, cost 0
/// - ride: platform → platform at the next *stop* (`StopRules`: closed stations and stations an express
///   skips are run through), cost = estimated travel + dwell time; at the end of an open line the train
///   turns round, so riding into a terminal leads to the reverse platform.
public struct NetworkGraph: Sendable {

    public struct Platform: Hashable, Sendable {
        public let station: StationID
        public let line: LineID
        public let direction: Int
    }

    /// Cost tolerance (seconds) when comparing equally good options.
    static let tolerance = 0.5

    /// `GameState.revision` this graph was built from.
    public let revision: Int
    private let stationIndex: [StationID: Int]
    private let platformIndex: [Platform: Int]
    private let platformsAtStation: [[Int]]
    private let rideNext: [Int]
    private let rideCost: [Double]
    /// Per shape: cost-to-go from each station node (passenger waiting there).
    private var stationCost: [StationShape: [Double]] = [:]
    /// Per shape: cost-to-go when staying on board from each platform (ride one stop, then continue).
    private var rideOnCost: [StationShape: [Double]] = [:]

    public init(state: GameState) {
        revision = state.revision
        let config = state.config
        var stationIndex: [StationID: Int] = [:]
        for (i, s) in state.stations.enumerated() { stationIndex[s.id] = i }
        let positions = state.stationPositions

        // Platforms and ride edges.
        var platformIndex: [Platform: Int] = [:]
        var platforms: [Platform] = []
        func platform(_ p: Platform) -> Int {
            if let i = platformIndex[p] { return i }
            platformIndex[p] = platforms.count
            platforms.append(p)
            return platforms.count - 1
        }
        var rides: [(from: Int, to: Int, cost: Double)] = []
        var boardCostOfPlatform: [Double] = []
        for line in state.lines {
            let s = line.stations
            let n = s.count
            guard n >= 2 else { continue }
            let stop = StopRules.stopMask(for: line, in: state)
            guard stop.filter({ $0 }).count >= 2 else { continue }
            func segment(_ a: Int, _ b: Int) -> Double {
                positions[s[a]].flatMap { p in positions[s[b]].map { RouteGeometry.octilinearLength(p, $0) } } ?? 0
            }
            let firstPlatform = platforms.count
            for i in 0..<n where stop[i] {
                for d in [1, -1] {
                    guard Self.nextIndex(i, direction: d, count: n, loop: line.isLoop) != nil else { continue }
                    // Ride on, through any stations the train runs through, to the next stop.
                    var k = i, dir = d, length = 0.0, reversals = 0, steps = 0
                    var target: (index: Int, direction: Int)?
                    while steps < 2 * n + 2 {
                        steps += 1
                        guard let j = Self.nextIndex(k, direction: dir, count: n, loop: line.isLoop) else { break }
                        length += segment(k, j)
                        // Departing direction at j (reverses at the end of an open line).
                        let dNext = Self.nextIndex(j, direction: dir, count: n, loop: line.isLoop) == nil ? -dir : dir
                        if stop[j] { target = (j, dNext); break }
                        if dNext != dir { reversals += 1 }
                        k = j
                        dir = dNext
                    }
                    guard let target else { continue }
                    let from = platform(Platform(station: s[i], line: line.id, direction: d))
                    let to = platform(Platform(station: s[target.index], line: line.id, direction: target.direction))
                    let time = Self.travelTime(length: length, config: config)
                        + Double(reversals) * max(config.trainMaxSpeed, 1) / max(config.trainAcceleration, 1)
                    rides.append((from, to, time))
                }
            }
            // Headway: one full cycle of the line divided by its trains in service.
            let lineRides = rides.filter { $0.from >= firstPlatform }
            let cycle = lineRides.reduce(0) { $0 + $1.cost } / (line.isLoop ? 2 : 1)
            let trains = state.trains.filter { $0.lineID == line.id && $0.maintenanceUntil == nil }.count
            let wait = trains > 0 ? cycle / Double(trains) / 2 : .infinity
            while boardCostOfPlatform.count < platforms.count { boardCostOfPlatform.append(0) }
            for pi in firstPlatform..<platforms.count {
                let station = platforms[pi].station
                let factor = state.station(station)?.special == .interchange ? config.interchangeTransferFactor : 1
                boardCostOfPlatform[pi] = (config.boardingCost + wait) * factor
            }
        }
        while boardCostOfPlatform.count < platforms.count { boardCostOfPlatform.append(0) }
        var rideNext = Array(repeating: -1, count: platforms.count)
        var rideCost = Array(repeating: Double.infinity, count: platforms.count)
        for r in rides {
            rideNext[r.from] = r.to
            rideCost[r.from] = r.cost
        }
        var platformsAtStation = Array(repeating: [Int](), count: state.stations.count)
        for (i, p) in platforms.enumerated() {
            if let s = stationIndex[p.station] { platformsAtStation[s].append(i) }
        }

        self.stationIndex = stationIndex
        self.platformIndex = platformIndex
        self.platformsAtStation = platformsAtStation
        self.rideNext = rideNext
        self.rideCost = rideCost

        // Reverse adjacency: node -> [(predecessor, edge cost)]. Stations are nodes 0..<S, platforms S..<S+P.
        let stationCount = state.stations.count
        var reverse = Array(repeating: [(Int, Double)](), count: stationCount + platforms.count)
        for (pi, p) in platforms.enumerated() {
            guard let si = stationIndex[p.station] else { continue }
            let pn = stationCount + pi
            reverse[si].append((pn, 0))                                   // alight: p -> s
            reverse[pn].append((si, boardCostOfPlatform[pi]))             // board:  s -> p
            if rideNext[pi] >= 0 { reverse[stationCount + rideNext[pi]].append((pn, rideCost[pi])) }
        }

        for shape in Set(state.stations.map(\.shape)) {
            let sources = state.stations.indices.filter { state.stations[$0].shape == shape }
            let dist = Self.dijkstra(reverse: reverse, sources: sources)
            stationCost[shape] = Array(dist[0..<stationCount])
            rideOnCost[shape] = (0..<platforms.count).map { pi in
                rideNext[pi] >= 0 ? rideCost[pi] + dist[stationCount + rideNext[pi]] : .infinity
            }
        }
    }

    // MARK: Queries

    /// Estimated seconds for a passenger waiting at `station` to reach `shape` (infinity = unreachable).
    public func cost(from station: StationID, to shape: StationShape) -> Double {
        guard let s = stationIndex[station] else { return .infinity }
        return stationCost[shape]?[s] ?? .infinity
    }

    /// Estimated seconds to reach `shape` by staying on a train of `line` departing `station` in `direction`.
    public func rideOnCost(at station: StationID, line: LineID, direction: Int, to shape: StationShape) -> Double {
        guard let p = platformIndex[Platform(station: station, line: line, direction: direction)] else { return .infinity }
        return rideOnCost[shape]?[p] ?? .infinity
    }

    /// Should a passenger waiting at `station` for `shape` board this train? Only if it is (one of) the best options.
    public func shouldBoard(at station: StationID, line: LineID, direction: Int, to shape: StationShape) -> Bool {
        let ride = rideOnCost(at: station, line: line, direction: direction, to: shape)
        guard ride.isFinite, let s = stationIndex[station], let costs = rideOnCost[shape] else { return false }
        let best = platformsAtStation[s].reduce(Double.infinity) { min($0, costs[$1]) }
        return ride <= best + Self.tolerance
    }

    /// Should a passenger on board stay on when the train departs `station`? (Otherwise they get off here to
    /// change trains, or to wait if their destination can't be reached from this train.)
    public func shouldStayOn(at station: StationID, line: LineID, direction: Int, to shape: StationShape) -> Bool {
        let stay = rideOnCost(at: station, line: line, direction: direction, to: shape)
        guard stay.isFinite else { return false }
        return stay <= cost(from: station, to: shape) + Self.tolerance
    }

    // MARK: Helpers

    /// Index of the next stop from `i` in `direction`, or nil past the end of an open line.
    static func nextIndex(_ i: Int, direction: Int, count n: Int, loop: Bool) -> Int? {
        let j = i + direction
        if loop { return (j % n + n) % n }
        return (0..<n).contains(j) ? j : nil
    }

    /// Seconds to travel one segment: cruise time plus acceleration/braking overhead plus the stop.
    static func travelTime(length: Double, config: GameConfiguration) -> Double {
        let v = max(config.trainMaxSpeed, 1)
        return length / v + v / max(config.trainAcceleration, 1) + config.dwellBase
    }

    private static func dijkstra(reverse: [[(Int, Double)]], sources: [Int]) -> [Double] {
        var dist = Array(repeating: Double.infinity, count: reverse.count)
        var heap = MinHeap()
        for s in sources {
            dist[s] = 0
            heap.push(0, s)
        }
        while let (d, v) = heap.pop() {
            guard d <= dist[v] else { continue }
            for (u, c) in reverse[v] where d + c < dist[u] {
                dist[u] = d + c
                heap.push(d + c, u)
            }
        }
        return dist
    }
}

/// Minimal binary heap of (cost, node), ties broken by node index for determinism.
private struct MinHeap {
    private var items: [(Double, Int)] = []

    private static func less(_ a: (Double, Int), _ b: (Double, Int)) -> Bool {
        a.0 < b.0 || (a.0 == b.0 && a.1 < b.1)
    }

    mutating func push(_ cost: Double, _ node: Int) {
        items.append((cost, node))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard Self.less(items[i], items[parent]) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, Self.less(items[l], items[m]) { m = l }
                if r < items.count, Self.less(items[r], items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}
