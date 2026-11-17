import SpriteKit
import MetroCore

/// Renders a `GameEngine` and ticks it every frame. Holds no gameplay rules of its own.
@MainActor
final class GameScene: SKScene {
    let engine: GameEngine
    weak var controller: GameSessionController?

    let cameraController: CameraController
    let routeRenderer: RouteRenderer
    let stationRenderer = StationRenderer()
    let trainRenderer = TrainRenderer()
    private let passengerRenderer = PassengerRenderer()
    private let effects = VisualEffectsManager()
    private let draftRenderer = DraftRenderer()
    private let alertRenderer = AlertRenderer()
    private(set) lazy var input = InputController(scene: self)

    private var lastUpdateTime: TimeInterval?
    private var drawnRevision = -1
    private var hudClock: TimeInterval = 0
    private var saveClock: TimeInterval = 0
    private var draft: RouteEditor?

    init(engine: GameEngine) {
        self.engine = engine
        cameraController = CameraController(mapSize: engine.state.map.size)
        routeRenderer = RouteRenderer(map: engine.state.map)
        super.init(size: CGSize(width: 1024, height: 768))
        scaleMode = .resizeFill
        backgroundColor = VisualTheme.outside.sk

        addChild(cameraController.camera)
        camera = cameraController.camera
        cameraController.camera.addChild(alertRenderer.layer)

        let map = MapRenderer.makeNode(for: engine.state.map)
        map.zPosition = 0
        addChild(map)
        routeRenderer.layer.zPosition = 10
        addChild(routeRenderer.layer)
        draftRenderer.node.zPosition = 15
        addChild(draftRenderer.node)
        stationRenderer.layer.zPosition = 20
        addChild(stationRenderer.layer)
        passengerRenderer.layer.zPosition = 21
        addChild(passengerRenderer.layer)
        // Trains run over stations, like real ones through a platform.
        trainRenderer.layer.zPosition = 24
        addChild(trainRenderer.layer)
        effects.layer.zPosition = 30
        addChild(effects.layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        cameraController.viewSize = size
        if !cameraController.userMoved, size.width > 1 { fitCity(animated: false, readable: true) }
        syncState(spawned: [])
    }

    override func didChangeSize(_ oldSize: CGSize) {
        cameraController.viewSize = size
        // Until the player takes control of the camera, keep the city framed (window resizes, rotation).
        if !cameraController.userMoved, size.width > 1, view != nil { fitCity(animated: false, readable: true) }
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime
        engine.update(realDelta: delta)

        // Lines and stations only change on edits and spawns; trains and queues change every frame.
        let events = engine.drainEvents()
        effects.advance(delta)
        var spawned = Set<StationID>()
        var networkEvent = false
        var newLines: [LineID] = []
        for event in events {
            switch event {
            case .stationSpawned(let id):
                spawned.insert(id); networkEvent = true
                if engine.state.elapsed > 1 { Feedback.play(.station) }
            case .lineCreated(let id):
                networkEvent = true
                Feedback.play(.line)
                newLines.append(id)
            case .lineDeleted:
                networkEvent = true
                Feedback.play(.remove)
            case .lineChanged, .trainAdded, .trainRemoved: networkEvent = true
            case .passengerDelivered(let id):
                if let p = engine.state.station(id)?.position { effects.passengerDelivered(at: id, position: p) }
                Feedback.play(.deliver)
            case .weekStarted(let grant): controller?.weekStarted(grant); networkEvent = true; Feedback.play(.week)
            case .stationOvercrowding(let id): controller?.stationStartedOvercrowding(id); Feedback.play(.warning)
            case .networkEventAnnounced(let e):
                controller?.networkEventAnnounced(e); networkEvent = true
                Feedback.play(.event)
            case .networkEventStarted(let e): controller?.networkEventStarted(e); networkEvent = true
            case .networkEventEnded: networkEvent = true
            case let .passengersBoarded(train, station, count):
                if let from = engine.state.station(station)?.position, let to = trainRenderer.positions[train] {
                    effects.passengersMoved(from: queueAnchor(from), to: to, count: count)
                }
                trainRenderer.bump(train)
            case let .passengersAlighted(train, station, count):
                if let to = engine.state.station(station)?.position, let from = trainRenderer.positions[train] {
                    effects.passengersMoved(from: from, to: queueAnchor(to), count: count)
                }
                trainRenderer.bump(train)
            case let .pointsScored(station, points):
                if let p = engine.state.station(station)?.position { effects.pointsScored(points, at: station, position: p) }
            case .scenarioFinished:
                controller?.scenarioFinished()
                Feedback.play(engine.scenarioResult?.passed == true ? .complete : .gameover)
            case .purchased, .stationExpanded, .trainUpgraded:
                networkEvent = true
                Feedback.play(.purchase)
            case .gameOver(let info):
                stationRenderer.markFailed(info.station)
                if let p = engine.state.station(info.station)?.position {
                    // Frame the failed station (zooming in if needed, never further out).
                    let around = CGRect(x: p.x - 420, y: p.y - 260, width: 840, height: 520)
                    cameraController.fit(around, animated: true, maxScale: cameraController.scale)
                }
                controller?.gameEnded(info)
                Feedback.play(.gameover)
            default: break
            }
        }
        if networkEvent || engine.state.revision != drawnRevision {
            syncState(spawned: spawned)
        }
        for id in newLines { routeRenderer.flash(id) }       // after sync, so the line's node exists
        passengerRenderer.setCameraScale(cameraController.scale)
        effects.cameraScale = cameraController.scale
        alertRenderer.update(stations: engine.state.isOver ? [] : engine.state.stations, center: cameraController.camera.position,
                             scale: cameraController.scale, viewSize: size)
        trainRenderer.setCameraScale(cameraController.scale)
        passengerRenderer.sync(engine.state.stations)
        stationRenderer.updateCongestion(engine.state.stations)
        stationRenderer.updateEvents(engine.state)
        trainRenderer.sync(state: engine.state, geometry: routeRenderer.geometry, dt: delta)

        // Autosave every 20 s of real time, so a crash loses little.
        saveClock += delta
        if saveClock >= 20 {
            saveClock = 0
            controller?.autosave()
        }

        // Music follows the game: busier in rush hour, quieter while paused or over.
        AudioManager.shared.setMusicIntensity(engine.state.isOver ? 0 : engine.state.activeRushHour != nil ? 2 : 1)
        AudioManager.shared.setMusicDucked(engine.isPaused || engine.state.isOver)

        hudClock += delta
        if hudClock >= 0.25 || networkEvent {
            hudClock = 0
            controller?.refreshHUD()
        }
    }

    // MARK: Rendering

    /// Where a station's waiting passengers are drawn (just right of the station).
    private func queueAnchor(_ station: Vec2) -> Vec2 {
        Vec2(station.x + Double(VisualTheme.stationRadius) + 10, station.y)
    }

    private func syncState(spawned: Set<StationID>) {
        let state = engine.state
        stationRenderer.sync(state.stations, animate: spawned)
        routeRenderer.sync(lines: state.lines, positions: state.stationPositions, draft: draft?.draftLine)
        drawnRevision = state.revision
    }

    func showDraft(_ editor: RouteEditor, pointer: Vec2, hovered: StationID?) {
        let positions = engine.state.stationPositions
        if editor != draft {
            draft = editor
            routeRenderer.sync(lines: engine.state.lines, positions: positions, draft: editor.draftLine)
        }
        var anchors: [Vec2] = []
        if let anchor = editor.tailAnchor, let p = positions[anchor] {
            anchors = [p]
        } else if case .insert(let id, let segment) = editor.mode, editor.insertCandidate == nil,
                  let line = engine.state.line(id), segment < line.segments.count {
            let (a, b) = line.segments[segment]
            anchors = [a, b].compactMap { positions[$0] }
        }
        draftRenderer.show(anchors: anchors, pointer: pointer, colorIndex: editor.colorIndex)
        stationRenderer.setHighlighted(hovered)
    }

    func clearDraft() {
        draft = nil
        draftRenderer.hide()
        stationRenderer.setHighlighted(nil)
        routeRenderer.sync(lines: engine.state.lines, positions: engine.state.stationPositions, draft: nil)
    }

    func applySelection(_ selection: GameSessionController.Selection?) {
        switch selection {
        case .station(let id):
            stationRenderer.setSelected(id)
            routeRenderer.setSelected(nil)
            trainRenderer.setSelected(nil)
        case .line(let id):
            stationRenderer.setSelected(nil)
            routeRenderer.setSelected(id)
            trainRenderer.setSelected(nil)
        case .train(let id):
            stationRenderer.setSelected(nil)
            routeRenderer.setSelected(engine.state.train(id)?.lineID)
            trainRenderer.setSelected(id)
        case nil:
            stationRenderer.setSelected(nil)
            routeRenderer.setSelected(nil)
            trainRenderer.setSelected(nil)
        }
    }

    // MARK: Camera

    func worldPoint(fromView point: CGPoint) -> CGPoint {
        convertPoint(fromView: point)
    }

    /// Frames the current city area and every station.
    /// - Parameter readable: also keep stations at a comfortable on-screen size (automatic framing);
    ///   the player's "fit" button shows everything instead.
    func fitCity(animated: Bool, readable: Bool = false) {
        let state = engine.state
        let r = state.cityRadius
        let city = CGRect(x: state.map.cityCenter.x - r, y: state.map.cityCenter.y - r, width: 2 * r, height: 2 * r)
        let stations = Rect.bounding(state.stations.map(\.position))
            .map { CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }

        guard readable, let stations else {
            // Whole city plus room for the HUD panels.
            let rect = stations.map { city.union($0) } ?? city
            cameraController.fit(rect.insetBy(dx: -r * 0.25, dy: -r * 0.25), animated: animated)
            return
        }
        // Automatic framing: show the city if stations stay readable (≥ ~11 pt), otherwise frame just the
        // stations, padded for the HUD, at the most zoomed-out scale that keeps them visible.
        let readableScale = VisualTheme.stationRadius / 11
        let pad = VisualTheme.stationRadius * 4
        // HUD bar covers the top of the view and hints/cards the bottom, so pad vertically on both sides.
        let tight = stations.insetBy(dx: -pad, dy: -pad - stations.height * 0.15 - 40)
        let target = city.union(stations).insetBy(dx: -r * 0.25, dy: -r * 0.25)
        let needed = max(target.width / max(size.width, 1), target.height / max(size.height, 1)) * 1.25
        if needed <= readableScale {
            cameraController.fit(target, animated: animated)
        } else {
            cameraController.fit(tight, animated: animated)
        }
    }

    func zoom(by factor: CGFloat, aroundView point: CGPoint? = nil) {
        let anchor = point.map(worldPoint(fromView:)) ?? cameraController.camera.position
        cameraController.zoom(by: factor, around: anchor)
    }
}
