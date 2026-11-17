import SwiftUI
import MetroCore

/// Personal records: totals, campaign and challenge progress, Endless bests per city and difficulty.
struct StatisticsView: View {
    let onBack: () -> Void

    private var progress: PlayerProgress { ProgressStore.shared.progress }

    var body: some View {
        ZStack {
            UITheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: UITheme.isCompact ? 10 : 16) {
                HStack(spacing: 12) {
                    Button(action: onBack) { Label("Menu", systemImage: "chevron.left") }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                    Text("Statistics").font(UITheme.font(size: UITheme.isCompact ? 24 : 34, weight: .heavy))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Tile(value: "\(progress.totals.games)", label: "games played")
                            Tile(value: "\(progress.totals.passengers)", label: "passengers carried")
                            Tile(value: hours(progress.totals.playTime), label: "time in the city")
                            Tile(value: "\(progress.campaignStars)/\(CampaignManager.levels.count * 3)", label: "campaign stars")
                            Tile(value: "\(progress.challenges.values.reduce(0) { $0 + $1.stars })/\(ChallengeManager.challenges.count * 3)",
                                 label: "challenge medals")
                        }
                        Text("Endless bests").font(UITheme.font(.headline))
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                            GridRow {
                                Text("City")
                                ForEach(Difficulty.allCases) { Text($0.displayName) }
                                Text("Most weeks")
                                Text("Best efficiency")
                            }
                            .font(UITheme.font(.caption, weight: .bold))
                            .foregroundStyle(UITheme.secondaryInk)
                            ForEach(PlayerProgress.endlessMaps.map(\.preset)) { preset in
                                let records = Difficulty.allCases.map { progress.bestEndless(map: preset.id, difficulty: $0) }
                                GridRow {
                                    Text(preset.name).font(UITheme.font(.subheadline, weight: .semibold))
                                    ForEach(Array(records.enumerated()), id: \.offset) { _, r in
                                        Text(r.map { "\($0.bestScore)" } ?? "–").monospacedDigit()
                                    }
                                    Text("\(records.compactMap { $0?.longestWeeks }.max() ?? 0)").monospacedDigit()
                                    Text(records.compactMap { $0?.bestEfficiency }.filter { $0 > 0 }.max().map { "\($0)%" } ?? "–")
                                }
                                .font(UITheme.font(.subheadline))
                            }
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .foregroundStyle(UITheme.ink)
                    .padding(.bottom, 20)
                }
            }
            .foregroundStyle(UITheme.ink)
            .padding(UITheme.isCompact ? 14 : 28)
        }
    }

    private func hours(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? tr("\(minutes / 60) h \(minutes % 60) min") : tr("\(minutes) min")
    }
}

private struct Tile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(UITheme.font(.title3, weight: .heavy)).monospacedDigit()
            Text(label).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Default difficulty and progress reset (sound settings arrive with the audio in Phase 6).
/// A small map swatch for a theme: land, water, park and three line colours.
private struct ThemeCard: View {
    let theme: ThemePalette
    let selected: Bool
    /// Campaign level that unlocks it; nil when available.
    let lockLevel: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Canvas { context, size in
                    let w = size.width, h = size.height
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.land.color))
                    context.fill(Path(ellipseIn: CGRect(x: w * 0.55, y: h * 0.45, width: w * 0.6, height: h * 0.8)),
                                 with: .color(theme.water.color))
                    context.fill(Path(roundedRect: CGRect(x: w * 0.08, y: h * 0.1, width: w * 0.28, height: h * 0.3),
                                      cornerRadius: 4), with: .color(theme.park.color))
                    for (i, y) in [0.3, 0.55, 0.8].enumerated() {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: h * y))
                        line.addLine(to: CGPoint(x: w, y: h * (y - 0.15)))
                        context.stroke(line, with: .color(theme.lines[i * 2].color),
                                       style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                }
                .frame(width: 104, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if let lockLevel {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial)
                            Label(tr("Level \(lockLevel)"), systemImage: "lock.fill").font(UITheme.font(.caption2, weight: .bold))
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? UITheme.accent : .black.opacity(0.08), lineWidth: selected ? 3 : 1))
                Text(theme.name).font(UITheme.font(.caption, weight: selected ? .bold : .regular))
            }
            .foregroundStyle(UITheme.ink)
        }
        .buttonStyle(.plain)
        .disabled(lockLevel != nil)
        .help(lockLevel.map { tr("Finish campaign level \($0) to unlock") } ?? theme.name)
    }
}

