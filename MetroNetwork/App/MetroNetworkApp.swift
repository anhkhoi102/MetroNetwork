import SwiftUI

@main
struct MetroNetworkApp: App {
    init() {
        AppFonts.register()
        let p = ProgressStore.shared.progress
        VisualTheme.palette = .named(p.isThemeUnlocked(p.theme) ? p.theme : "metropolitan")
        AudioManager.shared.start()
        AudioManager.shared.configure(music: p.musicVolume, effects: p.effectsVolume, muted: p.muted)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        #endif
    }
}
