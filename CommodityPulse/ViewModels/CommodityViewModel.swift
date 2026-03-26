import Foundation

@MainActor
final class CommodityViewModel: ObservableObject {
    @Published private(set) var quotes: [CommodityQuote] = []
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published private(set) var isLoading = false
    @Published var isAutoRefreshEnabled = false {
        didSet {
            defaults.set(isAutoRefreshEnabled, forKey: autoRefreshEnabledKey)
            if isAutoRefreshEnabled {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }

    @Published var selectedCommodity: Commodity?
    @Published var selectedChartRange: CommodityChartRange = .oneMonth
    @Published private(set) var historyPoints: [CommodityPricePoint] = []
    @Published private(set) var isHistoryLoading = false
    @Published var historyErrorMessage: String?
    private struct CachePayload: Codable {
        let quotes: [CommodityQuote]
        let lastUpdated: Date?
    }

    private struct HistoryCacheKey: Hashable {
        let commodity: Commodity
        let range: CommodityChartRange
    }

    private let service: CommodityServicing
    private let defaults: UserDefaults
    private let cacheKey = "commodityPulse.cachedQuotes.v1"
    private let autoRefreshEnabledKey = "commodityPulse.autoRefreshEnabled.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var historyCache: [HistoryCacheKey: [CommodityPricePoint]] = [:]
    private var autoRefreshTask: Task<Void, Never>?

    init(service: CommodityServicing = CommodityService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        loadAutoRefreshPreference()
        loadCache()
    }

    var displayedQuotes: [CommodityQuote] {
        quotes.sorted { lhs, rhs in
            lhs.commodity.displayOrder < rhs.commodity.displayOrder
        }
    }

    var isDataStale: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 12 * 60 * 60
    }

    func quote(for commodity: Commodity) -> CommodityQuote? {
        quotes.first { $0.commodity == commodity }
    }

    func refresh(force: Bool = false) async {
        if isLoading { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let newQuotes = try await fetchQuotesWithRetry(force: force)
            quotes = newQuotes
            lastUpdated = Date()
            errorMessage = nil
            infoMessage = force
                ? "Refreshed the latest official EIA market data. Historical charts still use FRED."
                : "Using the latest official EIA market data."
            persistCache()
        } catch {
            errorMessage = error.localizedDescription
            if !quotes.isEmpty {
                infoMessage = "Showing the latest available snapshot."
            }
        }
    }

    func startAutoRefresh() {
        guard isAutoRefreshEnabled else { return }
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard self?.isAutoRefreshEnabled == true else { return }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func openDetails(for commodity: Commodity) {
        selectedCommodity = commodity
        selectedChartRange = .oneMonth
        historyErrorMessage = nil
        historyPoints = []
        Task { await loadHistory(for: commodity, range: .oneMonth) }
    }

    func closeDetails() {
        selectedCommodity = nil
        historyPoints = []
        historyErrorMessage = nil
        isHistoryLoading = false
    }

    func refreshSelectedHistory(force: Bool = false) async {
        guard let commodity = selectedCommodity else { return }
        await loadHistory(for: commodity, range: selectedChartRange, force: force)
    }

    func setChartRange(_ range: CommodityChartRange) async {
        selectedChartRange = range
        await refreshSelectedHistory()
    }

    func clearCachedQuotes() {
        defaults.removeObject(forKey: cacheKey)
        quotes = []
        lastUpdated = nil
        errorMessage = nil
        infoMessage = "Cache cleared. Pull to refresh for the latest energy spot data."
    }

    private func loadHistory(for commodity: Commodity, range: CommodityChartRange, force: Bool = false) async {
        let key = HistoryCacheKey(commodity: commodity, range: range)

        if !force, let cached = historyCache[key], !cached.isEmpty {
            historyPoints = cached
            historyErrorMessage = nil
            return
        }

        isHistoryLoading = true
        defer { isHistoryLoading = false }

        do {
            let points = try await service.fetchHistory(for: commodity, range: range, forceRefresh: force)
            historyCache[key] = points

            if selectedCommodity == commodity && selectedChartRange == range {
                historyPoints = points
                historyErrorMessage = nil
            }
        } catch {
            if let cached = historyCache[key], !cached.isEmpty {
                historyPoints = cached
            }
            if selectedCommodity == commodity && selectedChartRange == range {
                historyErrorMessage = error.localizedDescription
            }
        }
    }

    private func fetchQuotesWithRetry(force: Bool, maxAttempts: Int = 3) async throws -> [CommodityQuote] {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await service.fetchQuotes(forceRefresh: force)
            } catch {
                lastError = error
                guard shouldRetry(error), attempt < maxAttempts else { throw error }
                let backoff = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                try? await Task.sleep(nanoseconds: backoff)
            }
        }

        throw lastError ?? CommodityServiceError.serverError
    }

