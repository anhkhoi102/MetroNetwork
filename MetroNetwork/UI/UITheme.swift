import SwiftUI
import MetroCore

@MainActor
enum UITheme {
    static var background: Color { VisualTheme.land.color }
    static var ink: Color { VisualTheme.ink.color }
    static var secondaryInk: Color { VisualTheme.ink.color.opacity(0.6) }
    static let accent = VisualTheme.selection.color

    static func lineColor(_ index: Int) -> Color { VisualTheme.lineColor(index).rgb.color }

    // MARK: Typography (Outfit; scales with Dynamic Type through `relativeTo`)

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let size: CGFloat = switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
        let w: Font.Weight = (style == .headline && weight == .regular) ? .semibold : weight
        // Outfit has no Vietnamese letters (ơ, ư, ạ…): in Vietnamese use the rounded system font, which has them all.
        if L10n.shared.isVietnamese { return .system(style, design: .rounded).weight(w) }
        return .custom(AppFonts.family, size: size, relativeTo: style).weight(w)
    }

    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        if L10n.shared.isVietnamese { return .system(size: size, weight: weight, design: .rounded) }
        return .custom(AppFonts.family, fixedSize: size).weight(weight)
    }

    #if os(iOS)
    static var isCompact: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    #else
    static let isCompact = false
    #endif
}

/// A station symbol drawn with the same paths as the map.
struct StationShapeIcon: View {
    let shape: StationShape
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2.5

    var body: some View {
        let path = Path(ShapePaths.path(for: shape, radius: size * 0.36))
        Canvas { context, canvasSize in
            // Paths are Y-up; flip into SwiftUI's Y-down space, centred.
            let transform = CGAffineTransform(translationX: canvasSize.width / 2, y: canvasSize.height / 2)
                .scaledBy(x: 1, y: -1)
            let p = path.applying(transform)
            context.fill(p, with: .color(.white))
            context.stroke(p, with: .color(UITheme.ink), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(shape.displayName)
    }
}

/// Rounded material panel used across the HUD.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
