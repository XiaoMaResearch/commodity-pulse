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
            let data = """
            {
              "quoteResponse": {
                "result": [
                  {
                    "symbol": "GC=F",
                    "regularMarketPrice": 2199.5,
                    "regularMarketChange": 12.3,
                    "regularMarketChangePercent": 0.56,
                    "regularMarketTime": 1710000000
                  },
                  {
                    "symbol": "CL=F",
                    "regularMarketPrice": 78.4,
                    "regularMarketChange": -1.2,
                    "regularMarketChangePercent": -1.51,
                    "regularMarketTime": 1710000000
                  },
                  {
                    "symbol": "NG=F",
                    "regularMarketPrice": 2.15,
                    "regularMarketChange": 0.03,
                    "regularMarketChangePercent": 1.4,
                    "regularMarketTime": 1710000000
                  },
                  {
                    "symbol": "SI=F",
                    "regularMarketPrice": 25.8,
                    "regularMarketChange": 0.2,
                    "regularMarketChangePercent": 0.8,
                    "regularMarketTime": 1710000000
                  }
                ]
              }
            }
            """.data(using: .utf8)!

            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession())
        let quotes = try await service.fetchQuotes()

        XCTAssertEqual(quotes.map(\.commodity), [.oil, .gas, .gold, .silver])
        XCTAssertEqual(quotes.first?.price, 78.4)
    }

    func testFetchHistoryParsesPoints() async throws {
        MockURLProtocol.handler = { request in
            let data = """
            {
              "chart": {
                "result": [
                  {
                    "timestamp": [1710000000, 1710003600, 1710007200],
                    "indicators": {
                      "quote": [
                        {
                          "close": [78.2, 78.5, 78.1]
                        }
                      ]
                    }
                  }
                ]
              }
            }
            """.data(using: .utf8)!

            return try MockURLProtocol.successResponse(for: request, data: data)
        }

        let service = CommodityService(session: makeSession())
        let points = try await service.fetchHistory(for: .oil, range: .oneDay)

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points.last?.price, 78.1)
    }

    func testFetchQuotesMapsNetworkError() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = CommodityService(session: makeSession())

        do {
            _ = try await service.fetchQuotes()
            XCTFail("Expected networkUnavailable error")
        } catch let error as CommodityServiceError {
            XCTAssertEqual(error, .networkUnavailable)
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
