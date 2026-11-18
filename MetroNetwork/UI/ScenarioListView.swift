import SwiftUI
import MetroCore

/// Campaign levels or challenges: cards with stars/medals; tap one for its briefing.
struct ScenarioListView: View {
    let kind: ScenarioKind
    let onStart: (ScenarioDefinition) -> Void
    let onBack: () -> Void

    @State private var briefing: ScenarioDefinition?

    private var progress: PlayerProgress { ProgressStore.shared.progress }
    private var items: [ScenarioDefinition] { kind == .campaign ? CampaignManager.levels : ChallengeManager.challenges }

    var body: some View {
        ZStack {
            UITheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: UITheme.isCompact ? 10 : 16) {
                HStack(spacing: 12) {
                    Button(action: onBack) { Label("Menu", systemImage: "chevron.left") }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                    Text(kind == .campaign ? "Campaign" : "Challenges")
                        .font(UITheme.font(size: UITheme.isCompact ? 24 : 34, weight: .heavy))
                    Spacer()
                    if kind == .campaign {
                        Label("\(progress.campaignStars)/\(items.count * 3)", systemImage: "star.fill")
                            .font(UITheme.font(.headline).monospacedDigit())
                            .foregroundStyle(VisualTheme.delivered.darkened(0.15).color)
                    }
                }
                .foregroundStyle(UITheme.ink)
                Text(kind == .campaign
                     ? "Each city introduces one idea. Meet the first objective before time runs out to pass; every objective is a star."
                     : "Fixed cities with one unusual rule each. Every attempt plays out the same way, so a better plan always scores better.")
                    .font(UITheme.font(.caption))
                    .foregroundStyle(UITheme.secondaryInk)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: UITheme.isCompact ? 190 : 240), spacing: 12)], spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ScenarioCard(item: item, number: index + 1, record: record(item), locked: !isUnlocked(item, index),
                                         lockHint: lockHint(item, index)) { briefing = item }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(UITheme.isCompact ? 14 : 28)

            if let briefing {
                BriefingView(scenario: briefing, record: record(briefing),
                             onStart: { onStart(briefing) }, onClose: { self.briefing = nil })
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: briefing?.id)
    }

    private func record(_ item: ScenarioDefinition) -> PlayerProgress.LevelRecord? {
        kind == .campaign ? progress.campaign[item.id] : progress.challenges[item.id]
    }

    private func isUnlocked(_ item: ScenarioDefinition, _ index: Int) -> Bool {
        kind == .campaign ? progress.isLevelUnlocked(index) : progress.isChallengeUnlocked(item.id)
    }

    private func lockHint(_ item: ScenarioDefinition, _ index: Int) -> String {
        kind == .campaign ? tr("Pass level \(index) first")
            : tr("Finish campaign level \(PlayerProgress.challengeUnlocks[item.id] ?? 0)")
    }
}

private struct ScenarioCard: View {
    let item: ScenarioDefinition
    let number: Int
    let record: PlayerProgress.LevelRecord?
    let locked: Bool
    let lockHint: String
    let action: () -> Void

    var body: some View {
        Button { Feedback.play(.tap); action() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(item.kind == .campaign ? "\(number)" : "")
                        .font(UITheme.font(size: 26, weight: .heavy))
                        .foregroundStyle(UITheme.lineColor(number - 1))
                        .frame(minWidth: item.kind == .campaign ? 22 : 0, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(UITheme.font(.headline))
                        Text(item.feature).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    if locked { Image(systemName: "lock.fill").foregroundStyle(UITheme.secondaryInk) }
                }
                HStack {
                    StarRow(stars: record?.stars ?? 0, medals: item.kind == .challenge)
                    Spacer()
                    Text(locked ? lockHint : record.map { tr("Best \($0.bestScore)") } ?? weeks)
                        .font(UITheme.font(.caption))
                        .foregroundStyle(UITheme.secondaryInk)
                }
            }
            .foregroundStyle(UITheme.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.55 : 1)
    }

    private var weeks: String { item.weekLimit.map { tr("\($0) weeks") } ?? "No time limit" }
}

/// Three stars (campaign) or bronze/silver/gold medals (challenges).
struct StarRow: View {
    let stars: Int
    var medals = false
    var size: CGFloat = 15

