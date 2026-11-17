import CoreGraphics
import MetroCore

/// Station symbols as paths centred on the origin (Y-up). Used by SpriteKit and by SwiftUI icons.
enum ShapePaths {

    static func path(for shape: StationShape, radius r: CGFloat) -> CGPath {
        switch shape {
        case .circle:
            return CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        case .square:
            let s = r * 0.9
            return CGPath(roundedRect: CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s),
                          cornerWidth: r * 0.18, cornerHeight: r * 0.18, transform: nil)
        case .triangle:
            // Equilateral, centroid at the origin, slightly larger so its area matches the circle.
            return polygon(sides: 3, radius: r * 1.28, rotation: .pi / 2, cornerRadius: r * 0.16)
        case .diamond:
            return polygon(sides: 4, radius: r * 1.2, rotation: .pi / 2, cornerRadius: r * 0.14)
        case .hexagon:
            return polygon(sides: 6, radius: r * 1.06, rotation: 0, cornerRadius: r * 0.12)
        case .star:
            return star(outer: r * 1.3, inner: r * 0.62)
        }
    }

    private static func polygon(sides: Int, radius: CGFloat, rotation: CGFloat, cornerRadius: CGFloat) -> CGPath {
        let points = (0..<sides).map { i -> CGPoint in
            let a = rotation + 2 * .pi * CGFloat(i) / CGFloat(sides)
            return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
        }
        return rounded(points, cornerRadius: cornerRadius)
    }

    private static func star(outer: CGFloat, inner: CGFloat) -> CGPath {
        let points = (0..<10).map { i -> CGPoint in
            let a = .pi / 2 + .pi * CGFloat(i) / 5
            let r = i.isMultiple(of: 2) ? outer : inner
            return CGPoint(x: cos(a) * r, y: sin(a) * r)
        }
        return rounded(points, cornerRadius: outer * 0.06)
    }

    /// Closed polygon with softened corners.
    private static func rounded(_ points: [CGPoint], cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        let start = CGPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2)
        path.move(to: start)
        for i in 0..<n {
            path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % n], radius: cornerRadius)
        }
        path.closeSubpath()
        return path
    }
}
