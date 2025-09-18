#if canImport(XCTest)
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SprinklerConnectivity

final class HealthCheckerTests: XCTestCase {
    func testConnectedWhenServerReturnsValidJSON() async throws {
        let expectation = expectation(description: "Request received")
        let protocolClass = StubURLProtocol.self
        let statusCode = 200
        let responseData = Data("{\"ok\":true}".utf8)
        StubURLProtocol.requestHandler = { request in
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: statusCode,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, responseData)
        }

        let checker = HealthChecker(session: makeSession(protocolClass: protocolClass))
        let result = await checker.check(baseURL: URL(string: "http://example.com:8000")!)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .connected)
    }

    func testOfflineWhenServerReturnsInvalidJSON() async {
        configureStub(statusCode: 200, data: Data("not-json".utf8))
        let checker = HealthChecker(session: makeSession(protocolClass: StubURLProtocol.self))

        let result = await checker.check(baseURL: URL(string: "http://example.com")!)

        if case let .offline(description) = result {
            XCTAssertNotNil(description)
        } else {
            XCTFail("Expected offline state")
        }
    }

    func testOfflineWhenServerReturnsUnrecognizedStatusField() async {
        configureStub(statusCode: 200, data: Data("{\"status\":\"mystery\"}".utf8))
        let checker = HealthChecker(session: makeSession(protocolClass: StubURLProtocol.self))

        let result = await checker.check(baseURL: URL(string: "http://example.com")!)

        if case let .offline(description) = result {
            XCTAssertNotNil(description)
        } else {
            XCTFail("Expected offline state")
        }
    }

    func testOfflineWhenControllerReportsUnhealthyStatus() async {
        configureStub(statusCode: 200, data: Data("{\"ok\":false}".utf8))
        let checker = HealthChecker(session: makeSession(protocolClass: StubURLProtocol.self))

        let result = await checker.check(baseURL: URL(string: "http://example.com")!)

        if case let .offline(description) = result {
            XCTAssertEqual(description, "Controller reported unhealthy status")
        } else {
            XCTFail("Expected offline state")
        }
    }

    func testOfflineWhenServerReturnsErrorStatus() async {
        configureStub(statusCode: 500, data: Data("{}".utf8))
        let checker = HealthChecker(session: makeSession(protocolClass: StubURLProtocol.self))

        let result = await checker.check(baseURL: URL(string: "http://example.com")!)

        if case let .offline(description) = result {
            XCTAssertNotNil(description)
        } else {
            XCTFail("Expected offline state")
        }
    }

    func testFallsBackToApiStatusWhenDirectStatusFails() async {
        let expectation = expectation(description: "Both endpoints queried")
        expectation.expectedFulfillmentCount = 2

        var requestedPaths: [String] = []

        StubURLProtocol.requestHandler = { request in
            requestedPaths.append(request.url!.path)
            expectation.fulfill()

            if request.url!.path == "/status" {
                let response = HTTPURLResponse(url: request.url!,
                                               statusCode: 404,
                                               httpVersion: nil,
                                               headerFields: nil)!
                return (response, Data("{}".utf8))
            } else {
                let response = HTTPURLResponse(url: request.url!,
                                               statusCode: 200,
                                               httpVersion: nil,
                                               headerFields: ["Content-Type": "application/json"])!
                return (response, Data("{\"ok\":true}".utf8))
            }
        }

        let checker = HealthChecker(session: makeSession(protocolClass: StubURLProtocol.self))
        let result = await checker.check(baseURL: URL(string: "http://example.com")!)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .connected)
        XCTAssertEqual(requestedPaths, ["/status", "/api/status"])
    }

    func testDoesNotDuplicateApiSegmentWhenBaseURLAlreadyContainsIt() async {
        let expectation = expectation(description: "Single request")

        StubURLProtocol.requestHandler = { request in
            expectation.fulfill()
            XCTAssertEqual(request.url?.path, "/api/status")
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, Data("{\"ok\":true}".utf8))
        }

        let checker = HealthChecker(session: makeSession(protocolClass: StubURLProtocol.self))
        let result = await checker.check(baseURL: URL(string: "http://example.com/api")!)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(result, .connected)
    }

    func testOfflineWhenNetworkErrorOccurs() async {
        StubURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let checker = HealthChecker(session: makeSession(protocolClass: StubURLProtocol.self))
        let result = await checker.check(baseURL: URL(string: "http://example.com")!)

        if case let .offline(description) = result {
            XCTAssertNotNil(description)
        } else {
            XCTFail("Expected offline state")
        }
    }

    // MARK: - Helpers

    private func configureStub(statusCode: Int, data: Data) {
        StubURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: statusCode,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, data)
        }
    }

    private func makeSession(protocolClass: AnyClass) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }
}

final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    static var requestHandler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}
#endif
