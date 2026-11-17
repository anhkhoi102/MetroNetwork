import Foundation

/// Original generative background music, synthesised in real time (no audio files): a slow chord loop of
/// soft pads, a gentle bass and pentatonic plucks. `intensity` (0 calm … 2 rush hour) raises the tempo and
/// the number of plucks, so the music follows the game.
///
/// `render` runs on the audio thread: no allocation, no locks. The two control values are plain floats
/// written from the main thread; a torn read only means one slightly different note, never a crash.
final class MusicSynth: @unchecked Sendable {
    /// 0 … 2. Written from the main thread.
    var intensity: Float = 0
    /// Linear gain, 0 … 1. Written from the main thread.
    var volume: Float = 0.5

    private let sampleRate: Float
    private var rng: UInt64 = 0x9E37_79B9_7F4A_7C15

    // Chords as MIDI notes: Cmaj9, Am7, Fmaj7, G6 — calm and unresolved, so the loop never feels like it ends.
    private let chords: [[Int]] = [[48, 55, 64, 71], [45, 52, 60, 67], [41, 48, 57, 64], [43, 50, 59, 64]]
    private let melodyScale: [Int] = [72, 74, 76, 79, 81, 84, 86, 88]
    private var chordIndex = 0
    private var stepInBar = 0
    private var samplesToNextStep: Float = 0

    // Pad: 4 voices with a slow crossfade between chords.
    // Voice state lives in fixed buffers: plain pointer access, no array bounds or exclusivity checks on the
    // real-time audio thread.
    private let padFreq = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    private let padPhase = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    private var padAmp: Float = 0
    private var padLow: Float = 0

    // Plucks: small ring of decaying voices.
    private static let pluckVoices = 8
    private let pluckFreq = UnsafeMutablePointer<Float>.allocate(capacity: 8)
    private let pluckPhase = UnsafeMutablePointer<Float>.allocate(capacity: 8)
    private let pluckAmp = UnsafeMutablePointer<Float>.allocate(capacity: 8)
    private var nextPluck = 0
    private let pluckDecay: Float

    // Bass.
    private var bassFreq: Float = 0
    private var bassPhase: Float = 0
    private var bassAmp: Float = 0
    private let bassDecay: Float

    /// One cycle of a sine wave: a table lookup instead of `sinf` for every voice and sample.
    private static let tableSize = 2048
    private let sine: UnsafeMutablePointer<Float> = {
        let table = UnsafeMutablePointer<Float>.allocate(capacity: MusicSynth.tableSize)
        for i in 0..<MusicSynth.tableSize { table[i] = sinf(2 * .pi * Float(i) / Float(MusicSynth.tableSize)) }
        return table
    }()

    @inline(__always) private func wave(_ phase: Float) -> Float {
        let x = phase * Float(Self.tableSize)
        let i = Int(x)
        return sine[i & (Self.tableSize - 1)]
    }

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)
        pluckDecay = expf(-1 / (Float(sampleRate) * 0.9))
        bassDecay = expf(-1 / (Float(sampleRate) * 1.6))
        for buffer in [padFreq, padPhase] { buffer.initialize(repeating: 0, count: 4) }
        for buffer in [pluckFreq, pluckPhase, pluckAmp] { buffer.initialize(repeating: 0, count: Self.pluckVoices) }
        setChord(0)
    }

    deinit {
        for buffer in [padFreq, padPhase, pluckFreq, pluckPhase, pluckAmp, sine] { buffer.deallocate() }
    }

    private static func frequency(_ midi: Int) -> Float { 440 * powf(2, Float(midi - 69) / 12) }

    private func random() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng % 10_000) / 10_000
    }

    private func setChord(_ index: Int) {
        chordIndex = index
        for (i, note) in chords[index].enumerated() { padFreq[i] = Self.frequency(note + 12) }
        bassFreq = Self.frequency(chords[index][0] - 12)
        bassAmp = 0.22
        bassPhase = 0
    }

    /// One eighth-note step: maybe a pluck, and every 16 steps the next chord.
    private func step() {
        if stepInBar == 0 { setChord((chordIndex + 1) % chords.count) }
        let busy = min(2, max(0, intensity))
        let chance: Float = 0.12 + 0.22 * busy
        if random() < chance {
            // Prefer notes of the current chord, otherwise any pentatonic note (no allocation here).
            var note = melodyScale[Int(random() * Float(melodyScale.count)) % melodyScale.count]
            if random() < 0.6 {
                let chord = chords[chordIndex]
                note = 72 + chord[Int(random() * Float(chord.count)) % chord.count] % 12 + (random() < 0.3 ? 12 : 0)
            }
            pluckFreq[nextPluck] = Self.frequency(note)
            pluckPhase[nextPluck] = 0
            pluckAmp[nextPluck] = 0.10 + 0.05 * random()
            nextPluck = (nextPluck + 1) % Self.pluckVoices
        }
        stepInBar = (stepInBar + 1) % 16
    }

    /// Fills `frames` mono samples.
    func render(into buffer: UnsafeMutablePointer<Float>, frames: Int) {
        let bpm = 70 + 9 * min(2, max(0, intensity))
        let stepLength = sampleRate * 60 / bpm / 2
        let gain = volume
        let padTarget: Float = 0.06
        for n in 0..<frames {
            if samplesToNextStep <= 0 {
                step()
                samplesToNextStep += stepLength
            }
            samplesToNextStep -= 1

            // Pad: slow swell, soft triangle-ish tone through a gentle low-pass.
            padAmp += (padTarget - padAmp) * 0.00002
            var pad: Float = 0
            for i in 0..<4 {
                padPhase[i] += padFreq[i] * (1 + 0.002 * Float(i)) / sampleRate
                if padPhase[i] >= 1 { padPhase[i] -= 1 }
                let x = wave(padPhase[i])
                pad += x + 0.15 * wave((3 * padPhase[i]).truncatingRemainder(dividingBy: 1))
            }
            padLow += (pad - padLow) * 0.08
            var sample = padLow * padAmp

            // Bass.
            bassPhase += bassFreq / sampleRate
            if bassPhase >= 1 { bassPhase -= 1 }
            sample += wave(bassPhase) * bassAmp
            bassAmp *= bassDecay

            // Plucks.
            for i in 0..<Self.pluckVoices where pluckAmp[i] > 0.0005 {
                pluckPhase[i] += pluckFreq[i] / sampleRate
                if pluckPhase[i] >= 1 { pluckPhase[i] -= 1 }
                let p = pluckPhase[i]
                sample += (wave(p) + 0.3 * wave((2 * p).truncatingRemainder(dividingBy: 1))) * pluckAmp[i]
                pluckAmp[i] *= pluckDecay
            }

            // Soft limiter.
            let out = sample * gain
            buffer[n] = out / (1 + abs(out))
        }
    }
}
