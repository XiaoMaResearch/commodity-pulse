import XCTest
@testable import CommodityPulse

final class EnergyNewsServiceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockNewsURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockNewsURLProtocol.self)
        super.tearDown()
    }

    func testFetchNewsForceRefreshBypassesRequestCacheAndParsesLatestHeadline() async throws {
        MockNewsURLProtocol.handler = { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")

            let html = """
            <div class="tie-article" data-type="inbrief">
                <div class="article-type">In-brief analysis</div>
                <span class="date">Mar 26, 2026</span>
                <h1><a href="detail.php?id=67386">Middle East crude oil tanker rates reached a multi-decade high in March</a></h1>
                <p data-type="inbrief">
                    <img src="images/2026.03.26/main.svg" alt="tanker rates">
                </p>
                <div class="source"><span><strong>Data source:</strong> EIA</span></div>
                <hr>
                <p>Rates for very large crude carriers leaving the Middle East to Asia increased sharply in March 2026.</p>
                <a href="detail.php?id=67386" class="link-button">Read More &rsaquo;</a>
            </div>
            <div class="tie-article" data-type="inbrief">
                <div class="article-type">In-brief analysis</div>
                <span class="date">Mar 25, 2026</span>
                <h1><a href="detail.php?id=67385">U.S. coke production and consumption have declined more than 75% since 1980</a></h1>
                <p>Secondary article body for ordering checks.</p>
                <a href="detail.php?id=67385" class="link-button">Read More &rsaquo;</a>
            </div>
            """

            return try MockNewsURLProtocol.successResponse(for: request, body: html)
        }

        let service = EnergyNewsService(session: makeSession())
        let articles = try await service.fetchNews(forceRefresh: true)

        XCTAssertEqual(articles.count, 2)
        XCTAssertEqual(articles.first?.title, "Middle East crude oil tanker rates reached a multi-decade high in March")
        XCTAssertEqual(articles.first?.link.absoluteString, "https://www.eia.gov/todayinenergy/detail.php?id=67386")
        XCTAssertEqual(
            articles.first?.publishedAt,
            makeDate(year: 2026, month: 3, day: 26)
        )
    }

    func testFetchNewsThrowsWhenNoArticlesExist() async {
        MockNewsURLProtocol.handler = { request in
            return try MockNewsURLProtocol.successResponse(for: request, body: "<html><body>No matching articles</body></html>")
        }

        let service = EnergyNewsService(session: makeSession())

        do {
            _ = try await service.fetchNews(forceRefresh: true)
            XCTFail("Expected feedUnavailable")
        } catch let error as EnergyNewsServiceError {
            XCTAssertEqual(error, .feedUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockNewsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}

private final class MockNewsURLProtocol: URLProtocol {
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

    static func successResponse(for request: URLRequest, body: String) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
              let data = body.data(using: .utf8) else {
            throw URLError(.badURL)
        }

        return (response, data)
    }
}
