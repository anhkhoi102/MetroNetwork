import SpriteKit

/// Bitmap textures (CC0, Kenney Particle Pack — see THIRD_PARTY_ASSETS.md). Loaded once, shared by all nodes.
@MainActor
enum Textures {
    /// Soft round glow: shadows, selection halos, spawn pulses.
    static let glow = load("glow")
    /// Four-point sparkle: passenger deliveries.
    static let sparkle = load("sparkle")

    private static func load(_ name: String) -> SKTexture {
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .linear
        return texture
    }

    /// An SF Symbol rendered once into a texture (cached by name and colour).
    static func symbol(_ name: String, color: RGB) -> SKTexture {
        let key = "\(name)#\(color.r),\(color.g),\(color.b)"
        if let cached = symbolCache[key] { return cached }
        let texture: SKTexture
        #if os(macOS)
        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(red: color.r, green: color.g, blue: color.b, alpha: 1)]))
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            texture = SKTexture(image: image)
        } else {
            texture = SKTexture()
        }
        #else
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .bold)
        if let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(UIColor(red: color.r, green: color.g, blue: color.b, alpha: 1), renderingMode: .alwaysOriginal) {
            texture = SKTexture(image: image)
        } else {
            texture = SKTexture()
        }
        #endif
        texture.filteringMode = .linear
        symbolCache[key] = texture
        return texture
    }

    private static var symbolCache: [String: SKTexture] = [:]

    /// A tinted sprite of `texture`, `size` world units across.
    static func sprite(_ texture: SKTexture, size: CGFloat, color: SKColor, alpha: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
        node.color = color
        node.colorBlendFactor = 1
        node.alpha = alpha
        return node
    }
}
