import SwiftUI
import MetroCore

/// Shown when a station is selected: its lines, with a way to take it off each one.
struct StationCard: View {
    let controller: GameSessionController
    let station: Station
    let lines: [MetroLine]

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: tr("\(station.shape.displayName) station"),
                           subtitle: (lines.isEmpty ? "Not connected yet" : tr("\(lines.count) line\(lines.count == 1 ? "" : "s")"))
                               + tr(" · \(station.waiting.count) waiting"),
                           onClose: controller.clearSelection) {
                    StationShapeIcon(shape: station.shape, size: 28)
                }
                character
                crowding
                if !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines) { line in
                            HStack(spacing: 8) {
                                Capsule().fill(UITheme.lineColor(line.colorIndex)).frame(width: 22, height: 8)
                                Button(VisualTheme.lineName(line.colorIndex)) { controller.select(.line(line.id)) }
                                    .buttonStyle(.plain)
                                    .font(UITheme.font(.subheadline).weight(.semibold))
                                Spacer(minLength: 12)
                                Button {
                                    controller.remove(station.id, from: line.id)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                        .font(UITheme.font(.caption).weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .tint(.red)
                                .help(tr("Take this station off the \(VisualTheme.lineName(line.colorIndex))"))
                            }
                        }
                    }
                }
            }
            .frame(width: UITheme.isCompact ? 270 : 300)
        }
    }
}

extension StationCard {
    private var config: GameConfiguration { controller.engine.state.config }

    /// Special role, how busy it is, and any event affecting it.
    @ViewBuilder
    private var character: some View {
        let state = controller.engine.state
        VStack(alignment: .leading, spacing: 4) {
            if let special = station.special {
                Label {
                    Text(special.displayName).font(UITheme.font(.caption, weight: .bold))
                    + Text(" · " + Self.describe(special, config)).font(UITheme.font(.caption))
                } icon: {
                    Image(systemName: VisualTheme.specialSymbol(special)).foregroundStyle(VisualTheme.specialColor(special).color)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Label(busyness, systemImage: "person.2.fill")
                Label(station.centrality > 0.6 ? "Central" : station.centrality > 0.25 ? "Inner suburbs" : "Outskirts",
                      systemImage: "location.fill")
            }
            .font(UITheme.font(.caption))
            .foregroundStyle(UITheme.secondaryInk)
            if state.isClosed(station.id) {
                Label("Closed: trains run through", systemImage: "xmark.octagon.fill")
                    .font(UITheme.font(.caption, weight: .bold)).foregroundStyle(VisualTheme.danger.color)
            }
        }
    }

    private var busyness: String {
        var demand = station.demand * (station.special == .hub ? config.hubDemandMultiplier : 1)
        demand = (demand * 10).rounded() / 10
        return demand >= 1.5 ? tr("Very busy ×\(demand.formatted())") : demand >= 1.1 ? tr("Busy ×\(demand.formatted())")
            : demand <= 0.9 ? tr("Quiet ×\(demand.formatted())") : "Normal demand"
    }

    static func describe(_ special: SpecialStation, _ config: GameConfiguration) -> String {
        switch special {
        case .hub: "many more passengers, a little more room"
        case .interchange: "changing trains here is much quicker"
        case .heritage: "at most \(config.heritageMaxLines) lines may stop here"
        case .grand: "lots of room, can't be expanded"
        }
    }

    /// Queue against capacity, the overcrowding timer, and the expand button.
    private var crowding: some View {
        let capacity = station.capacity(config)
        let fraction = min(1, Double(station.waiting.count) / Double(max(1, capacity)))
        let tint = station.overcrowding > 0
            ? VisualTheme.warning.mixed(with: VisualTheme.danger, min(1, station.overcrowding * 1.5)).color
            : UITheme.lineColor(3)
        let spare = controller.hud.resources.expansions
        let maxed = !station.canExpand(config)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("\(station.waiting.count)/\(capacity) waiting"))
                    .font(UITheme.font(.subheadline, weight: .semibold).monospacedDigit())
                if station.overcrowding > 0 {
                    Label("Overcrowded", systemImage: "exclamationmark.triangle.fill")
                        .font(UITheme.font(.caption, weight: .bold))
                        .foregroundStyle(tint)
                }
                Spacer()
                Button {
                    controller.expand(station.id)
                } label: {
                    Label(station.special == .grand ? "Can't expand" : maxed ? "Fully expanded" : tr("Expand (\(spare))"),
                          systemImage: "building.2.fill")
                        .font(UITheme.font(.caption, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(maxed || spare == 0)
                .help(maxed ? "This station can't grow any more"
                      : tr("Use a spare expansion: +\(config.expansionCapacity) room here (\(spare) spare)"))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(UITheme.ink.opacity(0.1))
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                    if station.overcrowding > 0 {
                        // Timer marker: how close this station is to ending the game.
                        Capsule().fill(VisualTheme.danger.color)
                            .frame(width: geo.size.width * station.overcrowding, height: 2)
                            .offset(y: 5)
                    }
                }
            }
            .frame(height: 6)
        }
        .foregroundStyle(UITheme.ink)
    }
}

