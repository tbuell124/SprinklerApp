import Foundation

/// Codable representation of all locally cached schedule state, including
/// pending deletions that still need to be synchronised with the controller.
struct SchedulePersistenceState: Codable {
    var schedules: [Schedule]
    var pendingDeletionIds: [String]
    var pendingReorder: [String]?

    init(schedules: [Schedule] = [],
         pendingDeletionIds: [String] = [],
         pendingReorder: [String]? = nil) {
        self.schedules = schedules
        self.pendingDeletionIds = pendingDeletionIds
        self.pendingReorder = pendingReorder
    }
}

/// Thin wrapper around file-based persistence for offline schedules. The
/// implementation favours resiliency over strict error propagation so the app
/// always remains functional even if disk operations fail.
final class SchedulePersistence {
    private enum Constants {
        static let directoryName = "Schedules"
        static let fileName = "schedules.json"
    }

    private let queue = DispatchQueue(label: "com.sprinklermobile.schedule-persistence",
                                      qos: .utility)
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        self.fileURL = SchedulePersistence.makeFileURL(fileManager: fileManager)
    }

    func load() -> SchedulePersistenceState {
        guard let fileURL else { return SchedulePersistenceState() }
        return queue.sync {
            do {
                let data = try Data(contentsOf: fileURL)
                return try decoder.decode(SchedulePersistenceState.self, from: data)
            } catch {
                try? fileManager.removeItem(at: fileURL)
                return SchedulePersistenceState()
            }
        }
    }

    func save(_ state: SchedulePersistenceState) {
        guard let fileURL else { return }
        queue.async {
            do {
                let data = try self.encoder.encode(state)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                try? self.fileManager.removeItem(at: fileURL)
            }
        }
    }

    private static func makeFileURL(fileManager: FileManager) -> URL? {
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first else {
            return nil
        }
        let directory = baseDirectory.appendingPathComponent(Constants.directoryName,
                                                             isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(Constants.fileName,
                                                   isDirectory: false)
        } catch {
            return nil
        }
    }
}