    private static let medalColors = [RGB(hex: 0xC9824A), RGB(hex: 0x9EA7B3), RGB(hex: 0xE5B53A)]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: medals ? "medal.fill" : "star.fill")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < stars
                                     ? (medals ? Self.medalColors[i].color : VisualTheme.delivered.darkened(0.05).color)
                                     : UITheme.ink.opacity(0.15))
            }
        }
        .accessibilityLabel(tr("\(stars) of 3 \(medals ? "medals" : "stars")"))
    }
}

/// Before playing: the city, the idea it introduces, and what earns each star.
struct BriefingView: View {
    let scenario: ScenarioDefinition
    let record: PlayerProgress.LevelRecord?
    let onStart: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea().onTapGesture(perform: onClose)
            Panel {
                HStack(alignment: .top, spacing: 16) {
                    if !UITheme.isCompact {
                        MapPreview(map: MapGenerator.generate(archetype: scenario.preset.archetype, seed: scenario.preset.seed,
                                                              name: scenario.preset.name))
                            .frame(width: 200, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: UITheme.isCompact ? 6 : 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(scenario.title).font(UITheme.font(.title3, weight: .heavy))
                                Text("\(scenario.preset.name) · \(scenario.feature) · "
                                     + (scenario.weekLimit.map { tr("\($0) weeks") } ?? "until the network fails"))
                                    .font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                            }
                            Spacer()
                            StarRow(stars: record?.stars ?? 0, medals: scenario.kind == .challenge)
                        }
                        Text(scenario.briefing)
                            .font(UITheme.font(UITheme.isCompact ? .caption : .callout))
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(scenario.objectives.enumerated()), id: \.offset) { i, objective in
                                HStack(spacing: 6) {
                                    Image(systemName: scenario.kind == .challenge ? "medal.fill" : "star.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(i < (record?.stars ?? 0) ? VisualTheme.delivered.darkened(0.05).color
                                                         : UITheme.ink.opacity(0.3))
                                        .frame(width: 14)
                                    Text(ObjectiveText.describe(objective) + (i == 0 && scenario.kind == .campaign ? tr(" (to pass)") : ""))
                                        .font(UITheme.font(.subheadline))
                                }
                            }
                        }
                        HStack {
                            Button("Back", action: onClose).buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                            Spacer()
                            Button(action: onStart) {
                                Label(record == nil ? "Start" : "Play again", systemImage: "play.fill")
                                    .font(UITheme.font(.subheadline, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(UITheme.lineColor(2))
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .foregroundStyle(UITheme.ink)
                .padding(UITheme.isCompact ? 2 : 8)
                .frame(width: UITheme.isCompact ? 520 : 620)
            }
        }
    }
}

/// Player-facing wording for objectives.
enum ObjectiveText {
    static func describe(_ objective: Objective) -> String {
        switch objective {
        case .deliver(let n): tr("Deliver \(n) passengers")
        case .score(let n): tr("Score \(n) points")
        case .connectedStations(let n): tr("Have \(n) stations on lines at the end")
        case .efficiency(let n): tr("Average network efficiency \(n)% or more")
        case .calmStations: "Never let a station's overcrowding ring pass halfway"
        case .rushDeliveries(let n): tr("Deliver \(n) passengers during rush hours")
        case .maxLines(let n): tr("Never run more than \(n) lines")
        case .surviveWeeks(let n): tr("Keep the network running to the end of week \(n)")
        case .fansDelivered(let n): tr("Deliver \(n) fans after matches")
        case .travellersOnTime(let n): tr("Deliver \(n) airport travellers on time")
        }
    }

    static func value(_ p: ObjectiveProgress) -> String {
        switch p.objective {
        case .calmStations: p.lost ? "Broken" : p.met ? "Kept" : tr("Holding · worst \(Int((p.current * 100).rounded()))%")
        case .maxLines: p.lost ? "Broken" : p.met ? "Kept" : tr("Holding · \(Int(p.current)) lines")
        case .efficiency: "\(Int(p.current))% / \(Int(p.target))%"
        case .surviveWeeks where p.lost: "Broken"                  // not "5 / 5" when it failed during week 5
        default: "\(Int(p.current)) / \(Int(p.target))"
        }
    }
}
