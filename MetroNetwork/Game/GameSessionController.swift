import SwiftUI
import Observation
import MetroCore

/// Bridges one game session to SwiftUI: owns the engine and scene, publishes a throttled HUD snapshot,
/// and turns button presses into `GameCommand`s.
@MainActor
@Observable
final class GameSessionController {

    enum Selection: Hashable {
        case station(StationID)
        case line(LineID)
        case train(TrainID)
    }

    struct LineSlot: Hashable, Identifiable {
        let id: Int
        let colorIndex: Int
        let lineID: LineID?
        /// Not owned yet: can be bought in the depot.
        var locked = false
    }

    /// One capsule in the HUD status row.
    struct Notice: Equatable, Identifiable {
        enum Tone: Equatable { case info, warning, active }
        let id: String
        let icon: String
        let text: String
        let tone: Tone
    }

    struct HUDSnapshot: Equatable {
        var elapsedSeconds = 0
        var week = 1
        var day = 0
        var stationCount = 0
        var delivered = 0
        var score = 0
        var resources = ResourceStock()
        var crossingsFree = 0
        /// Most urgent overcrowding timer in the city (0…1).
        var worstOvercrowding = 0.0
        /// Network efficiency 0–100, nil before the first delivery.
        var efficiency: Int?
        /// Rush hour and network-event notices for the status row.
        var notices: [Notice] = []
        /// Scenario: last week, and objectives met so far.
        var weekLimit: Int?
        var objectivesMet = 0
        var objectivesTotal = 0
        var waiting = 0
        var trainCount = 0
        var slots: [LineSlot] = []
        var lineCount = 0
        var isPaused = false
        var speed: Double = 1
    }

    /// Endless (map + difficulty) or a scenario.
    let mode: SessionMode
    /// The campaign level or challenge being played, if any.
    let scenario: ScenarioDefinition?
    /// The city (for names and "play again").
    let preset: MapPreset
    /// Autosave this session (off for the debug demo, so it never overwrites a real game).
    @ObservationIgnored var persistsSession = true
    @ObservationIgnored let engine: GameEngine
    @ObservationIgnored let scene: GameScene

    private(set) var hud = HUDSnapshot()
    /// Mirrors `engine.state.revision`; views read it so they refresh after edits.
    private(set) var revision = 0
    /// Bumped on every HUD refresh while something is selected, so context cards show live trains and queues.
    private(set) var liveStamp = 0
    private(set) var selection: Selection?
    private(set) var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    /// Depot panel. `depotGrant` is set when the depot opened because a new week began.
    private(set) var isDepotOpen = false
    private(set) var depotGrant: WeeklyGrant?
    /// The depot paused the game when it opened; closing it resumes.
    @ObservationIgnored private var depotPaused = false
    /// Open the depot automatically at the start of every week (off in the debug demo).
    @ObservationIgnored var opensDepotWeekly = true

    /// Set when the session ends.
    private(set) var result: SessionResult?

    struct SessionResult: Equatable {
        let summary: SessionSummary
        /// The station that failed (nil when a scenario simply reached its time limit).
        let station: Station?
        let previousBest: Int?
        /// Stars / medals and objectives, for campaign levels and challenges.
        let scenario: ScenarioResult?
        var isNewBest: Bool { previousBest.map { summary.score > $0 } ?? (summary.score > 0) }
    }

    /// A new session, or a resumed one when `engine` is given.
    init(mode: SessionMode, engine: GameEngine? = nil) {
        self.mode = mode
        switch mode {
        case .endless(let preset, _):
            self.preset = preset
            scenario = nil
        case .scenario(let id):
            scenario = Scenarios.definition(id)
            preset = scenario?.preset ?? MapPreset.builtIn[0]
        }
        self.engine = engine ?? GameSessionManager.newSession(mode: mode)
            ?? GameSessionManager.newSession(preset: preset)
        scene = GameScene(engine: self.engine)
        scene.controller = self
        refreshHUD()
    }

    /// The same mode from the start.
    func freshCopy() -> GameSessionController { GameSessionController(mode: mode) }

