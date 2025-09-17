import Foundation

actor APIClient {
    private var baseURL: URL?
    private let httpClient: HTTPClient

    init(baseURL: URL? = nil, httpClient: HTTPClient = HTTPClient()) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    func updateBaseURL(_ url: URL?) {
        self.baseURL = url
    }

    func fetchStatus() async throws -> StatusDTO {
        let url = try makeURL(path: "/api/status")
        return try await httpClient.request(url: url)
    }

    func fetchRain() async throws -> RainDTO {
        let url = try makeURL(path: "/api/rain")
        return try await httpClient.request(url: url)
    }

    func setRain(isActive: Bool, durationHours: Int?) async throws {
        let url = try makeURL(path: "/api/rain")
        struct RainPayload: Encodable {
            let active: Bool
            let hours: Int?

            enum CodingKeys: String, CodingKey {
                case active = "active"
                case hours = "hours"
            }
        }

        let payload = RainPayload(active: isActive, hours: durationHours)
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: payload,
                                         fallbackToEmptyBody: true,
                                         decode: EmptyResponse.self)
    }

    func setPin(_ pin: Int, on: Bool) async throws {
        let path = "/api/pin/\(pin)/\(on ? "on" : "off")"
        let url = try makeURL(path: path)
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         fallbackToEmptyBody: true,
                                         decode: EmptyResponse.self)
    }

    func updatePin(_ pin: Int, name: String?, isEnabled: Bool) async throws {
        let url = try makeURL(path: "/api/pin/\(pin)")
        struct PinUpdatePayload: Encodable {
            let name: String?
            let isEnabled: Bool

            enum CodingKeys: String, CodingKey {
                case name
                case isEnabled = "is_enabled"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let name {
                    try container.encode(name, forKey: .name)
                } else {
                    try container.encodeNil(forKey: .name)
                }
                try container.encode(isEnabled, forKey: .isEnabled)
            }
        }

        let payload = PinUpdatePayload(name: name, isEnabled: isEnabled)
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: payload,
                                         fallbackToEmptyBody: false,
                                         decode: EmptyResponse.self)
    }

    func reorderPins(_ pinOrder: [Int]) async throws {
        let url = try makeURL(path: "/api/pins/reorder")
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: pinOrder,
                                         fallbackToEmptyBody: false,
                                         decode: EmptyResponse.self)
    }

    func createSchedule(_ schedule: ScheduleWritePayload) async throws {
        let url = try makeURL(path: "/api/schedule")
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: schedule,
                                         fallbackToEmptyBody: false,
                                         decode: EmptyResponse.self)
    }

    func updateSchedule(id: String, schedule: ScheduleWritePayload) async throws {
        let url = try makeURL(path: "/api/schedule/\(id)")
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: schedule,
                                         fallbackToEmptyBody: false,
                                         decode: EmptyResponse.self)
    }

    func deleteSchedule(id: String) async throws {
        let url = try makeURL(path: "/api/schedule/\(id)")
        _ = try await httpClient.request(url: url,
                                         method: .delete,
                                         decode: EmptyResponse.self)
    }

    func reorderSchedules(_ scheduleIds: [String]) async throws {
        let url = try makeURL(path: "/api/schedules/reorder")
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: scheduleIds,
                                         fallbackToEmptyBody: false,
                                         decode: EmptyResponse.self)
    }

    func fetchScheduleGroups() async throws -> [ScheduleGroupDTO] {
        let url = try makeURL(path: "/api/schedule-groups")
        return try await httpClient.request(url: url)
    }

    func createScheduleGroup(name: String) async throws {
        let url = try makeURL(path: "/api/schedule-groups")
        struct GroupPayload: Encodable { let name: String }
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: GroupPayload(name: name),
                                         fallbackToEmptyBody: false,
                                         decode: EmptyResponse.self)
    }

    func selectScheduleGroup(id: String) async throws {
        let url = try makeURL(path: "/api/schedule-groups/select")
        struct SelectPayload: Encodable { let id: String }
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         body: SelectPayload(id: id),
                                         fallbackToEmptyBody: false,
                                         decode: EmptyResponse.self)
    }

    func addAllToGroup(id: String) async throws {
        let url = try makeURL(path: "/api/schedule-groups/\(id)/add-all")
        _ = try await httpClient.request(url: url,
                                         method: .post,
                                         fallbackToEmptyBody: true,
                                         decode: EmptyResponse.self)
    }

    func deleteScheduleGroup(id: String) async throws {
        let url = try makeURL(path: "/api/schedule-groups/\(id)")
        _ = try await httpClient.request(url: url,
                                         method: .delete,
                                         decode: EmptyResponse.self)
    }

    private func makeURL(path: String) throws -> URL {
        guard let baseURL else { throw APIError.invalidURL }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = path
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }
}

struct ScheduleWritePayload: Encodable {
    var name: String?
    var durationMinutes: Int?
    var startTime: String?
    var days: [String]?
    var isEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case durationMinutes = "duration"
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
    }
}
