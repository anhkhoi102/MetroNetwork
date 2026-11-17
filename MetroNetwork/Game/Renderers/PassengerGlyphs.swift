import CoreGraphics
import MetroCore

/// Builds one combined path for a group of passenger glyphs, so a whole queue or a whole train load is a
/// single node (cheap to draw, rebuilt only when the group changes).
enum PassengerGlyphs {

    /// Glyphs laid out in rows, left to right, top to bottom, starting at `origin` (centre of the first glyph).
    static func path(for shapes: [StationShape], origin: CGPoint, perRow: Int, spacing: CGFloat,
                     radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for (i, shape) in shapes.enumerated() {
            let col = i % perRow, row = i / perRow
            let transform = CGAffineTransform(translationX: origin.x + CGFloat(col) * spacing,
                                              y: origin.y - CGFloat(row) * spacing)
            path.addPath(ShapePaths.path(for: shape, radius: radius), transform: transform)
        }
        return path
    }
}
