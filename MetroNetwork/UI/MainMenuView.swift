import SwiftUI
import MetroCore

struct MainMenuView: View {
    let saved: SavedSession?
    let onContinue: () -> Void
    let onEndless: () -> Void
    let onCampaign: () -> Void
    let onChallenges: () -> Void
    let onStatistics: () -> Void
    let onSettings: () -> Void

    private var progress: PlayerProgress { ProgressStore.shared.progress }
    /// Buttons appear one after another when the menu opens.
    @State private var appeared = false

    var body: some View {
        ZStack {
            UITheme.background.ignoresSafeArea()
            MenuBackdrop().ignoresSafeArea().opacity(0.9)
            // Calm area behind the title and buttons.
            RadialGradient(colors: [UITheme.background, UITheme.background.opacity(0.85), UITheme.background.opacity(0)],
                           center: .center, startRadius: 0, endRadius: UITheme.isCompact ? 420 : 560)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: UITheme.isCompact ? 14 : 24) {
                VStack(spacing: 6) {
                    HStack(spacing: UITheme.isCompact ? 12 : 18) {
                        Image("Logo")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: UITheme.isCompact ? 56 : 84, height: UITheme.isCompact ? 56 : 84)
                            .accessibilityHidden(true)
                        Text("Metro Network")
                        .font(UITheme.font(size: UITheme.isCompact ? 40 : 56, weight: .heavy))
                        .foregroundStyle(UITheme.ink)
                    }
                    Text("Plan it. Build it. Keep the city moving.")
                        .font(UITheme.font(UITheme.isCompact ? .body : .title3))
                        .foregroundStyle(UITheme.secondaryInk)
                }
                .padding(.bottom, UITheme.isCompact ? 4 : 12)
                .scaleEffect(appeared ? 1 : 0.96)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: UITheme.isCompact ? 8 : 10) {
                    if let saved {
                        MenuButton(title: "Continue", subtitle: tr("\(saved.mode.localizedName) · week \(saved.state.week)"),
                                   icon: "play.fill", color: UITheme.ink, action: onContinue)
                            .keyboardShortcut(.defaultAction)
                    }
                    // Landscape phones are short: pair the entries side by side there.
                    if UITheme.isCompact {
                        HStack(spacing: 8) { campaign; endless }
                        HStack(spacing: 8) {
                            challenges.environment(\.denseMenu, true)
                            statistics.environment(\.denseMenu, true)
                            settings.environment(\.denseMenu, true)
                        }
                    } else {
                        campaign
                        endless
                        challenges
                        HStack(spacing: 10) { statistics; settings }
                    }
                }
                .frame(maxWidth: UITheme.isCompact ? 520 : 420)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
            }
            .padding(UITheme.isCompact ? 12 : 24)
        }
        .overlay(alignment: .topTrailing) {
            LanguageSwitch()
                .padding(UITheme.isCompact ? 12 : 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.05)) { appeared = true }
            AudioManager.shared.setMusicIntensity(0)
            AudioManager.shared.setMusicDucked(false)
        }
    }

    private var campaign: some View {
        let stars = progress.campaignStars
        let total = CampaignManager.levels.count * 3
        return MenuButton(title: "Campaign", subtitle: stars == 0 ? "8 cities, one idea each" : tr("\(stars)/\(total) stars"),
                          icon: "map", color: UITheme.lineColor(0), action: onCampaign)
    }

    private var endless: some View {
        MenuButton(title: "Endless", subtitle: "How long can your network last?", icon: "infinity",
                   color: UITheme.lineColor(2), action: onEndless)
    }

    private var challenges: some View {
        let unlocked = ChallengeManager.challenges.filter { progress.isChallengeUnlocked($0.id) }.count
        return MenuButton(title: "Challenges", subtitle: unlocked == 0 ? "Unlock in the campaign" : tr("\(unlocked) open"),
                          icon: "flag.checkered", color: UITheme.lineColor(3), action: onChallenges)
    }

    private var statistics: some View {
        MenuButton(title: "Statistics", subtitle: "Bests and totals", icon: "chart.bar", color: UITheme.lineColor(4),
                   action: onStatistics)
    }

    private var settings: some View {
        MenuButton(title: "Settings", subtitle: "Difficulty, progress", icon: "gearshape", color: UITheme.lineColor(6),
                   action: onSettings)
    }
}

private struct DenseMenuKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Phone menu rows with three buttons: title only.
    var denseMenu: Bool {
        get { self[DenseMenuKey.self] }
        set { self[DenseMenuKey.self] = newValue }
    }
}

