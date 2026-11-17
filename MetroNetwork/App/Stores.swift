import Foundation
import Observation
import MetroCore

/// Where the game keeps its files: Application Support/Metro Network (inside the sandbox container on macOS).
enum StorageLocation {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Metro Network", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// The player's progress (campaign stars, challenge medals, Endless bests, totals, settings), saved as JSON
/// after every change. Writes are atomic, so a crash can't leave a half-written file.
@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    private(set) var progress: PlayerProgress
    @ObservationIgnored private let url: URL

    init(url: URL = StorageLocation.directory.appendingPathComponent("progress.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(PlayerProgress.self, from: data) {
            progress = decoded
        } else {
            progress = PlayerProgress()
            Self.migrateScoreBook(into: &progress)
        }
    }

    func update(_ change: (inout PlayerProgress) -> Void) {
        change(&progress)
        save()
    }

    func reset() {
        progress = PlayerProgress()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Phase 3 kept Endless bests in UserDefaults; carry them over once (they were Normal difficulty).
    private static func migrateScoreBook(into progress: inout PlayerProgress) {
        struct Old: Codable { var bestScore, mostDelivered, longestWeeks, mostStations, gamesPlayed: Int }
        let key = "MetroNetwork.ScoreBook.v1"
        guard let data = UserDefaults.standard.data(forKey: key),
              let old = try? JSONDecoder().decode([String: Old].self, from: data) else { return }
        for (map, r) in old {
            var record = PlayerProgress.EndlessRecord()
            record.bestScore = r.bestScore
            record.mostDelivered = r.mostDelivered
            record.longestWeeks = r.longestWeeks
            record.mostStations = r.mostStations
            record.games = r.gamesPlayed
            progress.endless[PlayerProgress.endlessKey(map: map, difficulty: .normal)] = record
        }
    }
}

/// The session in progress, saved so the game can continue after the app is closed (or killed).
@MainActor
enum SessionStore {
    private static var url: URL { StorageLocation.directory.appendingPathComponent("session.json") }

    static func save(_ session: SavedSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The saved session, if there is one in a format this version understands.
    static func load() -> SavedSession? {
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data),
              session.version == SavedSession.formatVersion, !session.state.isOver else { return nil }
        return session
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
