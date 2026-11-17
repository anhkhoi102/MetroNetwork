import SwiftUI
import SpriteKit

/// Hosts the platform-specific SKView subclass that presents the shared GameScene.
#if os(macOS)
struct GameViewContainer: NSViewRepresentable {
    let scene: GameScene

    func makeNSView(context: Context) -> MacGameView {
        let view = MacGameView(frame: .zero)
        configure(view)
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: MacGameView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
    }

    static func dismantleNSView(_ view: MacGameView, coordinator: ()) {
        view.presentScene(nil)
    }
}
#else
struct GameViewContainer: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> IOSGameView {
        let view = IOSGameView(frame: .zero)
        configure(view)
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: IOSGameView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
    }

    static func dismantleUIView(_ view: IOSGameView, coordinator: ()) {
        view.presentScene(nil)
    }
}
#endif

@MainActor
private func configure(_ view: SKView) {
    view.ignoresSiblingOrder = true
    view.preferredFramesPerSecond = 120
    view.shouldCullNonVisibleNodes = true
    #if DEBUG
    view.showsFPS = true
    view.showsNodeCount = true
    #endif
}
