import Foundation

/// A 2D point / vector in world units. World space is Y-up, matching SpriteKit.
public struct Vec2: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }

    /// Unit vector in the same direction, or `.zero` for a zero vector.
    public var normalized: Vec2 {
        let len = length
        return len > 1e-9 ? Vec2(x / len, y / len) : .zero
    }

    /// The vector rotated 90° counter-clockwise.
    public var perpendicular: Vec2 { Vec2(-y, x) }

    public func distance(to other: Vec2) -> Double { (self - other).length }
    public func distanceSquared(to other: Vec2) -> Double { (self - other).lengthSquared }
    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    public func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }

    public static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }

    public var description: String { String(format: "(%.1f, %.1f)", x, y) }
}

/// Axis-aligned rectangle in world units.
public struct Rect: Hashable, Codable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(center: Vec2, halfSize: Vec2) {
        self.init(minX: center.x - halfSize.x, minY: center.y - halfSize.y,
                  maxX: center.x + halfSize.x, maxY: center.y + halfSize.y)
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    public func insetBy(_ d: Double) -> Rect {
        Rect(minX: minX + d, minY: minY + d, maxX: maxX - d, maxY: maxY - d)
    }

    /// Smallest rectangle containing all points, or nil for an empty list.
    public static func bounding(_ points: [Vec2]) -> Rect? {
        guard let first = points.first else { return nil }
        var r = Rect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points.dropFirst() {
            r.minX = min(r.minX, p.x); r.maxX = max(r.maxX, p.x)
            r.minY = min(r.minY, p.y); r.maxY = max(r.maxY, p.y)
        }
        return r
    }
}

public enum Geometry2D {
    /// Distance from `p` to the segment `a`–`b`.
    public static func distance(from p: Vec2, toSegment a: Vec2, _ b: Vec2) -> Double {
        p.distance(to: closestPoint(on: a, b, to: p))
    }

    public static func closestPoint(on a: Vec2, _ b: Vec2, to p: Vec2) -> Vec2 {
        let ab = b - a
        let lenSq = ab.lengthSquared
        guard lenSq > 1e-12 else { return a }
        let t = max(0, min(1, (p - a).dot(ab) / lenSq))
        return a + ab * t
    }

    /// Distance from `p` to a polyline.
    public static func distance(from p: Vec2, toPolyline points: [Vec2]) -> Double {
        guard points.count > 1 else { return points.first.map { p.distance(to: $0) } ?? .infinity }
        var best = Double.infinity
        for i in 0..<(points.count - 1) {
            best = min(best, distance(from: p, toSegment: points[i], points[i + 1]))
        }
        return best
    }
}
