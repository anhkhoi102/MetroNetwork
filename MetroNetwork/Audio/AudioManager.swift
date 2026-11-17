import AVFoundation
import MetroCore

/// Sound effects (Kenney Interface Sounds, CC0) and the generative music. One engine for the whole app.
/// If audio can't start (no output device), the game simply stays silent.
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    enum Sound: String, CaseIterable {
        case tap, line, station, deliver, purchase, warning, event, week, gameover, complete, remove, toggle

        /// Relative loudness and the shortest gap between two plays (busy sounds are throttled).
        var gain: Float {
            switch self {
            case .deliver: 0.28
            case .station: 0.45
            case .tap, .toggle: 0.5
            default: 0.8
            }
        }

        var minimumGap: Double {
            switch self {
            case .deliver: 0.12
            case .station: 0.3
            default: 0.05
            }
        }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Sound: Date] = [:]
    private var musicNode: AVAudioSourceNode?
    private let musicMixer = AVAudioMixerNode()
    private var synth: MusicSynth?
    private var started = false

    private var effectsVolume: Float = 0.8
    private var musicVolume: Float = 0.6
    private var muted = false
    /// Quieter while paused or in menus with the game in the background.
    private var musicDuck: Float = 1

    private init() {}

    /// Loads the sounds and starts the engine (once).
    func start() {
        guard !started else { return }
        started = true
        #if os(iOS)
        // Ambient: mixes with the player's own music and respects the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let output = engine.outputNode.inputFormat(forBus: 0)
        guard output.sampleRate > 0 else { return }
        for sound in Sound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else { continue }
            buffers[sound] = buffer
        }
        let format = buffers.values.first?.format ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        // Music: synthesised in the render callback.
        let musicFormat = AVAudioFormat(standardFormatWithSampleRate: output.sampleRate, channels: 1)!
        let synth = MusicSynth(sampleRate: output.sampleRate)
        self.synth = synth
        let node = Self.makeMusicNode(format: musicFormat, synth: synth)
        musicNode = node
        engine.attach(node)
        engine.attach(musicMixer)
        engine.connect(node, to: musicMixer, format: musicFormat)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: musicFormat)

        engine.prepare()
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            started = false
        }
        apply()
    }

    /// Built outside the main actor: the render block runs on the real-time audio thread.
    nonisolated private static func makeMusicNode(format: AVAudioFormat, synth: MusicSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            if let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) {
                synth.render(into: data, frames: Int(frameCount))
            }
            return noErr
        }
    }

    // MARK: Settings

    func configure(music: Double, effects: Double, muted: Bool) {
        musicVolume = Float(music)
        effectsVolume = Float(effects)
        self.muted = muted
        apply()
    }

    private func apply() {
        synth?.volume = muted ? 0 : musicVolume * musicDuck
    }

    // MARK: Music

    /// 0 = calm (menus), 1 = playing, 2 = rush hour.
    func setMusicIntensity(_ value: Float) { synth?.intensity = value }

    /// Lower the music while paused.
    func setMusicDucked(_ ducked: Bool) {
        musicDuck = ducked ? 0.45 : 1
        apply()
    }

    // MARK: Effects

    func play(_ sound: Sound) {
        guard started, !muted, effectsVolume > 0, let buffer = buffers[sound], !players.isEmpty else { return }
        let now = Date()
        if let last = lastPlayed[sound], now.timeIntervalSince(last) < sound.minimumGap { return }
        lastPlayed[sound] = now
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = sound.gain * effectsVolume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }
}
