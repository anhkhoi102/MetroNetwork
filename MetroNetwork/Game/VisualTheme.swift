import SpriteKit
import SwiftUI
import MetroCore

/// An sRGB colour usable from both SpriteKit and SwiftUI.
struct RGB: Hashable, Sendable {
    let r: Double, g: Double, b: Double

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    var sk: SKColor { SKColor(red: r, green: g, blue: b, alpha: 1) }

    /// The same hue, `amount` (0…1) darker.
    func darkened(_ amount: Double) -> RGB { RGB(r: r * (1 - amount), g: g * (1 - amount), b: b * (1 - amount)) }
    /// Linear blend towards `other` (t = 0 → self, 1 → other).
    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
    func sk(alpha: Double) -> SKColor { SKColor(red: r, green: g, blue: b, alpha: alpha) }
    var color: Color { Color(red: r, green: g, blue: b) }
}

/// One visual theme: map, line and station colours. Gameplay never reads these.
struct ThemePalette: Sendable {
    let id: String
    let name: String
    let lines: [RGB]
    let outside, land, street, block, blockEdge, park, parkEdge, tree, water, waterEdge, ripple, shore: RGB
    let stationFill, stationStroke, ink: RGB

    static let metropolitan = ThemePalette(
        id: "metropolitan", name: "Metropolitan",
        lines: [0xE5484D, 0xF0A020, 0x2F80ED, 0x1FA067, 0x8E5BD8, 0xE8579C, 0x12A2A8].map(RGB.init(hex:)),
        outside: RGB(hex: 0xE2DCCD), land: RGB(hex: 0xF5F2EA), street: RGB(hex: 0xE8E2D4), block: RGB(hex: 0xECE6DA),
        blockEdge: RGB(hex: 0xE2DBCC), park: RGB(hex: 0xD3E8C6), parkEdge: RGB(hex: 0xB9D8A8), tree: RGB(hex: 0xBCDAA9),
        water: RGB(hex: 0xA8D3EE), waterEdge: RGB(hex: 0x86BEE2), ripple: RGB(hex: 0xC3E2F4), shore: RGB(hex: 0xE3F0F2),
        stationFill: RGB(hex: 0xFFFFFF), stationStroke: RGB(hex: 0x2A2F3A), ink: RGB(hex: 0x2A2F3A))

    /// Sand, turquoise water and sunny line colours.
    static let coastal = ThemePalette(
        id: "coastal", name: "Coastal",
        lines: [0xF0624F, 0xF2B134, 0x1F7FBF, 0x2E9E62, 0x9A6ACF, 0xEC6AA0, 0x0FA3A0].map(RGB.init(hex:)),
        outside: RGB(hex: 0xE6DDC6), land: RGB(hex: 0xF7F1E3), street: RGB(hex: 0xEDE3CC), block: RGB(hex: 0xF0E5CF),
        blockEdge: RGB(hex: 0xE5D8BC), park: RGB(hex: 0xD6E8C4), parkEdge: RGB(hex: 0xBFD9A8), tree: RGB(hex: 0xC4DDB0),
        water: RGB(hex: 0x8ED3D3), waterEdge: RGB(hex: 0x5DBABB), ripple: RGB(hex: 0xB7E6E3), shore: RGB(hex: 0xEAF5EE),
        stationFill: RGB(hex: 0xFFFFFF), stationStroke: RGB(hex: 0x23353D), ink: RGB(hex: 0x23353D))

    /// European old town: warm stone, terracotta roofs, muted heritage colours.
    static let oldTown = ThemePalette(
        id: "old-town", name: "Old Town",
        lines: [0xB83A3F, 0xD9952B, 0x3F6FA6, 0x6E8B3D, 0x7D4E8C, 0xC9617E, 0x3C9A8F].map(RGB.init(hex:)),
        outside: RGB(hex: 0xE3D5C2), land: RGB(hex: 0xF4ECDF), street: RGB(hex: 0xE6D7C2), block: RGB(hex: 0xEBDCC6),
        blockEdge: RGB(hex: 0xDCC8AC), park: RGB(hex: 0xD2DFB8), parkEdge: RGB(hex: 0xB7CC98), tree: RGB(hex: 0xBCD0A0),
        water: RGB(hex: 0xA6C3D6), waterEdge: RGB(hex: 0x7FA6BF), ripple: RGB(hex: 0xC4D7E3), shore: RGB(hex: 0xEAEFEA),
        stationFill: RGB(hex: 0xFFFDF8), stationStroke: RGB(hex: 0x3B2F2A), ink: RGB(hex: 0x3B2F2A))

