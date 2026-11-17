import Foundation

/// Used by the balance tests and the debug demo. A deliberately simple "casual player": connects every new station to the nearest line end, puts spare
/// trains where queues are longest and spends credits on the obvious fix. Not a good player — a yardstick for
/// how forgiving the early game is. Deterministic, so results can be compared between balance changes.
public struct AutoPlayer {
    public var thinkInterval = 2.0
    private var nextThink = 0.0

    public init() {}

    public mutating func act(on engine: GameEngine) {
        guard engine.state.elapsed >= nextThink else { return }
        nextThink = engine.state.elapsed + thinkInterval
        connectStations(engine)
        spend(engine)
        placeTrains(engine)
        useExpansions(engine)
    }

    private func connectStations(_ engine: GameEngine) {
        let state = engine.state
        let served = Set(state.lines.flatMap(\.stations))
        for station in state.stations where !served.contains(station.id) {
            let s = engine.state
            // Line ends, nearest first.
            var ends: [(LineID, LineEnd, Double)] = []
            for line in s.lines where !line.isLoop {
                for (end, id) in [(LineEnd.start, line.stations.first!), (.end, line.stations.last!)] {
                    if let p = s.station(id)?.position { ends.append((line.id, end, p.distance(to: station.position))) }
                }
            }
            ends.sort { $0.2 < $1.2 }
            // Prefer a new line while one is free and the nearest end is far away.
            if s.availableLineSlots > 0, (ends.first?.2 ?? .infinity) > 450 || s.lines.isEmpty {
                let others = s.stations.filter { $0.id != station.id }
                    .sorted { $0.position.distance(to: station.position) < $1.position.distance(to: station.position) }
                if let partner = others.first,
                   case .success = engine.apply(.createLine(stations: [station.id, partner.id], colorIndex: nil, isLoop: false)) {
                    continue
                }
            }
            var connected = false
            for (line, end, _) in ends.prefix(4) {
                switch engine.apply(.extendLine(line, end: end, station: station.id)) {
                case .success: connected = true
                case .failure(.noCrossingsLeft):
                    if case .success = engine.apply(.purchase(.crossings)),
                       case .success = engine.apply(.extendLine(line, end: end, station: station.id)) { connected = true }
                default: break
                }
                if connected { break }
            }
        }
    }

    private func spend(_ engine: GameEngine) {
        let s = engine.state
        let crowded = s.stations.contains { $0.overcrowding > 0.25 }
        if crowded, s.resources.expansions == 0 { engine.apply(.purchase(.expansion)) }
        let unserved = s.stations.count - Set(s.lines.flatMap(\.stations)).count
        if unserved >= 2, s.availableLineSlots == 0 { engine.apply(.purchase(.line)) }
        if s.resources.locomotives == 0 { engine.apply(.purchase(.locomotive)) }
        if engine.state.resources.credits >= engine.state.config.priceCarriage + 2 {
            engine.apply(.purchase(.carriage))
        }
    }

    private func placeTrains(_ engine: GameEngine) {
        let s = engine.state
        func load(_ line: MetroLine) -> Double {
            let waiting = line.stations.compactMap { s.station($0)?.waiting.count }.reduce(0, +)
            return Double(waiting) / Double(max(1, s.trains(on: line.id).count))
        }
        for line in s.lines.sorted(by: { load($0) > load($1) }) where engine.state.resources.locomotives > 0 {
            engine.apply(.addTrain(line.id))
        }
        if engine.state.resources.carriages > 0,
           let busiest = engine.state.trains.filter({ !$0.isRetiring && $0.carriages < s.config.maxCarriagesPerTrain })
            .max(by: { $0.passengers.count < $1.passengers.count }) {
            engine.apply(.attachCarriage(busiest.id))
        }
    }

    private func useExpansions(_ engine: GameEngine) {
        guard engine.state.resources.expansions > 0,
              let worst = engine.state.stations.filter({ $0.expansions < engine.state.config.maxExpansionsPerStation })
                .max(by: { $0.overcrowding < $1.overcrowding }), worst.overcrowding > 0 else { return }
        engine.apply(.expandStation(worst.id))
    }
}