    private func shouldRetry(_ error: Error) -> Bool {
        guard let serviceError = error as? CommodityServiceError else { return false }
        switch serviceError {
        case .requestTimedOut, .serverError, .networkUnavailable, .httpStatus:
            return true
        case .apiKeyMissing, .invalidResponse, .decodingFailed, .emptyPayload, .emptyHistory, .rateLimited, .providerMessage:
            return false
        }
    }

    private func persistCache() {
        let payload = CachePayload(quotes: quotes, lastUpdated: lastUpdated)
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func loadCache() {
        guard let data = defaults.data(forKey: cacheKey),
              let payload = try? decoder.decode(CachePayload.self, from: data) else { return }
        quotes = payload.quotes
        lastUpdated = payload.lastUpdated
        infoMessage = "Loaded cached prices while waiting for the latest official EIA market data."
    }

    private func loadAutoRefreshPreference() {
        guard defaults.object(forKey: autoRefreshEnabledKey) != nil else {
            isAutoRefreshEnabled = false
            return
        }
        isAutoRefreshEnabled = defaults.bool(forKey: autoRefreshEnabledKey)
    }

}

struct EnergyNewsItem: Identifiable, Equatable, Codable {
    let title: String
    let summary: String
    let link: URL
    let publishedAt: Date?

    var id: String { link.absoluteString }
}

protocol EnergyNewsServicing {
    func fetchNews(forceRefresh: Bool) async throws -> [EnergyNewsItem]
}

enum EnergyNewsServiceError: LocalizedError, Equatable {
    case feedUnavailable
    case invalidFeed
    case emptyFeed

    var errorDescription: String? {
        switch self {
        case .feedUnavailable:
            return "The energy news feed is temporarily unavailable."
        case .invalidFeed:
            return "The energy news feed returned an unexpected format."
        case .emptyFeed:
            return "No energy news is available right now."
        }
    }
}

@MainActor
final class EnergyNewsViewModel: ObservableObject {
    @Published private(set) var articles: [EnergyNewsItem] = []
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isShowingCachedArticles = false

    private let service: EnergyNewsServicing
    private let defaults: UserDefaults
    private let cacheKey = "commodityPulse.cachedEnergyNews.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct CachePayload: Codable {
        let articles: [EnergyNewsItem]
        let lastUpdated: Date?
    }

    init(service: EnergyNewsServicing = EnergyNewsService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        loadCache()
    }

    func refreshIfNeeded() async {
        guard articles.isEmpty else { return }
        await refresh(force: true)
    }

    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force, !articles.isEmpty { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            articles = try await service.fetchNews(forceRefresh: force)
            lastUpdated = Date()
            errorMessage = nil
            isShowingCachedArticles = false
            persistCache()
        } catch {
            if articles.isEmpty {
                errorMessage = error.localizedDescription
                isShowingCachedArticles = false
            } else {
                errorMessage = nil
                isShowingCachedArticles = true
            }
        }
    }

    private func persistCache() {
        let payload = CachePayload(articles: articles, lastUpdated: lastUpdated)
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func loadCache() {
        guard let data = defaults.data(forKey: cacheKey),
              let payload = try? decoder.decode(CachePayload.self, from: data) else {
            return
        }

        articles = payload.articles
        lastUpdated = payload.lastUpdated
        isShowingCachedArticles = !payload.articles.isEmpty
    }

    func clearCachedNews() {
        defaults.removeObject(forKey: cacheKey)
        articles = []
        lastUpdated = nil
        errorMessage = nil
        isShowingCachedArticles = false
    }
}

struct EnergyNewsService: EnergyNewsServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchNews(forceRefresh: Bool = false) async throws -> [EnergyNewsItem] {
        guard !ReleaseConfiguration.energyNewsPageURLs.isEmpty else {
            throw EnergyNewsServiceError.invalidFeed
        }

        for pageURL in ReleaseConfiguration.energyNewsPageURLs {
            do {
                let items = try await fetchNews(from: pageURL, forceRefresh: forceRefresh)
                if !items.isEmpty {
                    return Array(items.prefix(20))
                }
            } catch {
                continue
            }
        }

