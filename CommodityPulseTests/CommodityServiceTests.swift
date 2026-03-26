import XCTest
@testable import CommodityPulse

final class CommodityServiceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testFetchQuotesParsesOrderedCommodities() async throws {
        MockURLProtocol.handler = { request in
            let data = try responseData(for: request)

            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key")
        let quotes = try await service.fetchQuotes(forceRefresh: false)

        XCTAssertEqual(quotes.map(\.commodity), [.wti, .brent, .naturalGas])
        XCTAssertEqual(quotes.first?.price, 78.4)
        XCTAssertEqual(quotes.first?.change, 1.2, accuracy: 0.001)
        XCTAssertEqual(quotes[1].price, 82.9)
        XCTAssertEqual(quotes[2].price, 3.25)
    }

    func testFetchHistoryParsesPoints() async throws {
        MockURLProtocol.handler = { request in
            let data = try responseData(for: request)

            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key")
        let points = try await service.fetchHistory(for: .wti, range: .oneDay, forceRefresh: false)

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.last?.price, 78.4)
    }

    func testFetchQuotesMapsNetworkError() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key")

        do {
            _ = try await service.fetchQuotes(forceRefresh: false)
            XCTFail("Expected networkUnavailable error")
        } catch let error as CommodityServiceError {
            XCTAssertEqual(error, .networkUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchQuotesMapsRateLimitNote() async {
        MockURLProtocol.handler = { request in
            let data = """
            {
              "error_message": "Too many requests. Please try again later."
            }
            """.data(using: .utf8)!

            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key", cacheMaxAge: 0)

        do {
            _ = try await service.fetchQuotes(forceRefresh: false)
            XCTFail("Expected rateLimited error")
        } catch let error as CommodityServiceError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testForceRefreshBypassesRequestCache() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")

            let data = try responseData(for: request)
            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key")
        _ = try await service.fetchQuotes(forceRefresh: true)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func responseData(for request: URLRequest) throws -> Data {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw URLError(.badURL)
    }

    let payload: String
    switch url.path {
    case "/fred/series/observations":
        let seriesID = components.queryItems?.first(where: { $0.name == "series_id" })?.value
        switch seriesID {
        case "DCOILWTICO":
            payload = """
            {
              "realtime_start": "2026-03-25",
              "realtime_end": "2026-03-25",
              "observation_start": "1776-07-04",
              "observation_end": "9999-12-31",
              "units": "lin",
              "output_type": 1,
              "file_type": "json",
              "order_by": "observation_date",
              "sort_order": "desc",
              "count": 2,
              "offset": 0,
              "limit": 400,
              "observations": [
                { "date": "2026-03-21", "value": "78.40" },
                { "date": "2026-03-20", "value": "77.20" }
              ]
            }
            """
        case "DCOILBRENTEU":
            payload = """
            {
              "realtime_start": "2026-03-25",
              "realtime_end": "2026-03-25",
              "observation_start": "1776-07-04",
              "observation_end": "9999-12-31",
              "units": "lin",
              "output_type": 1,
              "file_type": "json",
              "order_by": "observation_date",
              "sort_order": "desc",
              "count": 2,
              "offset": 0,
              "limit": 400,
              "observations": [
                { "date": "2026-03-21", "value": "82.90" },
                { "date": "2026-03-20", "value": "81.80" }
              ]
            }
            """
        case "DHHNGSP":
            payload = """
            {
              "realtime_start": "2026-03-25",
              "realtime_end": "2026-03-25",
              "observation_start": "1776-07-04",
              "observation_end": "9999-12-31",
              "units": "lin",
              "output_type": 1,
              "file_type": "json",
              "order_by": "observation_date",
              "sort_order": "desc",
              "count": 2,
              "offset": 0,
              "limit": 400,
              "observations": [
                { "date": "2026-03-21", "value": "3.25" },
                { "date": "2026-03-20", "value": "3.10" }
              ]
            }
            """
        default:
            throw URLError(.badURL)
        }
    default:
        throw URLError(.badServerResponse)
    }

    guard let data = payload.data(using: .utf8) else {
        throw URLError(.cannotDecodeRawData)
    }
    return data
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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

    override func stopLoading() {}

    static func successResponse(for request: URLRequest, data: Data) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badURL)
        }
        return (response, data)
    }
}
