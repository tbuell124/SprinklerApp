import XCTest
@testable import Sprink

/// Integration-style tests that exercise the schedule REST endpoints against a mocked
/// server. The mocked URL protocol captures outbound requests from `APIClient` so we can
/// verify HTTP semantics without requiring a live Raspberry Pi controller.
final class ScheduleAPITests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockServerURLProtocol.requestHandler = nil
    }

    func testCreateSchedulePostsEncodedPayload() async throws {
        let client = makeClient()
        let payload = ScheduleWritePayload(id: "garden-morning",
                                           name: "Garden Morning",
                                           durationMinutes: 18,
                                           startTime: "06:15",
                                           days: ["Mon", "Wed", "Fri"],
                                           isEnabled: true)
        var capturedRequest: URLRequest?

        MockServerURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockServerURLProtocol.MockResponse(statusCode: 200,
                                                      headers: ["Content-Type": "application/json"],
                                                      body: Data("{}".utf8))
        }

        try await client.createSchedule(payload)

        guard let request = capturedRequest else {
            return XCTFail("Expected create schedule request to be captured")
        }

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/schedules")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let decoded = try decodeSchedulePayload(from: request)
        XCTAssertEqual(decoded.id, payload.id)
        XCTAssertEqual(decoded.name, payload.name)
        XCTAssertEqual(decoded.durationMinutes, payload.durationMinutes)
        XCTAssertEqual(decoded.startTime, payload.startTime)
        XCTAssertEqual(decoded.days, payload.days)
        XCTAssertEqual(decoded.isEnabled, payload.isEnabled)
    }

    func testUpdateScheduleUsesPutAndEncodesPayload() async throws {
        let client = makeClient()
        let payload = ScheduleWritePayload(id: "backyard-evening",
                                           name: "Backyard Evening",
                                           durationMinutes: 25,
                                           startTime: "19:45",
                                           days: ["Tue", "Thu"],
                                           isEnabled: false)
        var capturedRequest: URLRequest?

        MockServerURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockServerURLProtocol.MockResponse(statusCode: 200,
                                                      headers: ["Content-Type": "application/json"],
                                                      body: Data("{}".utf8))
        }

        try await client.updateSchedule(id: payload.id, schedule: payload)

        guard let request = capturedRequest else {
            return XCTFail("Expected update schedule request to be captured")
        }

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/schedules/\(payload.id)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let decoded = try decodeSchedulePayload(from: request)
        XCTAssertEqual(decoded.id, payload.id)
        XCTAssertEqual(decoded.name, payload.name)
        XCTAssertEqual(decoded.durationMinutes, payload.durationMinutes)
        XCTAssertEqual(decoded.startTime, payload.startTime)
        XCTAssertEqual(decoded.days, payload.days)
        XCTAssertEqual(decoded.isEnabled, payload.isEnabled)
    }

    func testDeleteScheduleIssuesDeleteRequest() async throws {
        let client = makeClient()
        let scheduleID = "flower-bed"
        var capturedRequest: URLRequest?

        MockServerURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockServerURLProtocol.MockResponse(statusCode: 200,
                                                      headers: ["Content-Type": "application/json"],
                                                      body: Data("{}".utf8))
        }

        try await client.deleteSchedule(id: scheduleID)

        guard let request = capturedRequest else {
            return XCTFail("Expected delete schedule request to be captured")
        }

        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/schedules/\(scheduleID)")
        XCTAssertNil(request.httpBody)
    }

    func testReorderSchedulesPostsIdentifierArray() async throws {
        let client = makeClient()
        let orderedIDs = ["front-yard", "garden", "backyard"]
        var capturedRequest: URLRequest?

        MockServerURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockServerURLProtocol.MockResponse(statusCode: 200,
                                                      headers: ["Content-Type": "application/json"],
                                                      body: Data("{}".utf8))
        }

        try await client.reorderSchedules(orderedIDs)

        guard let request = capturedRequest else {
            return XCTFail("Expected reorder schedules request to be captured")
        }

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/schedules/reorder")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody, "Expected reorder payload to include body data")
        let decoded = try JSONDecoder().decode([String].self, from: body)
        XCTAssertEqual(decoded, orderedIDs)
    }

    // MARK: - Helpers

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockServerURLProtocol.self]
        let cache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        let httpClient = HTTPClient(sessionConfiguration: configuration,
                                    cache: cache,
                                    maxRetries: 0,
                                    initialRetryDelay: 0,
                                    authenticationProvider: nil)
        let client = APIClient(baseURL: URL(string: "http://mock.local")!,
                               authentication: AuthenticationStub(),
                               httpClient: httpClient)
        return client
    }

    private func decodeSchedulePayload(from request: URLRequest) throws -> CapturedSchedulePayload {
        let body = try XCTUnwrap(request.httpBody, "Expected request to include JSON body")
        return try JSONDecoder().decode(CapturedSchedulePayload.self, from: body)
    }
}

private actor AuthenticationStub: AuthenticationManaging {
    func authorizationHeader() async -> (key: String, value: String)? { nil }
    func updateToken(_ token: String?) async throws {}
    func currentToken() async -> String? { nil }
}

private struct CapturedSchedulePayload: Decodable {
    let id: String
    let name: String?
    let durationMinutes: Int
    let startTime: String
    let days: [String]
    let isEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMinutes = "duration"
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
    }
}

final class MockServerURLProtocol: URLProtocol {
    struct MockResponse {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    static var requestHandler: ((URLRequest) -> MockResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockServerURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = handler(request)
        let httpResponse = HTTPURLResponse(url: request.url!,
                                           statusCode: response.statusCode,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // No-op because responses are returned synchronously via the handler closure.
    }
}
