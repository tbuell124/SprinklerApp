import Foundation

/// Concurrency-safe gateway to the sprinkler controller REST API.
///
/// The client keeps track of the currently selected base URL, manages authentication tokens and exposes high-level
/// domain operations that the store consumes. All low-level request work is delegated to `HTTPClient`.
actor APIClient {
    private var baseURL: URL?
    private let httpClient: HTTPClient
    private let authentication: AuthenticationManaging

    init(baseURL: URL? = nil,
         authentication: AuthenticationManaging = AuthenticationController(),
         httpClient: HTTPClient? = nil) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.httpClient = httpClient ?? HTTPClient(authenticationProvider: authentication)
    }

    func updateBaseURL(_ url: URL?) {
        self.baseURL = url
    }

    /// Updates the persisted authentication token so subsequent requests include the proper Authorization header.
    func updateAuthenticationToken(_ token: String?) async throws {
        try await authentication.updateToken(token)
    }

    /// Exposes the currently stored token for diagnostics or settings screens.
    func currentAuthenticationToken() async -> String? {
        await authentication.currentToken()
    }

    func fetchStatus() async throws -> StatusDTO {
        try await perform(.init(path: "/api/status"))
    }

    func fetchRain() async throws -> RainDTO {
        try await perform(.init(path: "/api/rain"))
    }

    func updateRainSettings(zipCode: String, thresholdPercent: Int, isEnabled: Bool) async throws {
        struct RainSettingsPayload: Encodable {
            let zipCode: String
            let thresholdPercent: Int
            let automationEnabled: Bool

            enum CodingKeys: String, CodingKey {
                case zipCode = "zip_code"
                case thresholdPercent = "threshold_percent"
                case automationEnabled = "automation_enabled"
            }
        }

        let payload = RainSettingsPayload(zipCode: zipCode,
                                          thresholdPercent: thresholdPercent,
                                          automationEnabled: isEnabled)
        let endpoint = Endpoint<EmptyResponse>(path: "/api/rain/settings",
                                               method: .post,
                                               body: AnyEncodable(payload))
        _ = try await perform(endpoint)
    }

    func setRain(isActive: Bool, durationHours: Int?) async throws {
        struct RainPayload: Encodable {
            let active: Bool
            let hours: Int?
        }

        let payload = RainPayload(active: isActive, hours: durationHours)
        let endpoint = Endpoint<EmptyResponse>(path: "/api/rain-delay",
                                               method: .post,
                                               body: AnyEncodable(payload),
                                               fallbackToEmptyBody: true)
        _ = try await perform(endpoint)
    }

    func setPin(_ pin: Int, on: Bool) async throws {
        let endpoint = Endpoint<EmptyResponse>(path: "/api/pin/\(pin)/\(on ? "on" : "off")",
                                               method: .post,
                                               fallbackToEmptyBody: true)
        _ = try await perform(endpoint)
    }

    func updatePin(_ pin: Int, name: String?, isEnabled: Bool) async throws {
        struct PinUpdatePayload: Encodable {
            let name: String?
            let isEnabled: Bool

            enum CodingKeys: String, CodingKey {
                case name
                case isEnabled = "is_enabled"
            }
        }

        let payload = PinUpdatePayload(name: name, isEnabled: isEnabled)
        let endpoint = Endpoint<EmptyResponse>(path: "/api/pins/\(pin)",
                                               method: .post,
                                               body: AnyEncodable(payload))
        _ = try await perform(endpoint)
    }

    func reorderPins(_ pinOrder: [Int]) async throws {
        let endpoint = Endpoint<EmptyResponse>(path: "/api/pins/reorder",
                                               method: .post,
                                               body: AnyEncodable(pinOrder))
        _ = try await perform(endpoint)
    }

    func createSchedule(_ schedule: ScheduleWritePayload) async throws {
        let endpoint = Endpoint<EmptyResponse>(path: "/api/schedules",
                                               method: .post,
                                               body: AnyEncodable(schedule))
        _ = try await perform(endpoint)
    }

    func updateSchedule(id: String, schedule: ScheduleWritePayload) async throws {
        let endpoint = Endpoint<EmptyResponse>(path: "/api/schedules/\(id)",
                                               method: .put,
                                               body: AnyEncodable(schedule))
        _ = try await perform(endpoint)
    }

    func deleteSchedule(id: String) async throws {
        let endpoint = Endpoint<EmptyResponse>(path: "/api/schedules/\(id)",
                                               method: .delete)
        _ = try await perform(endpoint)
    }

    func reorderSchedules(_ scheduleIds: [String]) async throws {
        let endpoint = Endpoint<EmptyResponse>(path: "/api/schedules/reorder",
                                               method: .post,
                                               body: AnyEncodable(scheduleIds))
        _ = try await perform(endpoint)
    }

    private func perform<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        guard let baseURL else { throw APIError.invalidURL }
        return try await httpClient.request(endpoint, baseURL: baseURL)
    }
}