private struct VolumeRow: View {
    let label: String
    let icon: String
    let value: Double
    let onChange: @MainActor (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(UITheme.secondaryInk)
            Text(label).font(UITheme.font(.subheadline)).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { v in onChange(v) }), in: 0...1)
            Text("\(Int((value * 100).rounded()))%").font(UITheme.font(.caption).monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct SettingsView: View {
    let onBack: () -> Void
    let onProgressReset: () -> Void

    @State private var confirmReset = false
    private var progress: PlayerProgress { ProgressStore.shared.progress }

    private func applyAudio() {
        let p = ProgressStore.shared.progress
        AudioManager.shared.configure(music: p.musicVolume, effects: p.effectsVolume, muted: p.muted)
    }

    var body: some View {
        ZStack {
            UITheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button(action: onBack) { Label("Menu", systemImage: "chevron.left") }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                    Text("Settings").font(UITheme.font(size: UITheme.isCompact ? 24 : 34, weight: .heavy))
                }
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Panel {
                    HStack {
                        Text("Language").font(UITheme.font(.headline))
                        Spacer()
                        LanguageSwitch()
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Endless difficulty").font(UITheme.font(.headline))
                        DifficultyPicker(selection: Binding(get: { progress.defaultDifficulty },
                                                            set: { d in ProgressStore.shared.update { $0.defaultDifficulty = d } }),
                                         progress: progress)
                        Text(progress.defaultDifficulty.summary).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Map theme").font(UITheme.font(.headline))
                        HStack(spacing: 10) {
                            ForEach(ThemePalette.all, id: \.id) { theme in
                                ThemeCard(theme: theme, selected: progress.theme == theme.id,
                                          lockLevel: progress.isThemeUnlocked(theme.id) ? nil
                                              : PlayerProgress.themeUnlocks[theme.id]) {
                                    ProgressStore.shared.update { $0.theme = theme.id }
                                    VisualTheme.palette = theme
                                    Feedback.play(.toggle)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sound").font(UITheme.font(.headline))
                        VolumeRow(label: "Music", icon: "music.note", value: progress.musicVolume) { v in
                            ProgressStore.shared.update { $0.musicVolume = v }
                            applyAudio()
                        }
                        VolumeRow(label: "Effects", icon: "speaker.wave.2.fill", value: progress.effectsVolume) { v in
                            ProgressStore.shared.update { $0.effectsVolume = v }
                            applyAudio()
                            Feedback.play(.tap)
                        }
                        Toggle(isOn: Binding(get: { progress.muted }, set: { m in
                            ProgressStore.shared.update { $0.muted = m }
                            applyAudio()
                        })) {
                            Label("Mute all sound", systemImage: "speaker.slash.fill").font(UITheme.font(.subheadline))
                        }
                        .toggleStyle(.switch)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Progress").font(UITheme.font(.headline))
                        Text("Everything is stored on this device only: campaign stars, challenge medals, best scores and the game in progress.")
                            .font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(role: .destructive) { confirmReset = true } label: {
                            Label("Reset all progress", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
                }
                .padding(.bottom, 20)
                }
            }
            .foregroundStyle(UITheme.ink)
            .padding(UITheme.isCompact ? 14 : 28)
        }
        .confirmationDialog(tr("Reset all progress?"), isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                ProgressStore.shared.reset()
                SessionStore.clear()
                onProgressReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Campaign stars, challenge medals, best scores and the saved game will be deleted. This can't be undone.")
        }
    }
}