private struct MenuButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var action: (() -> Void)?
    @Environment(\.denseMenu) private var dense

    var body: some View {
        Button {
            Feedback.play(.tap)
            action?()
        } label: {
            HStack(spacing: dense ? 8 : 12) {
                Image(systemName: icon)
                    .font(.system(size: dense ? 15 : 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: dense ? 30 : 38, height: dense ? 30 : 38)
                    .background(color, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(UITheme.font(.headline)).lineLimit(1).minimumScaleFactor(0.8)
                    if !dense {
                        Text(subtitle).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if action != nil, !dense {
                    Image(systemName: "chevron.right").foregroundStyle(UITheme.secondaryInk)
                }
            }
            .help(subtitle)
            .foregroundStyle(UITheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, UITheme.isCompact ? 6 : 10)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.55 : 1)
    }
}

/// Decorative transit-map strokes behind the menu.
private struct MenuBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // Street grid and a scatter of city blocks, like the game map.
            let cell: CGFloat = 64
            var grid = Path()
            var x: CGFloat = 0
            while x < w { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h)); x += cell }
            var y: CGFloat = 0
            while y < h { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y)); y += cell }
            context.stroke(grid, with: .color(VisualTheme.street.color), lineWidth: 1.5)
            var blocks = Path()
            for col in 0..<Int(w / cell) + 1 {
                // Integer hash, so the scatter looks irregular but never changes between launches.
                for row in 0..<Int(h / cell) + 1 where ((col &* 73_856_093) ^ (row &* 19_349_663)) % 7 < 2 {
                    blocks.addRoundedRect(in: CGRect(x: CGFloat(col) * cell + 6, y: CGFloat(row) * cell + 6,
                                                     width: cell - 12, height: cell - 12),
                                          cornerSize: CGSize(width: 4, height: 4))
                }
            }
            context.fill(blocks, with: .color(VisualTheme.block.color.opacity(0.75)))
            let routes: [(Int, [CGPoint])] = [
                (0, [CGPoint(x: -20, y: h * 0.08), CGPoint(x: w * 0.30, y: h * 0.08),
                     CGPoint(x: w * 0.38, y: h * 0.16), CGPoint(x: w + 20, y: h * 0.16)]),
                (2, [CGPoint(x: w * 0.12, y: -20), CGPoint(x: w * 0.12, y: h * 0.55),
                     CGPoint(x: w * 0.30, y: h * 0.73), CGPoint(x: w * 0.30, y: h + 20)]),
                (3, [CGPoint(x: -20, y: h * 0.84), CGPoint(x: w * 0.62, y: h * 0.84),
                     CGPoint(x: w * 0.80, y: h * 0.66), CGPoint(x: w * 0.80, y: -20)]),
                (1, [CGPoint(x: w * 0.92, y: h + 20), CGPoint(x: w * 0.92, y: h * 0.60),
                     CGPoint(x: w * 0.70, y: h * 0.38), CGPoint(x: w * 0.70, y: -20)]),
            ]
            for (color, points) in routes {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(UITheme.lineColor(color).opacity(0.35)),
                               style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            }
            for p in [CGPoint(x: w * 0.30, y: h * 0.08), CGPoint(x: w * 0.12, y: h * 0.55),
                      CGPoint(x: w * 0.62, y: h * 0.84), CGPoint(x: w * 0.92, y: h * 0.60),
                      CGPoint(x: w * 0.70, y: h * 0.16)] {
                let r: CGFloat = 13
                let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                context.fill(circle, with: .color(.white.opacity(0.8)))
                context.stroke(circle, with: .color(UITheme.ink.opacity(0.35)), lineWidth: 4)
            }
        }
        .allowsHitTesting(false)
    }
}

/// EN | VI: switches the whole interface at once (the choice is saved with the player's progress).
struct LanguageSwitch: View {
    private var l10n: L10n { L10n.shared }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Language.allCases) { language in
                let selected = l10n.language == language
                SwiftUI.Button {
                    Feedback.play(.toggle)
                    withAnimation(.easeOut(duration: 0.2)) { l10n.language = language }
                } label: {
                    SwiftUI.Text(verbatim: language.short)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? .white : UITheme.ink)
                        .frame(width: 38, height: 28)
                        .background(selected ? AnyShapeStyle(UITheme.lineColor(2)) : AnyShapeStyle(Color.clear), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(language.name)
                .accessibilityLabel(language.name)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.black.opacity(0.06)))
    }
}