/// Shown when a line is selected: colour, stops, loop and delete.
struct LineCard: View {
    let controller: GameSessionController
    let line: MetroLine
    let stations: [Station]
    let trains: Int

    private var maxTrains: Int { controller.engine.state.config.maxTrainsPerLine }
    private var spareTrains: Int { controller.hud.resources.locomotives }
    private var allowsExpress: Bool { controller.engine.state.config.allowExpress }
    private var swatchSize: CGFloat { UITheme.isCompact ? 18 : 22 }

    var body: some View {
        Panel {
            if UITheme.isCompact {
                // Landscape phone: two short columns instead of one tall card, so the map stays visible.
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        swatches
                        stops
                    }
                    .frame(width: 230)
                    VStack(alignment: .trailing, spacing: 8) {
                        trainsRow
                        if allowsExpress { expressRow }
                        Spacer(minLength: 0)
                        actions
                    }
                    .frame(width: 170)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    swatches
                    stops
                    trainsRow
                    if allowsExpress { expressRow }
                    actions
                }
                .frame(width: 320)
            }
        }
    }

    private var header: some View {
        CardHeader(title: VisualTheme.lineName(line.colorIndex),
                   subtitle: tr("\(stations.count) stops\(line.isLoop ? " · loop" : "")"),
                   onClose: controller.clearSelection) {
            Capsule().fill(UITheme.lineColor(line.colorIndex)).frame(width: 28, height: 10)
        }
    }

    /// Colour swatches: picking a colour used by another line swaps them.
    private var swatches: some View {
        HStack(spacing: UITheme.isCompact ? 5 : 6) {
            ForEach(0..<controller.engine.state.config.lineColorCount, id: \.self) { index in
                Button {
                    controller.setColor(index, for: line.id)
                } label: {
                    Circle()
                        .fill(UITheme.lineColor(index))
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay(Circle().strokeBorder(.white, lineWidth: index == line.colorIndex ? 3 : 0))
                        .overlay(Circle().strokeBorder(UITheme.ink.opacity(index == line.colorIndex ? 0.5 : 0), lineWidth: 1))
                        .contentShape(Circle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .help(VisualTheme.lineColor(index).name)
            }
        }
    }

    /// Stops in order; tap one to remove it from the line.
    private var stops: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    if index > 0 {
                        Rectangle().fill(UITheme.lineColor(line.colorIndex)).frame(width: 10, height: 4)
                    }
                    Button {
                        controller.remove(station.id, from: line.id)
                    } label: {
                        StationShapeIcon(shape: station.shape, size: swatchSize, lineWidth: 2)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.red)
                                    .offset(x: 4, y: -4)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tr("Remove this stop"))
                }
                if line.isLoop {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(UITheme.lineColor(line.colorIndex))
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Trains on this line.
    private var trainsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "tram.fill").foregroundStyle(UITheme.lineColor(line.colorIndex))
            Text(UITheme.isCompact ? "\(trains)/\(maxTrains)" : tr("\(trains)/\(maxTrains) trains · \(spareTrains) spare"))
                .font(UITheme.font(.subheadline).weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(tr("\(trains) of \(maxTrains) trains"))
            Spacer(minLength: 4)
            Button { controller.removeTrain(from: line.id) } label: { Image(systemName: "minus") }
                .disabled(trains == 0)
                .help(tr("Withdraw a train"))
            Button { controller.addTrain(to: line.id) } label: { Image(systemName: "plus") }
                .disabled(trains >= maxTrains || spareTrains == 0)
                .help(spareTrains == 0 ? "No spare trains: buy one in the depot" : tr("Add a spare train (\(spareTrains) left)"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Express service toggle.
    private var expressRow: some View {
        let state = controller.engine.state
        let stops = StopRules.expressStops(of: line, in: state).count
        let applies = stops >= 2 && stops < line.stations.count
        return Toggle(isOn: Binding(get: { line.isExpress }, set: { Feedback.play(.toggle); controller.setExpress(line.id, $0) })) {
            VStack(alignment: .leading, spacing: 0) {
                Label("Express", systemImage: "forward.fill").font(UITheme.font(.subheadline, weight: .semibold))
                Text(!applies ? "Needs a stop it can skip"
                     : UITheme.isCompact ? tr("Stops at \(stops) of \(line.stations.count)")
                     : tr("Stops at \(stops) of \(line.stations.count): ends, interchanges, specials"))
                    .font(UITheme.font(.caption2)).foregroundStyle(UITheme.secondaryInk)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(tr("Express trains run through ordinary stations without stopping: faster trips, but those stations lose this line's service."))
    }

    private var actions: some View {
        HStack {
            if line.isLoop {
                Button {
                    controller.openLoop(line.id)
                } label: {
                    Label("Open loop", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                controller.deleteLine(line.id)
            } label: {
                Label("Delete line", systemImage: "trash")
            }
            .help(tr("Delete line (⌫)"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Shown when a train is selected: its line, load and next stop.
struct TrainCard: View {
    let controller: GameSessionController
    let train: Train
    let line: MetroLine
    let nextStop: Station?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: tr("Train · \(VisualTheme.lineName(line.colorIndex))"),
                           subtitle: status, onClose: controller.clearSelection) {
                    Image(systemName: "tram.fill")
                        .font(.title2)
                        .foregroundStyle(UITheme.lineColor(line.colorIndex))
                }
                let roomy = train.capacity <= 8
                HStack(spacing: roomy ? 6 : 2) {
                    Text("\(train.passengers.count)/\(train.capacity)")
                        .font(UITheme.font(.subheadline).weight(.semibold).monospacedDigit())
                        .padding(.trailing, roomy ? 0 : 4)
                    ForEach(Array(train.passengers.enumerated()), id: \.element.id) { _, p in
                        StationShapeIcon(shape: p.destination, size: roomy ? 16 : 14, lineWidth: 1.5)
                    }
                    ForEach(0..<train.freeSeats, id: \.self) { _ in
                        Circle().strokeBorder(UITheme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                            .frame(width: roomy ? 13 : 11, height: roomy ? 13 : 11)
                            .frame(width: roomy ? 13 : 14)
                    }
                }
                upgrades
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        controller.withdraw(train.id)
                    } label: {
                        Label("Withdraw", systemImage: "arrow.uturn.left")
                    }
                    .help(tr("The train finishes its trip, lets everyone off, then leaves the line"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(width: UITheme.isCompact ? 300 : 320)
        }
    }

    private var config: GameConfiguration { controller.engine.state.config }

    /// Carriages and motor: fitted from (and returned to) stock.
    private var upgrades: some View {
        let r = controller.hud.resources
        let sells = config.availablePurchases
        return VStack(alignment: .leading, spacing: 6) {
            if sells.contains(.carriage) || train.carriages > 0 || r.carriages > 0 {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1.fill").foregroundStyle(UITheme.secondaryInk)
                Text(tr("Carriages \(train.carriages)/\(config.maxCarriagesPerTrain)"))
                    .font(UITheme.font(.subheadline, weight: .semibold).monospacedDigit())
                Text(tr("\(r.carriages) spare")).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                Spacer(minLength: 4)
                Button { controller.detachCarriage(train.id) } label: { Image(systemName: "minus") }
                    .disabled(train.carriages == 0)
                    .help(tr("Uncouple a carriage back into stock"))
                Button { controller.attachCarriage(train.id) } label: { Image(systemName: "plus") }
                    .disabled(train.carriages >= config.maxCarriagesPerTrain || r.carriages == 0)
                    .help(tr("+\(config.carriageCapacity) seats; the train speeds up a little more slowly"))
            }
            }
            if sells.contains(.motor) || train.hasMotor || r.motors > 0 {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(train.hasMotor ? VisualTheme.delivered.color : UITheme.secondaryInk)
                Text(train.hasMotor ? "Fast motor" : "Standard motor")
                    .font(UITheme.font(.subheadline, weight: .semibold))
                Text(tr("\(r.motors) spare")).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
                Spacer(minLength: 4)
                if train.hasMotor {
                    Button("Remove") { controller.removeMotor(train.id) }
                        .help(tr("Take the fast motor off, back into stock"))
                } else {
                    Button("Fit") { controller.fitMotor(train.id) }
                        .disabled(r.motors == 0)
                        .help(tr("Runs \(Int(((config.motorSpeedFactor - 1) * 100).rounded()))% faster"))
                }
            }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .foregroundStyle(UITheme.ink)
    }

    private var status: String {
        let stop = nextStop.map { tr("\($0.shape.displayName.lowercased()) station") } ?? "next station"
        if let until = train.maintenanceUntil {
            let left = max(0, Int((until - controller.engine.state.elapsed).rounded(.up)))
            return tr("In maintenance · back in \(left)s")
        }
        return train.isDwelling ? tr("Stopped at \(stop)") : tr("Heading to \(stop)")
    }
}

private struct CardHeader<Icon: View>: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(UITheme.font(.headline))
                Text(subtitle).font(UITheme.font(.caption)).foregroundStyle(UITheme.secondaryInk)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(tr("Close (Esc)"))
        }
        .foregroundStyle(UITheme.ink)
    }
}
