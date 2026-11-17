import MetroCore

/// Player-facing wording for network events (shared by the HUD, toasts and cards).
enum EventText {
    static func icon(_ kind: NetworkEvent.Kind) -> String {
        switch kind {
        case .surge: "person.3.fill"
        case .touristGroup: "camera.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .closure: "xmark.octagon.fill"
        }
    }

    static func describe(_ event: NetworkEvent, in state: GameState, running: Bool) -> String {
        func name(_ id: StationID) -> String {
            tr("\(state.station(id)?.shape.displayName ?? "") station")
        }
        switch event.kind {
        case .surge(let s):
            return running ? tr("Crowds at \(name(s))") : tr("big crowds expected at \(name(s))")
        case let .touristGroup(s, shape, count):
            return running ? tr("A group of \(count) at \(name(s)) heads for a \(shape.displayName.lowercased())")
                : tr("a tour group arrives at \(name(s))")
        case .maintenance(let t):
            let line = state.train(t)?.lineID.flatMap { state.line($0) }.map { VisualTheme.lineName($0.colorIndex) } ?? "A"
            return running ? tr("\(line) train in maintenance") : tr("a \(line) train goes in for maintenance")
        case .closure(let s):
            return running ? tr("\(name(s)) closed") : tr("\(name(s)) closes for \(Int(event.end - event.start))s")
        }
    }
}
