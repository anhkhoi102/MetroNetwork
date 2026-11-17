import SwiftUI
import MetroCore

/// Top-level navigation: main menu → (campaign | endless map picker | challenges | statistics | settings) → game.
struct RootView: View {
    private enum Screen {
        case menu
        case mapPicker
        case campaign
        case challenges
        case statistics
        case settings
        case game(GameSessionController)
    }

    @State private var screen: Screen = RootView.initialScreen()
    /// A session saved earlier (shown as "Continue" on the menu).
    @State private var saved: SavedSession? = SessionStore.load()
    @Environment(\.scenePhase) private var scenePhase

    private static func initialScreen() -> Screen {
        #if DEBUG
        if let index = DemoDirector.presetIndex {
            if let theme = DemoDirector.themeID { VisualTheme.palette = .named(theme) }
            let preset = MapPreset.builtIn[index % MapPreset.builtIn.count]
            let mode = DemoDirector.scenarioID.map { SessionMode.scenario($0) } ?? .endless(preset, .normal)
            // -MetroDemoStress: a full city with every line and train, for profiling.
            let engine = ProcessInfo.processInfo.arguments.contains("-MetroDemoStress")
                ? GameEngine(state: Benchmark.fullCity(preset: preset))
                : GameSessionManager.newSession(mode: mode, adjust: DemoDirector.adjust)!
            let controller = GameSessionController(mode: mode, engine: engine)
            // The demo never touches the real save unless asked (-MetroDemoPersist, for testing saving).
            controller.persistsSession = ProcessInfo.processInfo.arguments.contains("-MetroDemoPersist")
            DemoDirector.run(controller)
            return .game(controller)
        }
        // -MetroScreen <name>: open a menu screen directly (screenshots on several device sizes).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-MetroScreen"), args.indices.contains(i + 1) {
            switch args[i + 1] {
            case "campaign": return .campaign
            case "challenges": return .challenges
            case "endless": return .mapPicker
            case "statistics": return .statistics
            case "settings": return .settings
            default: break
            }
        }
        #endif
        return .menu
    }

    var body: some View {
        ZStack {
            switch screen {
            case .menu:
                MainMenuView(saved: saved,
                             onContinue: continueSaved,
                             onEndless: { show(.mapPicker) },
                             onCampaign: { show(.campaign) },
                             onChallenges: { show(.challenges) },
                             onStatistics: { show(.statistics) },
                             onSettings: { show(.settings) })
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            case .mapPicker:
                MapPickerView(onPick: { preset, difficulty in start(.endless(preset, difficulty)) },
                              onBack: { show(.menu) })
                    .transition(Self.push)
            case .campaign:
                ScenarioListView(kind: .campaign, onStart: { start(.scenario($0.id)) }, onBack: { show(.menu) })
                    .transition(Self.push)
            case .challenges:
                ScenarioListView(kind: .challenge, onStart: { start(.scenario($0.id)) }, onBack: { show(.menu) })
                    .transition(Self.push)
            case .statistics:
                StatisticsView(onBack: { show(.menu) })
                    .transition(Self.push)
            case .settings:
                SettingsView(onBack: { show(.menu) }, onProgressReset: { saved = SessionStore.load() })
                    .transition(Self.push)
            case .game(let controller):
                GameScreen(controller: controller,
                           onExit: { leave(controller) },
                           onPlayAgain: { show(.game(controller.freshCopy())) },
                           onChooseCity: { show(.mapPicker) },
                           onNextLevel: { level in start(.scenario(level.id)) },
                           onLevels: { show(controller.scenario?.kind == .challenge ? .challenges : .campaign) })
                    .id(ObjectIdentifier(controller))
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #if DEBUG
        .onAppear {
            // -MetroWindowSize 900x600: resize the window (screenshots at the smallest supported size).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-MetroWindowSize"), args.indices.contains(i + 1) {
                let parts = args[i + 1].split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 {
                    DispatchQueue.main.async {
                        NSApplication.shared.windows.first?.setContentSize(NSSize(width: parts[0], height: parts[1]))
                    }
                }
            }
        }
        #endif
        #endif
        .onChange(of: scenePhase) { _, phase in
            // Backgrounded or closing: save the game in progress.
            if phase != .active, case .game(let controller) = screen { controller.autosave() }
        }
    }

    private func start(_ mode: SessionMode) {
        SessionStore.clear()
        saved = nil
        show(.game(GameSessionController(mode: mode)))
    }

    private func continueSaved() {
        guard let saved else { return }
        let controller = GameSessionController(mode: saved.mode, engine: GameSessionManager.resume(saved))
        show(.game(controller))
    }

    /// Back to the menu; an unfinished game is kept for "Continue".
    private func leave(_ controller: GameSessionController) {
        controller.autosave()
        saved = SessionStore.load()
        show(.menu)
    }

    /// Sub-screens slide in from the right and back out to the right.
    private static let push = AnyTransition.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                       removal: .move(edge: .trailing).combined(with: .opacity))

    private func show(_ next: Screen) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { screen = next }
    }
}
