import Foundation

struct FeedCacheSnapshot: Codable, Sendable {
    let fingerprint: String
    let items: [RecommendedTrack]
    let savedAt: Date
}

actor FeedCache {
    static let shared = FeedCache()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let base = directory.appendingPathComponent("Volna", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("feed-cache.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() -> FeedCacheSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(FeedCacheSnapshot.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(snapshot.savedAt) < 14 * 24 * 60 * 60 else {
            return nil
        }
        return snapshot
    }

    func save(fingerprint: String, items: [RecommendedTrack]) {
        guard !items.isEmpty else { return }
        let snapshot = FeedCacheSnapshot(
            fingerprint: fingerprint,
            items: Array(items.prefix(160)),
            savedAt: Date()
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.debug("Feed cache write failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func size() -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }
}
