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
        let todayRSS = makeRSSDateString(daysFromNow: 0)
        let yesterdayRSS = makeRSSDateString(daysFromNow: -1)
        let todayHTML = makeHTMLDateString(daysFromNow: 0)

        MockNewsURLProtocol.handler = { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")

            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.absoluteString.contains("todayinenergy.xml") {
                let rss = """
                <?xml version="1.0" encoding="UTF-8"?>
                <rss version="2.0">
                  <channel>
                    <item>
                      <title>Middle East crude oil tanker rates reached a multi-decade high in March</title>
                      <link>https://www.eia.gov/todayinenergy/detail.php?id=67386</link>
                      <pubDate>\(todayRSS)</pubDate>
                      <description>Today item from EIA.</description>
                    </item>
                    <item>
                      <title>Older EIA article that should not be shown</title>
                      <link>https://www.eia.gov/todayinenergy/detail.php?id=60000</link>
                      <pubDate>\(yesterdayRSS)</pubDate>
                      <description>Old item.</description>
                    </item>
                  </channel>
                </rss>
                """
                return try MockNewsURLProtocol.successResponse(for: request, body: rss)
            }

            if url.absoluteString.contains("press_rss.xml") {
                let rss = """
                <?xml version="1.0" encoding="UTF-8"?>
                <rss version="2.0">
                  <channel>
                    <item>
                      <title>EIA launches pilot survey on energy use at data centers</title>
                      <link>/pressroom/releases/press585.php</link>
                      <pubDate>\(todayRSS)</pubDate>
                      <description>Press release item.</description>
                    </item>
                  </channel>
                </rss>
                """
                return try MockNewsURLProtocol.successResponse(for: request, body: rss)
            }

            if url.absoluteString.contains("oilprice.com/rss.xml") {
                let rss = """
                <?xml version="1.0" encoding="UTF-8"?>
                <rss version="2.0">
                  <channel>
                    <item>
                      <title>StanChart: Europe's Gas Prices Could Spike Above $90/MWh By The Summer</title>
                      <link>https://oilprice.com/Energy/Natural-Gas/StanChart-Europes-Gas-Prices-Could-Spike-Above-90MWh-By-The-Summer.html</link>
                      <pubDate>\(todayRSS)</pubDate>
                      <description>Natural gas headline.</description>
                    </item>
                  </channel>
                </rss>
                """
                return try MockNewsURLProtocol.successResponse(for: request, body: rss)
            }

            let html = """
            <div class="tie-article" data-type="inbrief">
                <div class="article-type">In-brief analysis</div>
                <span class="date">\(todayHTML)</span>
                <h1><a href="detail.php?id=67386">Middle East crude oil tanker rates reached a multi-decade high in March</a></h1>
                <p>Duplicate of an RSS item to verify dedupe by link.</p>
                <a href="detail.php?id=67386" class="link-button">Read More &rsaquo;</a>
            </div>
            """
            return try MockNewsURLProtocol.successResponse(for: request, body: html)
        }

        let service = EnergyNewsService(session: makeSession())
        let articles = try await service.fetchNews(forceRefresh: true)

        XCTAssertEqual(articles.count, 3)
        XCTAssertTrue(articles.contains(where: { $0.link.absoluteString == "https://www.eia.gov/todayinenergy/detail.php?id=67386" }))
        XCTAssertTrue(articles.contains(where: { $0.link.absoluteString == "https://www.eia.gov/pressroom/releases/press585.php" }))
        XCTAssertTrue(articles.contains(where: { $0.link.absoluteString.contains("oilprice.com/Energy/Natural-Gas/StanChart-Europes-Gas-Prices-Could-Spike-Above-90MWh-By-The-Summer.html") }))
        XCTAssertTrue(articles.allSatisfy { item in
            guard let publishedAt = item.publishedAt else { return false }
            return Calendar.current.isDateInToday(publishedAt)
        })
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

    func testFetchNewsThrowsEmptyFeedWhenOnlyOlderItemsExist() async {
        let yesterdayRSS = makeRSSDateString(daysFromNow: -1)

        MockNewsURLProtocol.handler = { request in
            let rss = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0">
              <channel>
                <item>
                  <title>Older item only</title>
                  <link>https://www.eia.gov/todayinenergy/detail.php?id=50000</link>
                  <pubDate>\(yesterdayRSS)</pubDate>
                  <description>Old content.</description>
                </item>
              </channel>
            </rss>
            """
            return try MockNewsURLProtocol.successResponse(for: request, body: rss)
        }

        let service = EnergyNewsService(session: makeSession())

        do {
            _ = try await service.fetchNews(forceRefresh: true)
            XCTFail("Expected emptyFeed")
        } catch let error as EnergyNewsServiceError {
            XCTAssertEqual(error, .emptyFeed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockNewsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeRSSDateString(daysFromNow: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        return formatter.string(from: date)
    }

    private func makeHTMLDateString(daysFromNow: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d, yyyy"
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        return formatter.string(from: date)
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
