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

        XCTAssertEqual(quotes.map(\.commodity), [.wti, .gold])
        XCTAssertEqual(quotes.first?.price, 78.4)
        XCTAssertEqual(quotes.first?.change, 1.2, accuracy: 0.001)
        XCTAssertEqual(quotes.last?.price, 2341.0)
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
              "message": "Request limit reached. Please upgrade your plan."
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
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw URLError(.badURL)
    }

    let symbol = components.queryItems?.first(where: { $0.name == "symbol" })?.value

    let payload: String
    switch (url.path, symbol) {
    case ("/stable/batch-commodity-quotes", _):
        payload = """
        [
          {
            "symbol": "CLUSD",
            "price": 78.4,
            "change": 1.2,
            "changesPercentage": 1.55,
            "timestamp": 1774051200
          },
          {
            "symbol": "GCUSD",
            "price": 2341.0,
            "change": 13.0,
            "changesPercentage": 0.56,
            "timestamp": 1774051200
          }
        ]
        """
    case ("/stable/historical-price-eod/light", "CLUSD"):
        payload = """
        [
          { "date": "2026-03-20", "price": "77.20" },
          { "date": "2026-03-21", "price": "78.40" }
        ]
        """
    case ("/stable/historical-price-eod/light", "GCUSD"):
        payload = """
        [
          { "date": "2026-03-20", "price": "2328.00" },
          { "date": "2026-03-21", "price": "2341.00" }
        ]
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
