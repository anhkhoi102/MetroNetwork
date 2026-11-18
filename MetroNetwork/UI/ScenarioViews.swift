import SwiftUI
import MetroCore

/// In play: each objective with its progress.
struct ObjectivesCard: View {
    let controller: GameSessionController
    let scenario: ScenarioDefinition
    let objectives: [ObjectiveProgress]

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scenario.title).font(UITheme.font(.headline))
                        Text(scenario.weekLimit.map { tr("Ends after week \($0)") } ?? "Until the network fails")
                            .font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                    }
                    Spacer()
                    Button(action: controller.toggleObjectives) {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(objectives.enumerated()), id: \.offset) { i, p in
                    ObjectiveRow(index: i, progress: p, medals: scenario.kind == .challenge,
                                 required: i == 0 && scenario.kind == .campaign)
                }
            }
            .foregroundStyle(UITheme.ink)
            .frame(width: UITheme.isCompact ? 320 : 360)
        }
    }
}

struct ObjectiveRow: View {
    let index: Int
    let progress: ObjectiveProgress
    let medals: Bool
    var required = false
    /// False on a failed campaign level: later objectives only count once the first one is met, so they are
    /// shown as locked rather than ticked.
    var counts = true

    private var met: Bool { progress.met && counts }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: !counts ? "lock.fill" : met ? "checkmark.circle.fill"
                      : progress.lost ? "xmark.circle.fill" : (medals ? "medal" : "star"))
                    .foregroundStyle(!counts ? UITheme.secondaryInk : met ? UITheme.lineColor(3)
                                     : progress.lost ? VisualTheme.danger.color : UITheme.secondaryInk)
                Text(ObjectiveText.describe(progress.objective) + (required ? tr(" (to pass)") : ""))
                    .font(UITheme.font(.subheadline, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(counts ? ObjectiveText.value(progress) : tr("Needs the first objective"))
                    .font(UITheme.font(.caption).monospacedDigit())
                    .foregroundStyle(UITheme.secondaryInk)
            }
            if showsBar && counts {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(UITheme.ink.opacity(0.1))
                        Capsule().fill(met ? UITheme.lineColor(3) : UITheme.lineColor(2))
                            .frame(width: max(4, geo.size.width * min(1, progress.current / max(progress.target, 1))))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var showsBar: Bool {
        switch progress.objective {
        case .calmStations, .maxLines: false
        default: !progress.lost
        }
    }
}

/// End of a campaign level or challenge: stars, objectives, and what to do next.
struct ScenarioResultView: View {
    let scenario: ScenarioDefinition
    let result: ScenarioResult
    let summary: SessionSummary
    let failedStation: Station?
    let previousBest: Int?
    let next: ScenarioDefinition?
    let onNext: (ScenarioDefinition) -> Void
    let onRetry: () -> Void
    let onLevels: () -> Void
    let onMenu: () -> Void

    private var medals: Bool { scenario.kind == .challenge }

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            Panel {
                VStack(alignment: .leading, spacing: UITheme.isCompact ? 8 : 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(UITheme.font(UITheme.isCompact ? .title3 : .title2, weight: .heavy))
                            Text(subtitle).font(UITheme.font(.subheadline)).foregroundStyle(UITheme.secondaryInk)
                        }
                        Spacer()
                        StarRow(stars: result.stars, medals: medals, size: UITheme.isCompact ? 22 : 28)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(result.objectives.enumerated()), id: \.offset) { i, p in
                            ObjectiveRow(index: i, progress: p, medals: medals, required: i == 0 && !medals,
                                         counts: medals || i == 0 || result.passed)
                        }
                    }
                    HStack(spacing: 16) {
                        Label(tr("\(summary.score) points"), systemImage: "star.fill")
                        Label(tr("\(summary.delivered) passengers"), systemImage: "figure.walk.arrival")
                        if let e = summary.efficiency { Label(tr("\(Int(e.rounded()))% efficiency"), systemImage: "gauge.with.dots.needle.50percent") }
                        if let previousBest, result.score > previousBest {
                            Text("New best").font(UITheme.font(.caption, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(VisualTheme.delivered.color, in: Capsule())
                        }
                    }
                    .font(UITheme.font(.caption, weight: .semibold))
                    .foregroundStyle(UITheme.secondaryInk)
                    HStack(spacing: 10) {
                        Button("Menu", action: onMenu).buttonStyle(.bordered)
                        Button(medals ? "Challenges" : "Levels", action: onLevels).buttonStyle(.bordered)
                        Spacer()
                        Button(action: onRetry) { Label("Retry", systemImage: "arrow.clockwise") }
                            .buttonStyle(.bordered)
                        if let next, result.passed {
                            Button { onNext(next) } label: {
                                Label(tr("Next: \(next.title)"), systemImage: "arrow.right")
                                    .font(UITheme.font(.subheadline, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(UITheme.lineColor(2))
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .controlSize(UITheme.isCompact ? .small : .regular)
                }
                .foregroundStyle(UITheme.ink)
                .padding(UITheme.isCompact ? 2 : 8)
                .frame(width: UITheme.isCompact ? 560 : 560)
            }
        }
    }

    private var title: String {
        if medals { return result.stars > 0 ? "Challenge complete" : "Challenge over" }
        return result.passed ? "Level complete" : "Level failed"
    }

    private var subtitle: String {
        if failedStation != nil, result.passed, !medals {
            return tr("\(scenario.title): the network failed in week \(summary.week), but you had already met the goal to pass.")
        }
        if let failedStation, !result.passed || medals {
            return tr("\(scenario.title): a \(failedStation.shape.displayName.lowercased()) station was overcrowded for too long.")
        }
        if !result.passed { return tr("\(scenario.title): the first objective wasn't met in time.") }
        return tr("\(scenario.title) · week \(min(summary.week, scenario.weekLimit ?? summary.week))")
    }
}
