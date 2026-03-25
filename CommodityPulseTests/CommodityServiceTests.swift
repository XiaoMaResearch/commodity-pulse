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
        let quotes = try await service.fetchQuotes()

        XCTAssertEqual(quotes.map(\.commodity), [.wti, .brent, .naturalGas, .gold, .silver, .corn])
        XCTAssertEqual(quotes.first?.price, 78.4)
        XCTAssertEqual(quotes.first?.change, 1.2, accuracy: 0.001)
    }

    func testFetchHistoryParsesPoints() async throws {
        MockURLProtocol.handler = { request in
            let data = try responseData(for: request)

            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key")
        let points = try await service.fetchHistory(for: .wti, range: .oneDay)

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.last?.price, 78.4)
    }

    func testFetchQuotesMapsNetworkError() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key")

        do {
            _ = try await service.fetchQuotes()
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
              "Note": "Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day."
            }
            """.data(using: .utf8)!

            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession(), apiKey: "test-key", cacheMaxAge: 0)

        do {
            _ = try await service.fetchQuotes()
            XCTFail("Expected rateLimited error")
        } catch let error as CommodityServiceError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func responseData(for request: URLRequest) throws -> Data {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let function = components.queryItems?.first(where: { $0.name == "function" })?.value else {
        throw URLError(.badURL)
    }

    let symbol = components.queryItems?.first(where: { $0.name == "symbol" })?.value

    let payload: String
    switch (function, symbol) {
    case ("WTI", _):
        payload = """
        {
          "name": "WTI",
          "interval": "daily",
          "unit": "USD",
          "data": [
            { "date": "2026-03-20", "value": "77.20" },
            { "date": "2026-03-21", "value": "78.40" }
          ]
        }
        """
    case ("BRENT", _):
        payload = """
        {
          "name": "Brent",
          "interval": "daily",
          "unit": "USD",
          "data": [
            { "date": "2026-03-20", "value": "80.90" },
            { "date": "2026-03-21", "value": "81.70" }
          ]
        }
        """
    case ("NATURAL_GAS", _):
        payload = """
        {
          "name": "Natural Gas",
          "interval": "daily",
          "unit": "USD",
          "data": [
            { "date": "2026-03-20", "value": "2.10" },
            { "date": "2026-03-21", "value": "2.15" }
          ]
        }
        """
    case ("GOLD_SILVER_HISTORY", "GOLD"):
        payload = """
        {
          "name": "Gold",
          "interval": "daily",
          "unit": "USD",
          "data": [
            { "date": "2026-03-20", "value": "2190.20" },
            { "date": "2026-03-21", "value": "2199.50" }
          ]
        }
        """
    case ("GOLD_SILVER_HISTORY", "SILVER"):
        payload = """
        {
          "name": "Silver",
          "interval": "daily",
          "unit": "USD",
          "data": [
            { "date": "2026-03-20", "value": "25.60" },
            { "date": "2026-03-21", "value": "25.80" }
          ]
        }
        """
    case ("CORN", _):
        payload = """
        {
          "name": "Corn",
          "interval": "monthly",
          "unit": "USD",
          "data": [
            { "date": "2025-12-01", "value": "220.20" },
            { "date": "2026-01-01", "value": "225.80" },
            { "date": "2026-02-01", "value": "229.10" },
            { "date": "2026-03-01", "value": "231.40" }
          ]
        }
        """
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
