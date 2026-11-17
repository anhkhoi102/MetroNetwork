import SwiftUI
import MetroCore

/// Top bar: city + clock + stations, line slots, and time/camera controls. Only essentials.
struct HUDView: View {
    let controller: GameSessionController
    let onExit: () -> Void

    private var hud: GameSessionController.HUDSnapshot { controller.hud }

    var body: some View {
        // One row when it fits; on narrower screens (iPad in portrait) the line slots move to a second row.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                statusPanel
                Spacer(minLength: 0)
                linesPanel
                Spacer(minLength: 0)
                controlsPanel
            }
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    statusPanel
                    Spacer(minLength: 0)
                    controlsPanel
                }
                linesPanel
            }
        }
        .overlay(alignment: .topTrailing) {
            if hud.isPaused, !controller.isDepotOpen, controller.result == nil {
                Text("PAUSED")
                    .font(UITheme.font(.caption).weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(UITheme.ink.opacity(0.8), in: Capsule())
                    .padding(.trailing, 12)
                    .offset(y: UITheme.isCompact ? 50 : 62)
                    .allowsHitTesting(false)
            }
        }
    }

    private var statusPanel: some View {
    Panel {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                if UITheme.isCompact {
                    // Phone: the week is what matters; the city name would crowd the bar.
                    Text(weekText).font(UITheme.font(.subheadline).weight(.bold))
                    Text(Self.days[min(6, max(0, hud.day))]).font(UITheme.font(.caption))
                        .foregroundStyle(UITheme.secondaryInk)
                } else {
                    Text(controller.preset.name)
                        .font(UITheme.font(.subheadline).weight(.bold))
                    Text(clock).font(UITheme.font(.caption).monospacedDigit()).foregroundStyle(UITheme.secondaryInk)
                }
            }
            .fixedSize()
            Divider().frame(height: 26)
            HStack(spacing: UITheme.isCompact ? 8 : 12) {
                Label("\(hud.score)", systemImage: "star.fill")
                    .help(tr("Score"))
                Label("\(hud.delivered)", systemImage: "figure.walk.arrival")
                    .help(tr("Passengers transported"))
                if !UITheme.isCompact {
                    Label("\(hud.stationCount)", systemImage: "mappin.circle.fill")
                        .help(tr("Stations"))
                }
            }
            .font(UITheme.font(.subheadline).weight(.semibold).monospacedDigit())
            .labelStyle(CompactLabelStyle())
            .fixedSize()
        }
        .foregroundStyle(UITheme.ink)
    }

    }

    private var linesPanel: some View {
    Panel {
        HStack(spacing: UITheme.isCompact ? 5 : 8) {
            ForEach(hud.slots) { slot in
                LineSlotButton(slot: slot, isSelected: isSelected(slot)) {
                    if let id = slot.lineID {
                        isSelected(slot) ? controller.clearSelection() : controller.select(.line(id))
                    } else if slot.locked {
                        controller.openDepot()
                    }
                }
            }
            Divider().frame(height: 22)
            HStack(spacing: UITheme.isCompact ? 8 : 10) {
                Label("\(hud.resources.locomotives)", systemImage: "tram.fill")
                    .help(tr("Spare trains"))
                    .accessibilityLabel(tr("\(hud.resources.locomotives) spare trains"))
                Label("\(hud.crossingsFree)", systemImage: "tram.fill.tunnel")
                    .help(tr("Free tunnels (for crossing water)"))
                    .accessibilityLabel(tr("\(hud.crossingsFree) free tunnels"))
            }
            .font(UITheme.font(.subheadline).weight(.semibold).monospacedDigit())
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(UITheme.ink)
            .fixedSize()
        }
    }

    }

    private var controlsPanel: some View {
    Panel {
        HStack(spacing: UITheme.isCompact ? 8 : 14) {
            DepotButton(credits: hud.resources.credits, isOpen: controller.isDepotOpen,
                        action: controller.toggleDepot)
            HUDButton(icon: hud.isPaused ? "play.fill" : "pause.fill",
                      help: hud.isPaused ? "Resume (Space)" : "Pause (Space)",
                      action: { Feedback.play(.toggle); controller.togglePause() })
                .disabled(controller.result != nil)
            Button(action: controller.cycleSpeed) {
                Text(hud.speed == 1 ? "1×" : "\(Int(hud.speed))×")
                    .font(UITheme.font(.subheadline).weight(.bold))
                    .frame(minWidth: 26, minHeight: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("Game speed (Tab)"))
            HUDButton(icon: "arrow.up.left.and.down.right.magnifyingglass", help: "Fit city (F)",
                      action: controller.fitCity)
            HUDButton(icon: "xmark", help: "Leave city", action: onExit)
        }
        .foregroundStyle(UITheme.ink)
    }
    }

    private static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var weekText: String {
        hud.weekLimit.map { tr("Week \(min(hud.week, $0))/\($0)") } ?? tr("Week \(hud.week)")
    }

    private var clock: String {
        "\(weekText) · \(translated(Self.days[min(6, max(0, hud.day))]))"
    }

    private func isSelected(_ slot: GameSessionController.LineSlot) -> Bool {
        guard let id = slot.lineID else { return false }
        return controller.selection == .line(id)
    }
}

private struct LineSlotButton: View {
    let slot: GameSessionController.LineSlot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let color = UITheme.lineColor(slot.colorIndex)
        let size: CGFloat = UITheme.isCompact ? (slot.locked ? 15 : 19) : (slot.locked ? 20 : 24)
        Button(action: action) {
            ZStack {
                if slot.lineID != nil {
                    Circle().fill(color)
                    if isSelected { Circle().strokeBorder(.white, lineWidth: 3) }
                } else if slot.locked {
                    Circle().fill(UITheme.ink.opacity(0.08))
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(UITheme.ink.opacity(0.35))
                } else {
                    Circle().strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 3, dash: [3, 3]))
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(isSelected ? 1.15 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(slot.lineID == nil && !slot.locked)
        .help(slot.locked ? "Locked line: buy it in the depot"
              : slot.lineID == nil ? "Free line: drag between stations to use it" : VisualTheme.lineName(slot.colorIndex))
    }
}

/// Opens the depot; shows the credits available to spend.
private struct DepotButton: View {
    let credits: Int
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "ticket.fill")
                Text("\(credits)").monospacedDigit()
            }
            .font(UITheme.font(.subheadline).weight(.bold))
            .foregroundStyle(credits > 0 ? .white : UITheme.ink)
            .padding(.horizontal, 9)
            .frame(minHeight: 26)
            .fixedSize()                       // never squeezed: the credit count must stay visible
            .background(credits > 0 ? AnyShapeStyle(UITheme.lineColor(2)) : AnyShapeStyle(UITheme.ink.opacity(isOpen ? 0.15 : 0.08)),
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("Depot: spend credits on trains, lines and upgrades (D)"))
        .accessibilityLabel(tr("Depot, \(credits) credits"))
    }
}

private struct HUDButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Icon + value with tight spacing.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(UITheme.secondaryInk)
            configuration.title
        }
    }
}
