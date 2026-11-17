import SwiftUI
import MetroCore

struct MapPickerView: View {
    let onPick: (MapPreset, Difficulty) -> Void
    let onBack: () -> Void

    @State private var randomSeed = UInt64.random(in: 1...999_999)
    @State private var difficulty: Difficulty = {
        let p = ProgressStore.shared.progress
        return p.isDifficultyUnlocked(p.defaultDifficulty) ? p.defaultDifficulty : .normal
    }()

    private var progress: PlayerProgress { ProgressStore.shared.progress }
    private var presets: [MapPreset] {
        PlayerProgress.endlessMaps.map(\.preset) + [MapPreset.random(seed: randomSeed)]
    }

    var body: some View {
        ZStack {
            UITheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: UITheme.isCompact ? 10 : 16) {
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        Label("Menu", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    Text("Endless")
                        .font(UITheme.font(size: UITheme.isCompact ? 24 : 34, weight: .heavy))
                        .foregroundStyle(UITheme.ink)
                    Spacer()
                    DifficultyPicker(selection: $difficulty, progress: progress)
                }
                Text(difficulty.summary)
                    .font(UITheme.font(.caption))
                    .foregroundStyle(UITheme.secondaryInk)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: UITheme.isCompact ? 205 : 220), spacing: 14)],
                              spacing: 14) {
                        ForEach(presets) { preset in
                            MapCard(preset: preset, isRandom: preset.id.hasPrefix("random"),
                                    unlockHint: progress.isMapUnlocked(preset) ? nil : unlockHint(preset),
                                    best: progress.bestEndless(map: preset.id, difficulty: difficulty)?.bestScore,
                                    onReroll: { randomSeed = UInt64.random(in: 1...999_999) },
                                    onPick: { onPick(preset, difficulty) })
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(UITheme.isCompact ? 14 : 28)
        }
        .onChange(of: difficulty) { _, d in ProgressStore.shared.update { $0.defaultDifficulty = d } }
    }

    private func unlockHint(_ preset: MapPreset) -> String {
        let level = preset.id.hasPrefix("random") ? PlayerProgress.randomCitiesAfterLevel
            : PlayerProgress.endlessMaps.first { $0.preset.id == preset.id }?.unlockedAfterLevel ?? 0
        return tr("Finish campaign level \(level)")
    }
}

/// Easy / Normal / Hard, with Hard locked until the campaign gets far enough.
struct DifficultyPicker: View {
    @Binding var selection: Difficulty
    let progress: PlayerProgress

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Difficulty.allCases) { d in
                let locked = !progress.isDifficultyUnlocked(d)
                Button {
                    selection = d
                } label: {
                    HStack(spacing: 4) {
                        if locked { Image(systemName: "lock.fill").font(.caption2) }
                        Text(d.displayName)
                    }
                    .font(UITheme.font(.subheadline, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(selection == d ? .white : UITheme.ink)
                    .background(selection == d ? AnyShapeStyle(UITheme.lineColor(2)) : AnyShapeStyle(Color.clear), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .opacity(locked ? 0.45 : 1)
                .help(locked ? tr("Finish campaign level \(PlayerProgress.hardAfterLevel) to unlock Hard") : d.summary)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
    }
}

private struct MapCard: View {
    let preset: MapPreset
    let isRandom: Bool
    /// Set when the map is still locked.
    let unlockHint: String?
    let best: Int?
    let onReroll: () -> Void
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPick) {
                MapPreview(map: MapGenerator.generate(archetype: preset.archetype, seed: preset.seed, name: preset.name))
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.08)))
                    .overlay {
                        if let unlockHint {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                                Label(unlockHint, systemImage: "lock.fill")
                                    .font(UITheme.font(.caption, weight: .semibold))
                                    .foregroundStyle(UITheme.ink)
                                    .padding(8)
                            }
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(unlockHint != nil)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).font(UITheme.font(.headline)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(subtitle).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                if isRandom, unlockHint == nil {
                    Button(action: onReroll) { Image(systemName: "dice") }
                        .buttonStyle(.borderless)
                        .help(tr("New random city"))
                }
                Button("Play", action: onPick)
                    .buttonStyle(.borderedProminent)
                    .tint(UITheme.lineColor(2))
                    .disabled(unlockHint != nil)
            }
            .foregroundStyle(UITheme.ink)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var subtitle: String {
        let kind = isRandom ? tr("Random · \(preset.archetype.displayName)") : preset.archetype.displayName
        return best.map { tr("\(kind) · best \($0)") } ?? kind
    }
}

/// Small top-down render of a map's geography (SwiftUI Canvas, no SpriteKit).
struct MapPreview: View {
    let map: MapDefinition

    var body: some View {
        Canvas { context, size in
            let scale = max(size.width / map.size.x, size.height / map.size.y)
            let offset = CGPoint(x: (size.width - map.size.x * scale) / 2, y: (size.height - map.size.y * scale) / 2)
            func pt(_ v: Vec2) -> CGPoint { CGPoint(x: offset.x + v.x * scale, y: size.height - (offset.y + v.y * scale)) }
            func path(_ polygon: MetroCore.Polygon) -> Path {
                var p = Path()
                p.addLines(polygon.points.map(pt))
                p.closeSubpath()
                return p
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(VisualTheme.land.color))
            for park in map.parks { context.fill(path(park), with: .color(VisualTheme.park.color)) }
            for water in map.water {
                context.fill(path(water), with: .color(VisualTheme.water.color))
                context.stroke(path(water), with: .color(VisualTheme.waterEdge.color), lineWidth: 1)
            }
            let c = pt(map.cityCenter)
            let r = 300 * scale
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(UITheme.ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }
}
