import SpriteKit
import MetroCore

/// Where an announced district will open: a dashed, gently pulsing circle with a building symbol.
@MainActor
final class DistrictPreviewNode: SKNode {
    private let ring = SKShapeNode()
    private let fill = SKShapeNode()
    private let icon: SKSpriteNode
    private var shown: NewDistrict?

    override init() {
        let texture = Textures.symbol("building.2.fill", color: VisualTheme.warning.darkened(0.2))
        icon = SKSpriteNode(texture: texture)
        super.init()
        fill.fillColor = VisualTheme.warning.sk.withAlphaComponent(0.12)
        fill.strokeColor = .clear
        ring.fillColor = .clear
        ring.strokeColor = VisualTheme.warning.darkened(0.1).sk
        ring.lineWidth = 4
        let size = texture.size()
        let scale = 34 / max(size.width, size.height, 1)
        icon.size = CGSize(width: size.width * scale, height: size.height * scale)
        icon.alpha = 0.85
        for n in [fill, ring, icon] as [SKNode] { addChild(n) }
        let pulse = SKAction.sequence([.fadeAlpha(to: 0.55, duration: 0.9), .fadeAlpha(to: 1, duration: 0.9)])
        run(.repeatForever(pulse))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ district: NewDistrict?) {
        guard district != shown else { return }
        shown = district
        isHidden = district == nil
        guard let district else { return }
        position = CGPoint(district.center)
        let r = CGFloat(district.radius)
        let circle = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        fill.path = circle
        ring.path = circle.copy(dashingWithPhase: 0, lengths: [16, 12])
    }
}