    /// Next campaign level after this one, if it has been unlocked.
    var nextLevel: ScenarioDefinition? {
        guard let scenario, scenario.kind == .campaign,
              let i = CampaignManager.levels.firstIndex(where: { $0.id == scenario.id }),
              i + 1 < CampaignManager.levels.count,
              ProgressStore.shared.progress.isLevelUnlocked(i + 1) else { return nil }
        return CampaignManager.levels[i + 1]
    }

    // MARK: Saving

    /// Saves the session so it can be continued later (no-op once it has ended).
    func autosave() {
        guard persistsSession, result == nil, !engine.state.isOver else { return }
        SessionStore.save(SavedSession(mode: mode, state: engine.state))
    }

    // MARK: State → UI

    func refreshHUD() {
        let state = engine.state
        if revision != state.revision {
            revision = state.revision
        }
        validateSelection()
        if selection != nil || showsEfficiency || showsObjectives { liveStamp &+= 1 }
        var slots: [LineSlot] = state.lines
            .sorted { $0.colorIndex < $1.colorIndex }
            .map { LineSlot(id: $0.colorIndex, colorIndex: $0.colorIndex, lineID: $0.id) }
        let used = state.usedColorIndices
        let free = (0..<state.config.lineColorCount).filter { !used.contains($0) }.prefix(state.availableLineSlots)
        slots += free.map { LineSlot(id: $0, colorIndex: $0, lineID: nil) }
        slots.sort { $0.colorIndex < $1.colorIndex }
        let lockedCount = max(0, state.config.maxLines - max(state.resources.lineSlots, state.lines.count))
        let lockedColors = (0..<state.config.lineColorCount)
            .filter { c in !slots.contains { $0.colorIndex == c } }.prefix(lockedCount)
        slots += lockedColors.map { LineSlot(id: $0, colorIndex: $0, lineID: nil, locked: true) }

        let snapshot = HUDSnapshot(elapsedSeconds: Int(state.elapsed), week: state.week, day: state.dayOfWeek,
                                   stationCount: state.stations.count,
                                   delivered: state.passengersDelivered, score: state.stats.score,
                                   resources: state.resources,
                                   crossingsFree: freeCrossings(state),
                                   worstOvercrowding: state.stations.map(\.overcrowding).max() ?? 0,
                                   efficiency: state.efficiency.hasData ? Int(state.efficiency.score.rounded()) : nil,
                                   notices: Self.notices(for: state),
                                   weekLimit: state.scenario?.weekLimit,
                                   objectivesMet: engine.scenarioProgress.filter(\.met).count,
                                   objectivesTotal: state.scenario?.objectives.count ?? 0,
                                   waiting: state.stations.reduce(0) { $0 + $1.waiting.count },
                                   trainCount: state.trains.filter { !$0.isRetiring }.count,
                                   slots: slots, lineCount: state.lines.count,
                                   isPaused: engine.isPaused, speed: engine.speed)
        if snapshot != hud { hud = snapshot }
    }

    private func validateSelection() {
        switch selection {
        case .line(let id) where engine.state.line(id) == nil: select(nil)
        case .station(let id) where engine.state.station(id) == nil: select(nil)
        case .train(let id) where engine.state.train(id)?.isRetiring ?? true: select(nil)
        default: break
        }
    }

    var selectedStation: (station: Station, lines: [MetroLine])? {
        _ = revision
        _ = liveStamp
        guard case .station(let id) = selection, let s = engine.state.station(id) else { return nil }
        return (s, engine.state.lines(serving: id))
    }

    var selectedLine: (line: MetroLine, stations: [Station], trains: Int)? {
        _ = revision
        _ = liveStamp
        guard case .line(let id) = selection, let line = engine.state.line(id) else { return nil }
        return (line, line.stations.compactMap { engine.state.station($0) }, engine.state.trains(on: id).count)
    }

    var selectedTrain: (train: Train, line: MetroLine, nextStop: Station?)? {
        _ = revision
        _ = liveStamp
        guard case .train(let id) = selection, let train = engine.state.train(id),
              let line = train.lineID.flatMap({ engine.state.line($0) }) else { return nil }
        return (train, line, engine.state.station(train.to))
    }

    // MARK: Selection

    func select(_ newSelection: Selection?) {
        if newSelection != nil { showsEfficiency = false; showsObjectives = false }
        selection = newSelection
        scene.applySelection(newSelection)
    }

