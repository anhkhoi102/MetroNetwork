import Foundation

/// Deterministic SplitMix64 generator. Its whole state is one `UInt64`, so it can live inside
/// `GameState`, be saved, and replay identically on every platform.
public struct SeededRandom: RandomNumberGenerator, Codable, Hashable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in `0..<1`.
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    /// Picks an index with probability proportional to `weights` (non-positive weights never win).
    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return nil }
        var roll = unit() * total
        for (i, w) in weights.enumerated() where w > 0 {
            roll -= w
            if roll < 0 { return i }
        }
        return weights.lastIndex { $0 > 0 }
    }

    /// Derives an independent generator (for sub-systems such as map generation).
    public mutating func fork() -> SeededRandom {
        SeededRandom(seed: next())
    }
}
