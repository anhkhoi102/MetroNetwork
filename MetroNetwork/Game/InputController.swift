import SpriteKit
import MetroCore

/// One pointer state machine for mouse and touch. Platform views only forward raw pointer positions
/// (in view coordinates); everything gameplay-related is decided here and in MetroCore's `RouteEditor`.
@MainActor
final class InputController {

    /// Touch targets in screen points, converted to world units with the current zoom.
    private enum Tolerance {
        #if os(iOS)
        static let dragStart: CGFloat = 10
        static let station: CGFloat = 26
        static let segment: CGFloat = 18
        static let handle: CGFloat = 24
        static let train: CGFloat = 20
        #else
        static let dragStart: CGFloat = 4
        static let station: CGFloat = 16
        static let segment: CGFloat = 9
        static let handle: CGFloat = 13
        static let train: CGFloat = 11
        #endif
    }

    private enum Hit {
        case station(StationID)
        case train(TrainID)
        case handle(LineID, LineEnd)
        case segment(LineID, Int)
        case empty
    }

    private enum Gesture {
        case none
        case pending(Hit, startView: CGPoint)
        case panning(lastView: CGPoint)
        /// `lastWorld` = previous pointer position, so the whole path between samples is swept.
        case editing(RouteEditor, lastWorld: Vec2)
    }

    private unowned let scene: GameScene
    private var gesture: Gesture = .none

    init(scene: GameScene) {
        self.scene = scene
    }

    var isEditing: Bool {
        if case .editing = gesture { return true }
        return false
    }

    // MARK: Pointer events

    func pointerDown(at viewPoint: CGPoint, forcePan: Bool = false) {
        cancel()
        gesture = forcePan ? .panning(lastView: viewPoint) : .pending(hitTest(viewPoint), startView: viewPoint)
    }

    func pointerMoved(to viewPoint: CGPoint) {
        switch gesture {
        case .none:
            return
        case .pending(let hit, let start):
            guard hypot(viewPoint.x - start.x, viewPoint.y - start.y) >= Tolerance.dragStart else { return }
            beginDrag(hit, startView: start)
            pointerMoved(to: viewPoint)
        case .panning(let last):
            let a = scene.worldPoint(fromView: last), b = scene.worldPoint(fromView: viewPoint)
            scene.cameraController.pan(byWorld: CGPoint(x: a.x - b.x, y: a.y - b.y))
            gesture = .panning(lastView: viewPoint)
        case .editing(var editor, let last):
            let world = scene.worldPoint(fromView: viewPoint).vec2
            let hovered = sweep(&editor, from: last, to: world)
            gesture = .editing(editor, lastWorld: world)
            scene.showDraft(editor, pointer: world, hovered: hovered)
        }
    }

    func pointerUp(at viewPoint: CGPoint) {
        let finished = gesture
        gesture = .none
        switch finished {
        case .none, .panning:
            break
        case .pending(let hit, _):
            tap(hit)
        case .editing(var editor, let last):
            sweep(&editor, from: last, to: scene.worldPoint(fromView: viewPoint).vec2)
            scene.clearDraft()
            if let command = editor.commitCommand() {
                scene.controller?.perform(command)
            }
        }
    }

    /// Abandons any gesture without committing (second finger, Escape, focus loss).
    func cancel() {
        if case .editing = gesture { scene.clearDraft() }
        gesture = .none
    }

    // MARK: Private

    /// Feeds every station between two pointer samples to the editor, in order. Pointer events can be
    /// far apart (fast swipes, slow frames); without this a station crossed between samples would be skipped.
    /// - Returns: the station under the end point, if any.
    @discardableResult
    private func sweep(_ editor: inout RouteEditor, from start: Vec2, to end: Vec2) -> StationID? {
        let stations = scene.engine.state.stations
        let radius = worldTolerance(Tolerance.station, minimum: VisualTheme.stationRadius * 1.5)
        let steps = max(1, Int((start.distance(to: end) / (radius * 0.5)).rounded(.up)))
        var hovered: StationID?
        for i in 1...steps {
            hovered = RouteGeometry.station(at: Vec2.lerp(start, end, Double(i) / Double(steps)), in: stations,
                                            radius: radius)
            editor.hover(hovered)
        }
        return hovered
    }

    private func beginDrag(_ hit: Hit, startView: CGPoint) {
        let state = scene.engine.state
        let result: Result<RouteEditor, RouteError>?
        switch hit {
        case .station(let id): result = RouteEditor.newLine(from: id, in: state)
        case .handle(let id, let end): result = RouteEditor.extend(id, from: end, in: state)
        case .segment(let id, let index): result = RouteEditor.insert(into: id, segment: index, in: state)
        case .train, .empty: result = nil      // dragging a train (or empty map) pans
        }
        switch result {
        case .none:
            gesture = .panning(lastView: startView)
        case .success(let editor):
            scene.controller?.clearSelection()
            gesture = .editing(editor, lastWorld: scene.worldPoint(fromView: startView).vec2)
        case .failure(let error):
            scene.controller?.showToast(error.message)
            gesture = .none
        }
    }

    private func tap(_ hit: Hit) {
        guard let controller = scene.controller else { return }
        switch hit {
        case .station(let id): controller.select(.station(id))
        case .train(let id): controller.select(.train(id))
        case .handle(let id, _), .segment(let id, _): controller.select(.line(id))
        case .empty: controller.clearSelection()
        }
    }

    private func hitTest(_ viewPoint: CGPoint) -> Hit {
        let world = scene.worldPoint(fromView: viewPoint).vec2
        let state = scene.engine.state
        let geometry = scene.routeRenderer.geometry
        if let id = RouteGeometry.station(at: world, in: state.stations,
                                          radius: worldTolerance(Tolerance.station, minimum: VisualTheme.stationRadius * 1.3)) {
            return .station(id)
        }
        // Stations win over trains, so a line can always be started from a station with a train in it.
        let trainRadius = worldTolerance(Tolerance.train, minimum: 14)
        if let (id, _) = scene.trainRenderer.positions
            .map({ ($0.key, $0.value.distance(to: world)) })
            .filter({ $0.1 <= trainRadius })
            .min(by: { $0.1 < $1.1 }) {
            return .train(id)
        }
        if let (id, handle) = RouteGeometry.handle(at: world, in: geometry, tolerance: worldTolerance(Tolerance.handle)) {
            return .handle(id, handle.end)
        }
        if let (id, index) = RouteGeometry.segment(at: world, in: geometry,
                                                   tolerance: worldTolerance(Tolerance.segment,
                                                                             minimum: VisualTheme.routeMetrics.lineWidth)) {
            return .segment(id, index)
        }
        return .empty
    }

    private func worldTolerance(_ points: CGFloat, minimum: CGFloat = 0) -> Double {
        Double(max(minimum, points * scene.cameraController.scale))
    }
}
