import SwiftUI
import MetroCore

/// The depot: spend weekly credits on trains, carriages, lines, tunnels, station expansions and motors.
/// Opens by itself at the start of every week (the game pauses while it's open).
struct DepotView: View {
    let controller: GameSessionController

    private var hud: GameSessionController.HUDSnapshot { controller.hud }
    private var config: GameConfiguration { controller.engine.state.config }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: controller.closeDepot)
            Panel {
                VStack(alignment: .leading, spacing: UITheme.isCompact ? 8 : 12) {
                    header
                    if config.availablePurchases.isEmpty {
                        Label("The depot is closed in this challenge.", systemImage: "lock.fill")
                            .font(UITheme.font(.subheadline))
                            .foregroundStyle(UITheme.secondaryInk)
                    }
                    // Phone: three short tiles per row (no descriptions) so all six fit without scrolling.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                             count: UITheme.isCompact ? 3 : 2),
                              spacing: UITheme.isCompact ? 8 : 10) {
                        ForEach(config.availablePurchases, id: \.self) { item in
                            DepotItemView(item: item, info: info(item), price: config.price(of: item),
                                          canBuy: canBuy(item)) { controller.buy(item) }
                        }
                    }
                    HStack {
                        Text(UITheme.isCompact ? "Use spare items from line, train and station cards."
                             : "Spare items wait in stock until you use them from a line, train or station card.")
                            .font(UITheme.font(.caption))
                            .foregroundStyle(UITheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button(action: controller.closeDepot) {
                            Text(controller.depotGrant == nil ? "Close" : tr("Start week \(hud.week)"))
                                .font(UITheme.font(.subheadline).weight(.bold))
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(UITheme.lineColor(2))
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(UITheme.isCompact ? 0 : 6)
                .frame(width: UITheme.isCompact ? 600 : 560)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.depotGrant.map { tr("Week \($0.week)") } ?? "Depot")
                    .font(UITheme.font(UITheme.isCompact ? .headline : .title2, weight: .heavy))
                if let grant = controller.depotGrant {
                    Text(grantText(grant))
                        .font(UITheme.font(UITheme.isCompact ? .caption : .subheadline))
                        .foregroundStyle(UITheme.secondaryInk)
                    if let rush = rushText {
                        Label(rush, systemImage: "clock.badge.exclamationmark")
                            .font(UITheme.font(.caption, weight: .semibold))
                            .foregroundStyle(VisualTheme.warning.darkened(0.15).color)
                    }
                } else {
                    Text("Spend credits on your network. More arrive every week.")
                        .font(UITheme.font(UITheme.isCompact ? .caption : .subheadline))
                        .foregroundStyle(UITheme.secondaryInk)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                Text("\(hud.resources.credits)").monospacedDigit()
            }
            .font(UITheme.font(UITheme.isCompact ? .headline : .title3, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, UITheme.isCompact ? 3 : 5)
            .background(UITheme.lineColor(2), in: Capsule())
            .accessibilityLabel(tr("\(hud.resources.credits) credits"))
        }
        .foregroundStyle(UITheme.ink)
    }

    /// "Rush hours this week: Tue morning (homes → centre), Thu evening (centre → homes)".
    private var rushText: String? {
        let state = controller.engine.state
        let day = state.config.weekLength / 7
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let items = state.rushHours.filter { $0.end > state.elapsed }.map { r in
            "\(names[Int(r.start / day) % 7]) " + (r.flow == .toCentre ? "morning (homes → centre)" : "evening (centre → homes)")
        }
        return items.isEmpty ? nil : tr("Rush hours this week: ") + items.joined(separator: ", ")
    }

    private func grantText(_ grant: WeeklyGrant) -> String {
        var text = tr("+\(grant.base) credits")
        if grant.performance > 0 {
            text += tr(", +\(grant.performance) for \(grant.delivered) passengers last week")
        } else {
            text += tr(" (deliver \(config.deliveriesPerBonusCredit)+ a week for bonus credits)")
        }
        return text
    }

    private func canBuy(_ item: Purchase) -> Bool {
        guard hud.resources.credits >= config.price(of: item) else { return false }
        return item != .line || hud.resources.lineSlots < config.maxLines
    }

    /// Name, effect and how many the player owns.
    private func info(_ item: Purchase) -> DepotItemView.Info {
        let r = hud.resources
        switch item {
        case .locomotive:
            return .init(title: "Train", detail: "Runs on any line. More trains, shorter waits.",
                         icon: "tram.fill", owned: tr("\(r.locomotives) spare"))
        case .carriage:
            return .init(title: "Carriage", detail: tr("+\(config.carriageCapacity) seats on one train, but slower to speed up."),
                         icon: "rectangle.split.2x1.fill", owned: tr("\(r.carriages) spare"))
        case .line:
            let full = r.lineSlots >= config.maxLines
            return .init(title: "New line", detail: full ? "You have every line." : "One more line colour to build with.",
                         icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                         owned: tr("\(r.lineSlots)/\(config.maxLines) lines"))
        case .crossings:
            return .init(title: tr("Tunnels ×\(config.crossingsPerPurchase)"), detail: "Each line segment over water uses one.",
                         icon: "tram.fill.tunnel", owned: tr("\(hud.crossingsFree) free"))
        case .expansion:
            return .init(title: "Station expansion",
                         detail: tr("+\(config.expansionCapacity) room at one station before it overcrowds."),
                         icon: "building.2.fill", owned: tr("\(r.expansions) spare"))
        case .motor:
            return .init(title: "Fast motor",
                         detail: tr("One train runs \(Int(((config.motorSpeedFactor - 1) * 100).rounded()))% faster."),
                         icon: "bolt.fill", owned: tr("\(r.motors) spare"))
        }
    }
}

private struct DepotItemView: View {
    struct Info {
        let title: String
        let detail: String
        let icon: String
        let owned: String
    }

    let item: Purchase
    let info: Info
    let price: Int
    let canBuy: Bool
    let buy: () -> Void

    var body: some View {
        if UITheme.isCompact { compact } else { regular }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: info.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(UITheme.lineColor(2))
                    .frame(width: 24, height: 24)
                    .background(UITheme.lineColor(2).opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(info.title).font(UITheme.font(.caption, weight: .bold)).lineLimit(1)
                    Text(info.owned).font(UITheme.font(.caption2)).foregroundStyle(UITheme.secondaryInk).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            buyButton
        }
        .foregroundStyle(UITheme.ink)
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHint(info.detail)
    }

    private var buyButton: some View {
        Button(action: buy) {
            HStack(spacing: 4) {
                Text("Buy")
                Image(systemName: "ticket.fill").font(.caption2)
                Text("\(price)").monospacedDigit()
            }
            .font(UITheme.font(.caption, weight: .bold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!canBuy)
        .accessibilityLabel(tr("Buy \(info.title) for \(price) credits"))
    }

    private var regular: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: info.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(UITheme.lineColor(2))
                .frame(width: 34, height: 34)
                .background(UITheme.lineColor(2).opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(info.title).font(UITheme.font(.subheadline, weight: .bold))
                    Spacer(minLength: 4)
                    Text(info.owned).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                }
                Text(info.detail)
                    .font(UITheme.font(.caption))
                    .foregroundStyle(UITheme.secondaryInk)
                    .lineLimit(2, reservesSpace: !UITheme.isCompact)
                    .fixedSize(horizontal: false, vertical: true)
                buyButton
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(UITheme.ink)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