    func clearSelection() {
        if selection != nil { select(nil) }
    }

    // MARK: Commands

    @discardableResult
    func perform(_ command: GameCommand) -> Bool {
        let result = engine.apply(command)
        refreshHUD()
        switch result {
        case .success:
            return true
        case .failure(.noChange):
            return false
        case .failure(let error):
            showToast(error.message)
            return false
        }
    }

    func deleteLine(_ id: LineID) { perform(.deleteLine(id)) }
    func remove(_ station: StationID, from line: LineID) { perform(.removeStation(line, station: station)) }
    func setColor(_ colorIndex: Int, for line: LineID) { perform(.setLineColor(line, colorIndex: colorIndex)) }
    func openLoop(_ line: LineID) { perform(.openLoop(line)) }
    func setExpress(_ line: LineID, _ express: Bool) { perform(.setExpress(line, express)) }
    func addTrain(to line: LineID) { perform(.addTrain(line)) }
    func removeTrain(from line: LineID) { perform(.removeTrain(line)) }

    /// Withdraws the selected train specifically (it finishes its trip, lets everyone off, then leaves).
    func withdraw(_ train: TrainID) {
        let line = engine.state.train(train)?.lineID
        if perform(.withdrawTrain(train)), let line { select(.line(line)) }
    }

    func deleteSelectedLine() {
        if case .line(let id) = selection { deleteLine(id) }
    }

    /// Selects the n-th visible line slot (keyboard 1–7).
    func selectLineSlot(_ index: Int) {
        let lines = hud.slots.compactMap(\.lineID)
        guard lines.indices.contains(index) else { return }
        select(.line(lines[index]))
    }

    /// Free tunnels, recomputed only when the network changes (it walks every segment against the water).
    @ObservationIgnored private var crossingsCache: (revision: Int, owned: Int, free: Int)?

    private func freeCrossings(_ state: GameState) -> Int {
        if let c = crossingsCache, c.revision == state.revision, c.owned == state.resources.crossings { return c.free }
        let free = ResourceManager.crossingsAvailable(in: state)
        crossingsCache = (state.revision, state.resources.crossings, free)
        return free
    }

    // MARK: Notices

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Rush hours (running, or next this week) and network events (announced or running).
    static func notices(for state: GameState) -> [Notice] {
        var result: [Notice] = []
        let now = state.elapsed
        if let rush = state.activeRushHour {
            let left = Int((rush.end - now).rounded(.up))
            result.append(Notice(id: "rush", icon: "clock.badge.exclamationmark.fill",
                                 text: tr("Rush hour · \(rush.flow == .toCentre ? "homes → centre" : "centre → homes") · \(left)s"),
                                 tone: .active))
        } else if let next = state.rushHours.filter({ $0.start > now }).min(by: { $0.start < $1.start }) {
            let day = Int((next.start / (state.config.weekLength / 7)).rounded(.down)) % 7
            result.append(Notice(id: "rush", icon: "clock",
                                 text: tr("Rush hour \(dayNames[day]) · \(next.flow == .toCentre ? "morning" : "evening")"),
                                 tone: .info))
        }
        for event in state.events {
            let running = event.isActive(at: now)
            let seconds = Int(((running ? event.end : event.start) - now).rounded(.up))
            let text = EventText.describe(event, in: state, running: running)
            result.append(Notice(id: "event-\(event.id)", icon: EventText.icon(event.kind),
                                 text: running ? "\(text) · \(seconds)s" : tr("In \(seconds)s: \(text)"),
                                 tone: running ? .active : .warning))
        }
        return result
    }

    // MARK: Efficiency card

    private(set) var showsEfficiency = false

    func toggleEfficiency() {
        if !showsEfficiency { clearSelection(); showsObjectives = false }
        showsEfficiency.toggle()
    }

    var efficiencyDetails: (efficiency: NetworkEfficiency, factors: NetworkEfficiency.Factors)? {
        _ = liveStamp
        let e = engine.state.efficiency
        guard e.hasData else { return nil }
        return (e, EfficiencyManager.factors(e, config: engine.state.config))
    }

    // MARK: Resources