    /// Steel and concrete with bold signal colours.
    static let industrial = ThemePalette(
        id: "industrial", name: "Industrial",
        lines: [0xE03C31, 0xF28C1E, 0x2457C5, 0x2A9D4A, 0xB43FA8, 0xE0558F, 0x0E9AB3].map(RGB.init(hex:)),
        outside: RGB(hex: 0xD6D9DC), land: RGB(hex: 0xECEEEF), street: RGB(hex: 0xDCDFE2), block: RGB(hex: 0xE1E4E6),
        blockEdge: RGB(hex: 0xD2D6DA), park: RGB(hex: 0xCFDCCB), parkEdge: RGB(hex: 0xB5C7AF), tree: RGB(hex: 0xBACBB4),
        water: RGB(hex: 0x97B4C6), waterEdge: RGB(hex: 0x6F93AA), ripple: RGB(hex: 0xB7CCD9), shore: RGB(hex: 0xE0E8EC),
        stationFill: RGB(hex: 0xFFFFFF), stationStroke: RGB(hex: 0x22272D), ink: RGB(hex: 0x22272D))

    static let all: [ThemePalette] = [.metropolitan, .coastal, .oldTown, .industrial]

    static func named(_ id: String) -> ThemePalette { all.first { $0.id == id } ?? .metropolitan }
}

/// The active look. Set from the player's settings before a scene is built; gameplay never reads these
/// values, except `routeMetrics`, which is shared with MetroCore's hit testing.
enum VisualTheme {
    struct LineColor {
        let name: String
        let rgb: RGB
    }

    /// The active theme (main thread only; read by renderers and SwiftUI).
    nonisolated(unsafe) static var palette = ThemePalette.metropolitan

    private static let lineNames = ["Crimson", "Amber", "Azure", "Emerald", "Violet", "Rose", "Teal"]

    static var linePalette: [LineColor] {
        zip(lineNames, palette.lines).map { LineColor(name: $0, rgb: $1) }
    }

    static func lineColor(_ index: Int) -> LineColor {
        let count = palette.lines.count
        let i = ((index % count) + count) % count
        return LineColor(name: lineNames[i % lineNames.count], rgb: palette.lines[i])
    }

    /// "Crimson Line" / "Tuyến Đỏ thẫm" (the key "%@ Line" is in the Vietnamese table).
    static func lineName(_ index: Int) -> String { tr("\(lineColor(index).name) Line") }

    // Map
    static var outside: RGB { palette.outside }
    static var land: RGB { palette.land }
    static var street: RGB { palette.street }
    static var block: RGB { palette.block }
    static var blockEdge: RGB { palette.blockEdge }
    static var park: RGB { palette.park }
    static var parkEdge: RGB { palette.parkEdge }
    static var tree: RGB { palette.tree }
    static var water: RGB { palette.water }
    static var waterEdge: RGB { palette.waterEdge }
    static var ripple: RGB { palette.ripple }
    static var shore: RGB { palette.shore }

    // Stations
    static var stationFill: RGB { palette.stationFill }
    static var stationStroke: RGB { palette.stationStroke }
    static let selection = RGB(hex: 0x2F80ED)
    static let delivered = RGB(hex: 0xFFC94A)
    static var ink: RGB { palette.ink }
    /// Overcrowding: amber while there is time, red when it's urgent.
    static let warning = RGB(hex: 0xF0A020)
    static let danger = RGB(hex: 0xE5484D)
    /// Bridge deck drawn under lines where they cross water.
    static let bridge = RGB(hex: 0xFBF8F1)
    static let bridgeEdge = RGB(hex: 0x9AA3AE)

    /// Special station badges.
    static func specialColor(_ special: SpecialStation) -> RGB {
        switch special {
        case .hub: RGB(hex: 0xE07A1F)
        case .interchange: RGB(hex: 0x2F80ED)
        case .heritage: RGB(hex: 0x8A5A44)
        case .grand: RGB(hex: 0x12A2A8)
        case .stadium: RGB(hex: 0x2E9E4F)
        case .airport: RGB(hex: 0x5B5FC7)
        }
    }

    static func specialSymbol(_ special: SpecialStation) -> String {
        switch special {
        case .hub: "flame.fill"
        case .interchange: "arrow.triangle.swap"
        case .heritage: "building.columns.fill"
        case .grand: "square.grid.2x2.fill"
        case .stadium: "sportscourt.fill"
        case .airport: "airplane"
        }
    }

    static let stationRadius: CGFloat = 17
    static let stationStrokeWidth: CGFloat = 4.5

    static let routeMetrics = RouteMetrics.standard
}
