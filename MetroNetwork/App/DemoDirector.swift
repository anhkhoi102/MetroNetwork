#if DEBUG
import Foundation
import MetroCore

/// Debug-only scripted session for screenshots and visual checks without input:
///   MetroNetwork -MetroDemo 0        (preset index; add -MetroDemoSelect to select the first line,
///                                     -MetroDemoDepot to let the weekly depot open,
///                                     -MetroDemoIdle to build nothing and reach game over,
///                                     -MetroDemoBridge to build the third line across water,
///                                     -MetroDemoSelectTrain to open a train card,
///                                     -MetroDemoAuto to let the auto player run the network
///                                     (with -MetroDemoSelectSpecial: open the first special station's card,
///                                      -MetroDemoExpress: make a line express and open its card,
///                                      -MetroDemoEfficiency: open the efficiency breakdown),
///                                     -MetroDemoSpeed N for an N× speed instead of 2×,
///                                     -MetroDemoTheme <id> to force a map theme, -MetroDemoZoomIn)
/// Builds three lines as the city grows and runs at 2× speed. Compiled out of Release builds.
@MainActor
enum DemoDirector {
    static var presetIndex: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MetroDemo") else { return nil }
        return args.indices.contains(i + 1) ? Int(args[i + 1]) ?? 0 : 0
    }

    /// The closest pair of stations whose connection has to cross water.
    private static func waterPair(_ state: GameState) -> (StationID, StationID)? {
        let positions = state.stationPositions
        var best: (StationID, StationID, Double)?
        for a in state.stations {
            for b in state.stations where a.id < b.id {
                guard RouteGeometry.terrain(SegmentKey(a.id, b.id), positions: positions, map: state.map) == .water else { continue }
                let d = a.position.distance(to: b.position)
                if best == nil || d < best!.2 { best = (a.id, b.id, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// `-MetroDemoSpeed N` replaces the speed choices (the demo picks the second one, so use e.g. 4).
    static func adjust(_ c: inout GameConfiguration) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-MetroDemoSpeed"), args.indices.contains(i + 1), let v = Double(args[i + 1]) {
            c.speedOptions = [1, v]
        }
    }

    /// `-MetroDemoTheme <id>` forces a map theme for screenshots (ignores unlocks).
    static var themeID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MetroDemoTheme"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// `-MetroDemoScenario <id>` plays a campaign level or challenge instead of Endless (use with -MetroDemoAuto).
    static var scenarioID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MetroDemoScenario"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static func run(_ controller: GameSessionController) {
        controller.cycleSpeed()
        let arguments = ProcessInfo.processInfo.arguments
        // -MetroDemoZoomIn: zoom in after a moment, so off-screen alerts can be seen.
        if arguments.contains("-MetroDemoZoomIn") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                controller.scene.zoom(by: 0.4)
            }
        }
        // Keep running unattended, unless the depot itself is being checked (-MetroDemoDepot).
        controller.opensDepotWeekly = ProcessInfo.processInfo.arguments.contains("-MetroDemoDepot")
        let args = ProcessInfo.processInfo.arguments
        let selectLine = args.contains("-MetroDemoSelect")
        // -MetroDemoIdle: build nothing, so a station overcrowds and the game-over screen appears quickly.
        guard !ProcessInfo.processInfo.arguments.contains("-MetroDemoIdle") else { return }
        // -MetroDemoAuto: the core's casual auto player builds and manages the network.
        if args.contains("-MetroDemoAuto") {
            Task { @MainActor in
                var player = AutoPlayer()
                var shownExpress = false, shownEfficiency = false
                while controller.result == nil {
                    let state = controller.engine.state
                    if args.contains("-MetroDemoExpress"), !shownExpress,
                       let line = state.lines.first(where: { l in
                           let stops = StopRules.expressStops(of: l, in: state).count
                           return stops >= 2 && stops < l.stations.count
                       }) {
                        shownExpress = true
                        controller.setExpress(line.id, true)
                        controller.select(.line(line.id))
                    }
                    if args.contains("-MetroDemoEfficiency"), !shownEfficiency, state.efficiency.hasData,
                       state.elapsed > 60 {
                        shownEfficiency = true
                        controller.toggleEfficiency()
                    }
                    if !controller.engine.isPaused { player.act(on: controller.engine) }
                    if args.contains("-MetroDemoSelectSpecial"), controller.selection == nil,
                       let special = controller.engine.state.stations.first(where: { $0.special != nil }) {
                        controller.select(.station(special.id))
                    }
                    controller.refreshHUD()
                    try? await Task.sleep(for: .seconds(0.25))
                }
            }
            return
        }
        Task { @MainActor in
            @MainActor func ids() -> [StationID] { controller.engine.state.stations.map(\.id) }
            /// Waits (polling) until the city has at least `n` stations.
            @MainActor func waitFor(_ n: Int) async {
                while ids().count < n { try? await Task.sleep(for: .seconds(0.5)) }
            }
            try? await Task.sleep(for: .seconds(0.5))
            controller.perform(.createLine(stations: Array(ids().prefix(3)), colorIndex: nil, isLoop: false))
            await waitFor(6)
            let s = ids()
            controller.perform(.createLine(stations: [s[0]] + Array(s[3..<6]), colorIndex: nil, isLoop: false))
            if let first = controller.engine.state.lines.first { controller.perform(.addTrain(first.id)) }
            // Riverside first has stations on both banks at around 12 stations.
            await waitFor(args.contains("-MetroDemoBridge") ? 12 : 9)
            let t = ids()
            if args.contains("-MetroDemoBridge"), let pair = waterPair(controller.engine.state) {
                controller.perform(.createLine(stations: [pair.0, pair.1], colorIndex: nil, isLoop: false))
            } else {
                controller.perform(.createLine(stations: [t[1]] + Array(t[6..<9]), colorIndex: nil, isLoop: false))
            }
            if selectLine, let first = controller.engine.state.lines.first { controller.select(.line(first.id)) }
            if args.contains("-MetroDemoSelectTrain"), let train = controller.engine.state.trains.first {
                controller.select(.train(train.id))
            }
        }
    }
}
#endif
