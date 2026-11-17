import SwiftUI
import MetroCore

/// The game: SpriteKit map with a SwiftUI HUD and context cards on top.
struct GameScreen: View {
    let controller: GameSessionController
    let onExit: () -> Void
    let onPlayAgain: () -> Void
    let onChooseCity: () -> Void
    let onNextLevel: (ScenarioDefinition) -> Void
    let onLevels: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmExit = false

    var body: some View {
        ZStack {
            GameViewContainer(scene: controller.scene)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HUDView(controller: controller, onExit: {
                    if controller.result == nil { confirmExit = true } else { onExit() }
                })
                StatusRow(controller: controller)
                    .padding(.top, 6)
                Spacer(minLength: 0)
                bottomArea
            }
            .padding(UITheme.isCompact ? 8 : 14)

            if controller.isDepotOpen {
                DepotView(controller: controller)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if let result = controller.result {
                if let scenarioResult = result.scenario, let scenario = controller.scenario {
                    ScenarioResultView(scenario: scenario, result: scenarioResult, summary: result.summary,
                                       failedStation: result.station, previousBest: result.previousBest,
                                       next: controller.nextLevel,
                                       onNext: onNextLevel, onRetry: onPlayAgain, onLevels: onLevels, onMenu: onExit)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    GameOverView(result: result, cityName: controller.preset.name,
                                 onPlayAgain: onPlayAgain, onChooseCity: onChooseCity, onMenu: onExit)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }

            if let toast = controller.toast {
                Text(toast)
                    .font(UITheme.font(.callout).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(UITheme.ink.opacity(0.88), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: controller.toast)
        .animation(.easeOut(duration: 0.18), value: controller.selection)
        .animation(.easeOut(duration: 0.18), value: controller.showsEfficiency)
        .animation(.easeOut(duration: 0.18), value: controller.showsObjectives)
        .animation(.easeOut(duration: 0.2), value: controller.isDepotOpen)
        .animation(.easeOut(duration: 0.35).delay(0.6), value: controller.result)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !controller.hud.isPaused, controller.result == nil { controller.togglePause() }
        }
        .confirmationDialog(translated(controller.result == nil ? "Leave this city?" : "Leave?"), isPresented: $confirmExit) {
            Button("Leave", role: .destructive, action: onExit)
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("Your game is saved; choose Continue on the menu to carry on.")
        }
    }

    @ViewBuilder
    private var bottomArea: some View {
        HStack(alignment: .bottom) {
            if let info = controller.selectedStation {
                StationCard(controller: controller, station: info.station, lines: info.lines)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let info = controller.selectedLine {
                LineCard(controller: controller, line: info.line, stations: info.stations, trains: info.trains)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let info = controller.selectedTrain {
                TrainCard(controller: controller, train: info.train, line: info.line, nextStop: info.nextStop)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if controller.showsObjectives, let scenario = controller.scenario {
                ObjectivesCard(controller: controller, scenario: scenario, objectives: controller.objectives)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if controller.showsEfficiency, let details = controller.efficiencyDetails {
                EfficiencyCard(controller: controller, efficiency: details.efficiency, factors: details.factors)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if controller.hud.lineCount == 0, controller.result == nil {
                Panel {
                    Label("Drag from one station to another to build your first line.", systemImage: "hand.draw")
                        .font(UITheme.font(.callout))
                        .foregroundStyle(UITheme.ink)
                }
                .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
        }
    }
}
