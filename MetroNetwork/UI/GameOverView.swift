import SwiftUI
import MetroCore

/// End-of-session summary for Endless: why it ended, the numbers, and the personal best for this city.
struct GameOverView: View {
    let result: GameSessionController.SessionResult
    let cityName: String
    let onPlayAgain: () -> Void
    let onChooseCity: () -> Void
    let onMenu: () -> Void

    private var s: SessionSummary { result.summary }

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            Panel {
                VStack(alignment: .leading, spacing: UITheme.isCompact ? 10 : 16) {
                    HStack(alignment: .top, spacing: 12) {
                        if let station = result.station {
                            StationShapeIcon(shape: station.shape, size: 34, lineWidth: 3)
                                .padding(6)
                                .background(VisualTheme.danger.color.opacity(0.15), in: Circle())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Network overwhelmed")
                                .font(UITheme.font(UITheme.isCompact ? .title3 : .title2, weight: .heavy))
                            Text(reason)
                                .font(UITheme.font(.subheadline))
                                .foregroundStyle(UITheme.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(s.score)")
                            .font(UITheme.font(size: UITheme.isCompact ? 34 : 44, weight: .heavy))
                            .monospacedDigit()
                        Text("points").font(UITheme.font(.headline)).foregroundStyle(UITheme.secondaryInk)
                        Spacer()
                        bestBadge
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        Stat(value: "\(s.delivered)", label: "passengers")
                        Stat(value: tr("Week \(s.week)"), label: tr("\(timePlayed) played"))
                        Stat(value: "\(s.stations)", label: "stations")
                        Stat(value: s.averageJourney.map { "\(Int($0.rounded())) s" } ?? "–", label: "average journey")
                        Stat(value: "\(s.bestWeek)", label: "best week")
                        Stat(value: s.efficiency.map { "\(Int($0.rounded()))%" } ?? "–", label: "network efficiency")
                    }

                    HStack(spacing: 10) {
                        Button("Menu", action: onMenu)
                            .buttonStyle(.bordered)
                        Button("Choose city", action: onChooseCity)
                            .buttonStyle(.bordered)
                        Spacer()
                        Button(action: onPlayAgain) {
                            Label(tr("Play \(cityName) again"), systemImage: "arrow.clockwise")
                                .font(UITheme.font(.subheadline, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(UITheme.lineColor(2))
                        .keyboardShortcut(.defaultAction)
                    }
                    .controlSize(UITheme.isCompact ? .small : .regular)
                }
                .foregroundStyle(UITheme.ink)
                .padding(UITheme.isCompact ? 2 : 8)
                .frame(width: UITheme.isCompact ? 460 : 500)
            }
        }
    }

    private var reason: String {
        let name = result.station.map { tr("A \($0.shape.displayName.lowercased()) station") } ?? "A station"
        return tr("\(name) was overcrowded for too long.")
    }

    private var timePlayed: String {
        let total = Int(s.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private var bestBadge: some View {
        if result.isNewBest {
            Label("New best", systemImage: "trophy.fill")
                .font(UITheme.font(.caption, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(VisualTheme.delivered.color.opacity(0.95), in: Capsule())
        } else if let best = result.previousBest {
            Text(tr("Best \(best)"))
                .font(UITheme.font(.subheadline, weight: .semibold))
                .foregroundStyle(UITheme.secondaryInk)
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(UITheme.font(.headline)).monospacedDigit()
            Text(label).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