    func buy(_ item: Purchase) { perform(.purchase(item)) }
    func attachCarriage(_ train: TrainID) { perform(.attachCarriage(train)) }
    func detachCarriage(_ train: TrainID) { perform(.detachCarriage(train)) }
    func fitMotor(_ train: TrainID) { perform(.fitMotor(train)) }
    func removeMotor(_ train: TrainID) { perform(.removeMotor(train)) }
    func expand(_ station: StationID) { perform(.expandStation(station)) }

    func openDepot(grant: WeeklyGrant? = nil) {
        guard result == nil else { return }
        depotGrant = grant
        if !isDepotOpen, !engine.isPaused {
            engine.isPaused = true
            depotPaused = true
        }
        isDepotOpen = true
        refreshHUD()
    }

    func closeDepot() {
        guard isDepotOpen else { return }
        isDepotOpen = false
        depotGrant = nil
        if depotPaused {
            engine.isPaused = false
            depotPaused = false
        }
        refreshHUD()
    }

    func toggleDepot() { isDepotOpen ? closeDepot() : openDepot() }

    // MARK: Game events (from the scene)

    // MARK: Objectives card

    private(set) var showsObjectives = false

    func toggleObjectives() {
        if !showsObjectives { clearSelection(); showsEfficiency = false }
        showsObjectives.toggle()
    }

    var objectives: [ObjectiveProgress] {
        _ = liveStamp
        return engine.scenarioProgress
    }

    func weekStarted(_ grant: WeeklyGrant) {
        autosave()
        if opensDepotWeekly { openDepot(grant: grant) } else { showToast(tr("Week \(grant.week): +\(grant.total) credits")) }
    }

    /// Announcements show in the HUD status row (with a countdown) and as a marker on the map.
    func networkEventAnnounced(_ event: NetworkEvent) {
        refreshHUD()
    }

    func networkEventStarted(_ event: NetworkEvent) {
        if case .touristGroup = event.kind {
            showToast(EventText.describe(event, in: engine.state, running: true))
        }
    }

    func stationStartedOvercrowding(_ id: StationID) {
        guard let station = engine.state.station(id) else { return }
        showToast(tr("\(station.shape.displayName) station is overcrowded!"))
    }

    func gameEnded(_ info: GameOverInfo) {
        finish(failedStation: engine.state.station(info.station))
    }

    /// A scenario reached its time limit.
    func scenarioFinished() {
        finish(failedStation: nil)
    }

    /// Records the result in the player's progress and shows the summary. The saved session is removed.
    private func finish(failedStation: Station?) {
        guard result == nil else { return }
        let summary = engine.summary
        let scenarioResult = engine.scenarioResult
        var previous: Int?
        if persistsSession {
            let store = ProgressStore.shared
            switch mode {
            case let .endless(preset, difficulty):
                previous = store.progress.bestEndless(map: preset.id, difficulty: difficulty)?.bestScore
                store.update { $0.recordEndless(summary, map: preset.id, difficulty: difficulty) }
            case .scenario(let id):
                let records = scenario?.kind == .challenge ? store.progress.challenges : store.progress.campaign
                previous = records[id]?.bestScore
                if let scenarioResult { store.update { $0.recordScenario(scenarioResult, summary: summary) } }
            }
            SessionStore.clear()
        }
        isDepotOpen = false
        showsObjectives = false
        showsEfficiency = false
        clearSelection()
        result = SessionResult(summary: summary, station: failedStation, previousBest: previous, scenario: scenarioResult)
        refreshHUD()
    }

    // MARK: Time and camera

    func togglePause() {
        guard result == nil else { return }
        if isDepotOpen { closeDepot(); return }
        engine.isPaused.toggle()
        refreshHUD()
    }

    func cycleSpeed() {
        let count = engine.state.config.speedOptions.count
        engine.setSpeedIndex((engine.speedIndex + 1) % max(count, 1))
        refreshHUD()
    }

    func fitCity() { scene.fitCity(animated: true) }
    func zoomIn() { scene.zoom(by: 1 / 1.25) }
    func zoomOut() { scene.zoom(by: 1.25) }

    /// Escape: cancel a drag first, then close the depot, then clear the selection.
    func cancelOrDeselect() {
        if scene.input.isEditing { scene.input.cancel() } else if isDepotOpen { closeDepot() } else { clearSelection() }
    }

    // MARK: Feedback

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
