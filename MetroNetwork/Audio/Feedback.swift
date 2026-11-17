import Foundation
#if os(iOS)
import UIKit
#endif

/// Game feedback in one place: a sound, plus a matching haptic on iPhone/iPad.
@MainActor
enum Feedback {
    static func play(_ sound: AudioManager.Sound) {
        AudioManager.shared.play(sound)
        #if os(iOS)
        switch sound {
        case .line, .purchase: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .gameover: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .complete: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .toggle, .remove: UISelectionFeedbackGenerator().selectionChanged()
        default: break
        }
        #endif
    }
}
