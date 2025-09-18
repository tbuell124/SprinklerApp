import Foundation

/// Persists the last successfully fetched `StatusDTO` so the UI can bootstrap
/// with cached data while a fresh network request is pending.
final class StatusCache {
    private struct Snapshot: Codable {
        let cacheVersion: Int
        let savedAt: Date
        let status: StatusDTO
    }

    private enum Constants {
        static let cacheVersion = 1
        static let directoryName = "StatusCache"
        static let fileName = "snapshot.json"
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.sprinklermobile.status-cache")
    private let fileURL: URL?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            for formatter in [fractionalFormatter, standardFormatter] {
                if let date = formatter.date(from: value) {
                    return date
                }
            }

            if let interval = TimeInterval(value) {
                return Date(timeIntervalSince1970: interval)
            }

            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unrecognized date format: \(value)")
        }

        self.fileURL = StatusCache.makeFileURL(fileManager: fileManager)
    }

    func load() -> StatusDTO? {
        guard let fileURL else { return nil }

        return queue.sync {
            do {
                let data = try Data(contentsOf: fileURL)
                let snapshot = try decoder.decode(Snapshot.self, from: data)
                guard snapshot.cacheVersion == Constants.cacheVersion else {
                    try? fileManager.removeItem(at: fileURL)
                    return nil
                }
                return snapshot.status
            } catch {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        }
    }

    func save(_ status: StatusDTO) {
        guard let fileURL else { return }

        queue.async {
            let snapshot = Snapshot(cacheVersion: Constants.cacheVersion,
                                    savedAt: Date(),
                                    status: status)
            do {
                let data = try self.encoder.encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                try? self.fileManager.removeItem(at: fileURL)
            }
        }
    }

    func clear() {
        guard let fileURL else { return }

        queue.async {
            try? self.fileManager.removeItem(at: fileURL)
        }
    }

    private static func makeFileURL(fileManager: FileManager) -> URL? {
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first else {
            return nil
        }

        let directory = baseDirectory.appendingPathComponent(Constants.directoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(Constants.fileName, isDirectory: false)
        } catch {
            return nil
        }
    }
}
