import MetroCore

/// Contour lines of a hill at a few fixed elevations (0.2, 0.45, 0.7 of full height), for drawing.
enum HillContours {
    struct Level { let elevation: Double; let radius: Double }

    static func levels(for hill: Hill) -> [Level] {
        [0.2, 0.45, 0.7].compactMap { e in
            guard e < hill.height else { return nil }
            // elevation = height · (1 − d²)²  ⇒  d = √(1 − √(e / height))
            let d = (1 - (e / hill.height).squareRoot()).squareRoot()
            return Level(elevation: e, radius: hill.radius * d)
        }
    }
}
