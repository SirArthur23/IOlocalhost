import Foundation

/// Persists saved servers (recents + favorites) to a JSON file in
/// ~/Library/Application Support/LocalhostIO/servers.json
final class Store {
    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalhostIO", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("servers.json")
    }

    func load() -> [SavedServer] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SavedServer].self, from: data)) ?? []
    }

    func save(_ servers: [SavedServer]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(servers) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Persists per-server console logs to
/// ~/Library/Application Support/LocalhostIO/logs/<id>.log so they survive
/// app restarts.
final class LogStore {
    private let dir: URL
    private let maxBytes = 200_000   // keep only the tail when reading back

    init() {
        let fm = FileManager.default
        dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalhostIO/logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func url(for id: UUID) -> URL {
        dir.appendingPathComponent("\(id.uuidString).log")
    }

    func append(_ chunk: String, for id: UUID) {
        guard let data = chunk.data(using: .utf8) else { return }
        let fileURL = url(for: id)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// Truncate the log (used when a server is relaunched or cleared).
    func reset(_ id: UUID) {
        try? Data().write(to: url(for: id))
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Load every persisted log (tail-capped) keyed by server id.
    func loadAll() -> [UUID: String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [:] }

        var result: [UUID: String] = [:]
        for file in files where file.pathExtension == "log" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: file) else { continue }
            let tail = data.count > maxBytes ? data.suffix(maxBytes) : data
            result[id] = String(decoding: tail, as: UTF8.self)
        }
        return result
    }
}
