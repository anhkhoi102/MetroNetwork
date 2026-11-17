import Foundation
import SwiftUI
import MetroCore

/// The two languages the game speaks.
enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }
    /// Its own name, in itself: never translated.
    var name: String { self == .english ? "English" : "Tiếng Việt" }
    var short: String { self == .english ? "EN" : "VI" }
}

/// Showing the game in Vietnamese.
///
/// The game is written in English: code, core data and saves. Vietnamese is put on when a string is shown,
/// so switching takes effect at once and a save opens in either language. The macOS menu bar stays English
/// (no .lproj translations).
///
/// 1. `tr("Deliver \(n) passengers")`: the literal becomes the key "Deliver %@ passengers"; values are put
///    back (and translated themselves if they are words, e.g. a shape name). Needed wherever a sentence is built.
/// 2. `Text(...)`, `Button(...)` and `Label(...)` in this app are the functions at the end of this file, not
///    SwiftUI's own initialisers: they look every string up before showing it.
/// The table is `Resources/Localization/vi.json`; `Scripts/l10n.py check` lists keys without a translation.
@Observable
final class L10n {
    // Only ever used from the main thread (views, the scene and the session controller).
    nonisolated(unsafe) static let shared = L10n()

    var language: Language {
        didSet {
            guard language != oldValue else { return }
            let code = language.rawValue
            MainActor.assumeIsolated { ProgressStore.shared.update { $0.language = code } }
        }
    }

    @ObservationIgnored private var table: [String: String] = [:]
    /// Same keys in small letters ("triangle" in "A triangle station").
    @ObservationIgnored private var lower: [String: String] = [:]

    private init() {
        let saved = MainActor.assumeIsolated { ProgressStore.shared.progress.language }
        if let forced = ProcessInfo.processInfo.environment["METRO_LANG"].flatMap(Language.init(rawValue:)) {
            language = forced
        } else if let saved = saved.flatMap(Language.init(rawValue:)) {
            language = saved
        } else {
            // First start: follow the device.
            language = Locale.preferredLanguages.first?.hasPrefix("vi") == true ? .vietnamese : .english
        }
        if let url = Bundle.main.url(forResource: "vi", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            table = decoded
            for (key, value) in decoded { lower[key.lowercased()] = value.lowercased() }
        }
    }

    /// The translation of a key with "%@" in it (the key itself in English, or when missing).
    func format(for key: String) -> String {
        guard language == .vietnamese else { return key }
        return table[key] ?? key
    }

    /// A whole string as it is about to be shown.
    func translate(_ text: String) -> String {
        guard language == .vietnamese else { return text }
        if let found = table[text] { return found }
        if text == text.lowercased(), let found = lower[text] { return found }
        // Leading/trailing spaces are not part of keys.
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed != text, let found = table[trimmed] { return text.replacingOccurrences(of: trimmed, with: found) }
        return text
    }

    var isVietnamese: Bool { language == .vietnamese }
}

/// A string literal taken apart: "Deliver \(n) passengers" is the key "Deliver %@ passengers" and one value.
struct Loc: ExpressibleByStringInterpolation {
    var key: String
    var values: [String]

    init(stringLiteral value: String) {
        key = value
        values = []
    }

    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        values = stringInterpolation.values
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var values: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) { key += literal }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            values.append("\(value)")
        }
    }
}

/// The sentence in the player's language. In a translation "%@" takes the values in order and "%1$@",
/// "%2$@" take them by number, for when Vietnamese wants another order.
func tr(_ text: Loc) -> String {
    let l10n = L10n.shared
    let format = l10n.format(for: text.key)
    guard !text.values.isEmpty else { return format }
    let values = text.values.map { l10n.translate($0) }
    var result = ""
    var next = 0
    var rest = Substring(format)
    while let percent = rest.firstIndex(of: "%") {
        result += rest[..<percent]
        let after = rest[rest.index(after: percent)...]
        if after.hasPrefix("@") {
            if next < values.count { result += values[next] }
            next += 1
            rest = after.dropFirst()
        } else if let digit = after.first?.wholeNumberValue, after.dropFirst().hasPrefix("$@") {
            if digit >= 1, digit <= values.count { result += values[digit - 1] }
            rest = after.dropFirst(3)
        } else {
            result += "%"
            rest = after
        }
    }
    return result + rest
}

/// A string that is not a literal here (a core name, a toast): looked up as a whole.
func translated(_ text: String) -> String { L10n.shared.translate(text) }

// MARK: SwiftUI, translated

// Within this app `Text("…")`, `Button("…") {}` and `Label("…", systemImage:)` are these functions. They shadow
// SwiftUI's initialisers of the same shape so that every string on screen passes through the table.

func Text<S: StringProtocol>(_ content: S) -> SwiftUI.Text {
    SwiftUI.Text(verbatim: L10n.shared.translate(String(content)))
}

func Button<S: StringProtocol>(_ title: S, action: @escaping () -> Void) -> SwiftUI.Button<SwiftUI.Text> {
    SwiftUI.Button(action: action) { Text(title) }
}

func Button<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) -> SwiftUI.Button<SwiftUI.Text> {
    SwiftUI.Button(role: role, action: action) { Text(title) }
}

func Label<S: StringProtocol>(_ title: S, systemImage: String) -> SwiftUI.Label<SwiftUI.Text, SwiftUI.Image> {
    SwiftUI.Label { Text(title) } icon: { SwiftUI.Image(systemName: systemImage) }
}

// Pass-throughs: with the functions above in this module, these shapes must be declared here too.

func Button<L: View>(action: @escaping () -> Void, @ViewBuilder label: () -> L) -> SwiftUI.Button<L> {
    SwiftUI.Button(action: action, label: label)
}

func Button<L: View>(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> SwiftUI.Button<L> {
    SwiftUI.Button(role: role, action: action, label: label)
}

// Tooltips and accessibility labels built from variables: looked up here too. These non-generic overloads win
// over SwiftUI's generic `StringProtocol` ones for `String` arguments.
extension View {
    func help(_ text: String) -> some View {
        help(SwiftUI.Text(verbatim: L10n.shared.translate(text)))
    }

    func accessibilityLabel(_ text: String) -> some View {
        accessibilityLabel(SwiftUI.Text(verbatim: L10n.shared.translate(text)))
    }
}

extension SessionMode {
    /// "Riverside · Normal" / "Riverside · Thường", or the level's title.
    var localizedName: String {
        switch self {
        case let .endless(preset, difficulty): "\(preset.name) · \(translated(difficulty.displayName))"
        case .scenario(let id): translated(Scenarios.definition(id)?.title ?? "")
        }
    }
}