        throw EnergyNewsServiceError.feedUnavailable
    }

    private func fetchNews(from pageURL: URL, forceRefresh: Bool) async throws -> [EnergyNewsItem] {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        if forceRefresh {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EnergyNewsServiceError.feedUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EnergyNewsServiceError.feedUnavailable
        }

        let parser = EnergyNewsHTMLParser(data: data, baseURL: pageURL)
        let items = try parser.parse()

        guard !items.isEmpty else {
            throw EnergyNewsServiceError.emptyFeed
        }

        return items
    }
}

private struct EnergyNewsHTMLParser {
    private let data: Data
    private let baseURL: URL

    init(data: Data, baseURL: URL) {
        self.data = data
        self.baseURL = baseURL
    }

    func parse() throws -> [EnergyNewsItem] {
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw EnergyNewsServiceError.invalidFeed
        }

        let nsHTML = html as NSString
        let matches = Self.articlePattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        let items = matches.compactMap { match -> EnergyNewsItem? in
            guard match.numberOfRanges == 5,
                  let dateRange = Range(match.range(at: 1), in: html),
                  let linkRange = Range(match.range(at: 2), in: html),
                  let titleRange = Range(match.range(at: 3), in: html),
                  let bodyRange = Range(match.range(at: 4), in: html) else {
                return nil
            }

            let dateText = html[dateRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let relativeLink = html[linkRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = sanitizeHTML(String(html[titleRange]))
            let summary = extractSummary(from: String(html[bodyRange]))

            guard !title.isEmpty,
                  let link = URL(string: relativeLink, relativeTo: baseURL)?.absoluteURL else {
                return nil
            }

            return EnergyNewsItem(
                title: title,
                summary: summary.isEmpty ? "Tap to read the full article on EIA." : summary,
                link: link,
                publishedAt: Self.pageDateFormatter.date(from: dateText)
            )
        }

        guard !items.isEmpty else {
            throw EnergyNewsServiceError.invalidFeed
        }

        return items.sorted { lhs, rhs in
            (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
        }
    }

    private func extractSummary(from articleHTML: String) -> String {
        let cleanedHTML = Self.stripDecorativeElements(in: articleHTML)
        let nsArticle = cleanedHTML as NSString
        let paragraphMatches = Self.paragraphPattern.matches(
            in: cleanedHTML,
            range: NSRange(location: 0, length: nsArticle.length)
        )

        for match in paragraphMatches {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: cleanedHTML) else {
                continue
            }

            let candidate = sanitizeHTML(String(cleanedHTML[range]))
            if candidate.count >= 40 {
                return candidate
            }
        }

        return sanitizeHTML(cleanedHTML)
    }

    private static func stripDecorativeElements(in html: String) -> String {
        var result = html
        for pattern in removalPatterns {
            result = replace(pattern: pattern, in: result, with: " ")
        }
        return result
    }

    private func sanitizeHTML(_ value: String) -> String {
        let stripped = Self.replace(pattern: "<[^>]+>", in: value, with: " ")
        return Self.decodeHTML(in: stripped)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func decodeHTML(in value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&lsquo;", with: "'")
            .replacingOccurrences(of: "&ldquo;", with: "\"")
            .replacingOccurrences(of: "&rdquo;", with: "\"")
            .replacingOccurrences(of: "&mdash;", with: "--")
            .replacingOccurrences(of: "&ndash;", with: "-")
            .replacingOccurrences(of: "&rsaquo;", with: ">")
            .replacingOccurrences(of: "&lsaquo;", with: "<")
            .replacingOccurrences(of: "&#160;", with: " ")
    }

    private static let pageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let articlePattern = try! NSRegularExpression(
        pattern: #"<span class="date">\s*([^<]+?)\s*</span>\s*<h1>\s*<a href="([^"]+)">(.+?)</a>\s*</h1>(.*?)<a href="[^"]+" class="link-button">Read More"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let paragraphPattern = try! NSRegularExpression(
        pattern: #"<p(?:\s[^>]*)?>(.*?)</p>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let removalPatterns = [
        #"<div class="source">.*?</div>"#,
        #"<img[^>]*>"#,
        #"<hr[^>]*>"#,
        #"<figure[^>]*>.*?</figure>"#,
        #"<script[^>]*>.*?</script>"#
    ]
}
