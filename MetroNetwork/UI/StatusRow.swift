import SwiftUI
import MetroCore

/// Under the HUD: network efficiency (tap for the breakdown), then rush hour and event notices.
struct StatusRow: View {
    let controller: GameSessionController

    private var hud: GameSessionController.HUDSnapshot { controller.hud }

    var body: some View {
        HStack(spacing: 6) {
            if hud.objectivesTotal > 0 {
                Button(action: controller.toggleObjectives) {
                    HStack(spacing: 5) {
                        Image(systemName: controller.scenario?.kind == .challenge ? "medal.fill" : "star.fill")
                            .foregroundStyle(VisualTheme.delivered.darkened(0.1).color)
                        Text("\(hud.objectivesMet)/\(hud.objectivesTotal)").monospacedDigit()
                        if !UITheme.isCompact { Text("objectives") }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(VisualTheme.delivered.color.opacity(0.7), lineWidth: 1.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tr("Objectives for this level"))
            }
            if let efficiency = hud.efficiency {
                Button(action: controller.toggleEfficiency) {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .foregroundStyle(efficiencyColor(efficiency))
                        Text(UITheme.isCompact ? "\(efficiency)%" : tr("Efficiency \(efficiency)%")).monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(efficiencyColor(efficiency).opacity(0.6), lineWidth: 1.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tr("Network efficiency: waiting, trip times, train load and crowding. Click for details."))
                .accessibilityLabel(tr("Network efficiency \(efficiency) percent"))
            }
            ForEach(hud.notices.prefix(UITheme.isCompact ? 2 : 3)) { notice in
                NoticeCapsule(notice: notice)
            }
        }
        .font(UITheme.font(.caption, weight: .semibold))
        .foregroundStyle(UITheme.ink)
        .animation(.easeOut(duration: 0.2), value: hud.notices.map(\.id))
    }

    private func efficiencyColor(_ value: Int) -> Color {
        value >= 70 ? UITheme.lineColor(3) : value >= 45 ? VisualTheme.warning.color : VisualTheme.danger.color
    }
}

private struct NoticeCapsule: View {
    let notice: GameSessionController.Notice

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: notice.icon)
            Text(notice.text).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .foregroundStyle(notice.tone == .info ? UITheme.ink : .white)
        .background(background, in: Capsule())
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var background: AnyShapeStyle {
        switch notice.tone {
        case .info: AnyShapeStyle(.regularMaterial)
        case .warning: AnyShapeStyle(VisualTheme.warning.color)
        case .active: AnyShapeStyle(VisualTheme.danger.color.opacity(0.92))
        }
    }
}

/// Breakdown of network efficiency with a hint for the weakest part.
struct EfficiencyCard: View {
    let controller: GameSessionController
    let efficiency: NetworkEfficiency
    let factors: NetworkEfficiency.Factors

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.50percent").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("Network efficiency \(Int(efficiency.score.rounded()))%")).font(UITheme.font(.headline))
                        Text("Recent trips and the network right now").font(UITheme.font(.caption))
                            .foregroundStyle(UITheme.secondaryInk)
                    }
                    Spacer()
                    Button(action: controller.toggleEfficiency) {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                FactorRow(label: "Waiting", detail: tr("\(Int(efficiency.averageWait.rounded())) s on platforms"), value: factors.waiting)
                FactorRow(label: "Trip time", detail: tr("\(Int(efficiency.averageJourney.rounded())) s door to door, ")
                          + String(format: "%.1f", efficiency.averageTransfers) + tr(" changes"), value: factors.journey)
                FactorRow(label: "Train load", detail: tr("\(Int((efficiency.utilization * 100).rounded()))% of seats used"),
                          value: factors.load)
                FactorRow(label: "Crowding", detail: tr("\(Int((efficiency.congestion * 100).rounded()))% of stations nearly full"),
                          value: factors.crowding)
                Label(tip, systemImage: "lightbulb.fill")
                    .font(UITheme.font(.caption))
                    .foregroundStyle(UITheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(UITheme.ink)
            .frame(width: UITheme.isCompact ? 300 : 330)
        }
    }

    private var tip: String {
        let weakest = [("waiting", factors.waiting), ("trip", factors.journey), ("load", factors.load),
                       ("crowding", factors.crowding)].min { $0.1 < $1.1 }?.0
        switch weakest {
        case "waiting": return "Long waits: add trains to busy lines so they come more often."
        case "trip": return "Slow trips: shorten long lines, link shapes directly, or try express service."
        case "load": return "Empty seats: move trains from quiet lines to busy ones."
        default: return "Crowded stations: add trains, expand stations, or give them a second line."
        }
    }
}

private struct FactorRow: View {
    let label: String
    let detail: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(UITheme.font(.subheadline, weight: .semibold))
                Spacer()
                Text(detail).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(UITheme.ink.opacity(0.1))
                    Capsule().fill(value >= 0.7 ? UITheme.lineColor(3) : value >= 0.4 ? VisualTheme.warning.color : VisualTheme.danger.color)
                        .frame(width: max(4, geo.size.width * value))
                }
            }
            .frame(height: 5)
        }
    }
}
