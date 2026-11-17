import CoreText
import Foundation

/// Registers the bundled Outfit font (SIL OFL 1.1, see Resources/Fonts/Outfit-OFL.txt) for this process.
/// Done in code so macOS and iOS share one path (no Info.plist font keys).
enum AppFonts {
    static let family = "Outfit"
    /// A named instance of the variable font, for SpriteKit labels.
    static let boldFontName = "Outfit-Bold"

    static func register() {
        guard let url = Bundle.main.url(forResource: "Outfit", withExtension: "ttf") else {
            assertionFailure("Outfit.ttf missing from the bundle")
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
