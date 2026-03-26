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
    @Published private(set) var sparklinePointsByCommodity: [Commodity: [CommodityPricePoint]] = [:]
    @Published private(set) var isRefreshingSparklines = false

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
    private var sparklineLastUpdated: Date?
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

    var topGainer: CommodityQuote? {
        quotes.max(by: { $0.changePercent < $1.changePercent })
    }

    var topLoser: CommodityQuote? {
        quotes.min(by: { $0.changePercent < $1.changePercent })
    }

    var isDataStale: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 12 * 60 * 60
    }

    func quote(for commodity: Commodity) -> CommodityQuote? {
        quotes.first { $0.commodity == commodity }
    }

    func sparklinePoints(for commodity: Commodity) -> [CommodityPricePoint] {
        sparklinePointsByCommodity[commodity] ?? []
    }

    func refresh() async {
        if isLoading { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let newQuotes = try await fetchQuotesWithRetry()
            quotes = newQuotes
            lastUpdated = Date()
            errorMessage = nil
            infoMessage = "Using daily WTI spot data from EIA via FRED."
            persistCache()
            Task { [weak self] in
                await self?.refreshSparklinesIfNeeded()
            }
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

    func refreshSparklinesIfNeeded(force: Bool = false) async {
        if isRefreshingSparklines { return }

        if !force,
           let last = sparklineLastUpdated,
           Date().timeIntervalSince(last) < 240,
           !sparklinePointsByCommodity.isEmpty {
            return
        }

        isRefreshingSparklines = true
        defer { isRefreshingSparklines = false }

        var collected: [Commodity: [CommodityPricePoint]] = [:]
        for commodity in Commodity.supportedCases {
            do {
                let points = try await service.fetchHistory(for: commodity, range: .oneMonth)
                let trimmed = Array(points.suffix(32))
                if !trimmed.isEmpty {
                    collected[commodity] = trimmed
                }
            } catch {
                continue
            }
        }

        if !collected.isEmpty {
            sparklinePointsByCommodity.merge(collected) { _, new in new }
            sparklineLastUpdated = Date()
        }
    }

    func clearCachedQuotes() {
        defaults.removeObject(forKey: cacheKey)
        quotes = []
        lastUpdated = nil
        errorMessage = nil
        sparklinePointsByCommodity = [:]
        sparklineLastUpdated = nil
        infoMessage = "Cache cleared. Pull to refresh for the latest WTI spot data."
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
            let points = try await service.fetchHistory(for: commodity, range: range)
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

    private func fetchQuotesWithRetry(maxAttempts: Int = 3) async throws -> [CommodityQuote] {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await service.fetchQuotes()
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
        infoMessage = "Loaded cached WTI prices while waiting for the latest provider snapshot."
    }

    private func loadAutoRefreshPreference() {
        guard defaults.object(forKey: autoRefreshEnabledKey) != nil else {
            isAutoRefreshEnabled = false
            return
        }
        isAutoRefreshEnabled = defaults.bool(forKey: autoRefreshEnabledKey)
    }

}

struct EnergyNewsItem: Identifiable, Equatable {
    let title: String
    let summary: String
    let link: URL
    let publishedAt: Date?

    var id: String { link.absoluteString }
}

protocol EnergyNewsServicing {
    func fetchNews() async throws -> [EnergyNewsItem]
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

    private let service: EnergyNewsServicing

    init(service: EnergyNewsServicing = EnergyNewsService()) {
        self.service = service
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
            articles = try await service.fetchNews()
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EnergyNewsService: EnergyNewsServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchNews() async throws -> [EnergyNewsItem] {
        guard let feedURL = ReleaseConfiguration.energyNewsFeedURL else {
            throw EnergyNewsServiceError.invalidFeed
        }

        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 20
        request.setValue("CommodityPulse/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")

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

        let parser = EnergyNewsRSSParser(data: data)
        let items = try parser.parse()

        guard !items.isEmpty else {
            throw EnergyNewsServiceError.emptyFeed
        }

        return Array(items.prefix(20))
    }
}

private final class EnergyNewsRSSParser: NSObject, XMLParserDelegate {
    private let data: Data

    private var items: [EnergyNewsItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var insideItem = false

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [EnergyNewsItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw EnergyNewsServiceError.invalidFeed
        }

        return items.sorted { lhs, rhs in
            (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentSummary = ""
            currentLink = ""
            currentPubDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "description":
            currentSummary += string
        case "link":
            currentLink += string
        case "pubDate":
            currentPubDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard insideItem,
              currentElement == "description",
              let string = String(data: CDATABlock, encoding: .utf8) else {
            return
        }
        currentSummary += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "item" else {
            currentElement = ""
            return
        }

        insideItem = false

        let title = sanitize(currentTitle)
        let summary = sanitizeHTML(currentSummary)
        let trimmedLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty,
              let link = URL(string: trimmedLink) else {
            return
        }

        items.append(
            EnergyNewsItem(
                title: title,
                summary: summary,
                link: link,
                publishedAt: Self.pubDateFormatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        )
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeHTML(_ value: String) -> String {
        let stripped = value.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return sanitize(stripped)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static let pubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
