import Foundation

protocol CommodityServicing {
    func fetchQuotes(forceRefresh: Bool) async throws -> [CommodityQuote]
    func fetchHistory(for commodity: Commodity, range: CommodityChartRange, forceRefresh: Bool) async throws -> [CommodityPricePoint]
}

enum CommodityServiceError: LocalizedError, Equatable {
    case apiKeyMissing
    case networkUnavailable
    case requestTimedOut
    case serverError
    case httpStatus(Int)
    case invalidResponse
    case decodingFailed
    case emptyPayload
    case emptyHistory
    case rateLimited
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Add your FRED API key in the Xcode scheme environment or ReleaseConfiguration before loading historical charts."
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .requestTimedOut:
            return "Request timed out. Please try again."
        case .serverError:
            return "The energy price service is temporarily unavailable."
        case .httpStatus(let code):
            return "The price service returned HTTP \(code)."
        case .invalidResponse:
            return "The price service returned an unexpected response."
        case .decodingFailed:
            return "The price data format changed and could not be parsed."
        case .emptyPayload:
            return "No quote data was returned."
        case .emptyHistory:
            return "No historical price data is available for this period."
        case .rateLimited:
            return "FRED request limit reached. Wait and try again later."
        case .providerMessage(let message):
            return message
        }
    }
}

private actor CommoditySeriesCache {
    struct Entry {
        let points: [CommodityPricePoint]
        let fetchedAt: Date
    }

    private var entries: [Commodity: Entry] = [:]

    func freshSeries(for commodity: Commodity, maxAge: TimeInterval) -> [CommodityPricePoint]? {
        guard let entry = entries[commodity],
              Date().timeIntervalSince(entry.fetchedAt) <= maxAge else {
            return nil
        }
        return entry.points
    }

    func staleSeries(for commodity: Commodity) -> [CommodityPricePoint]? {
        entries[commodity]?.points
    }

    func store(_ points: [CommodityPricePoint], for commodity: Commodity) {
        entries[commodity] = Entry(points: points, fetchedAt: Date())
    }
}

struct CommodityService: CommodityServicing {
    private let session: URLSession
    private let fredAPIKey: String
    private let eiaAPIKey: String
    private let cache: CommoditySeriesCache
    private let cacheMaxAge: TimeInterval
    private let dailyPricesURL = URL(string: "https://www.eia.gov/todayinenergy/prices.php")!

    init(
        session: URLSession = .shared,
        apiKey: String = ReleaseConfiguration.fredAPIKey,
        marketAPIKey: String? = nil,
        cacheMaxAge: TimeInterval = 55
    ) {
        self.session = session
        self.fredAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.eiaAPIKey = Self.resolveEIAAPIKey(from: marketAPIKey)
        self.cache = CommoditySeriesCache()
        self.cacheMaxAge = cacheMaxAge
    }

    func fetchQuotes(forceRefresh: Bool = false) async throws -> [CommodityQuote] {
        if !eiaAPIKey.isEmpty {
            return try await fetchAPIQuotes(forceRefresh: forceRefresh)
        }

        let html = try await performHTMLRequest(url: dailyPricesURL, forceRefresh: forceRefresh)
        let parser = EIADailyPricesParser(html: html)
        return try parser.parseQuotes()
    }

    func fetchHistory(for commodity: Commodity, range: CommodityChartRange, forceRefresh: Bool = false) async throws -> [CommodityPricePoint] {
        guard !fredAPIKey.isEmpty else {
            throw CommodityServiceError.apiKeyMissing
        }

        let points = try await loadSeries(for: commodity, forceRefresh: forceRefresh)
        let filtered = Array(points.suffix(range.requestedPointCount))

        if filtered.isEmpty {
            throw CommodityServiceError.emptyHistory
        }
        return filtered
    }

    private func loadSeries(for commodity: Commodity, forceRefresh: Bool) async throws -> [CommodityPricePoint] {
        if !forceRefresh,
           let cached = await cache.freshSeries(for: commodity, maxAge: cacheMaxAge),
           !cached.isEmpty {
            return cached
        }

        let url = try makeObservationsURL(for: commodity)

        do {
            let data = try await performJSONRequest(url: url, forceRefresh: forceRefresh)
            let root = try decodeRootObject(from: data)
            let points = try decodeSeries(from: root)

            if points.isEmpty {
                throw CommodityServiceError.emptyHistory
            }

            await cache.store(points, for: commodity)
            return points
        } catch let serviceError as CommodityServiceError {
            if let cached = await cache.staleSeries(for: commodity),
               !cached.isEmpty,
               shouldFallbackToCachedSeries(for: serviceError) {
                return cached
            }
            throw serviceError
        } catch {
            if let cached = await cache.staleSeries(for: commodity), !cached.isEmpty {
                return cached
            }
            throw CommodityServiceError.serverError
        }
    }

    private func makeObservationsURL(for commodity: Commodity) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.stlouisfed.org"
        components.path = "/fred/series/observations"
        components.queryItems = [
            URLQueryItem(name: "series_id", value: commodity.fredSeriesID),
            URLQueryItem(name: "api_key", value: fredAPIKey),
            URLQueryItem(name: "file_type", value: "json"),
            URLQueryItem(name: "sort_order", value: "desc"),
            URLQueryItem(name: "limit", value: "400")
        ]

        guard let url = components.url else {
            throw CommodityServiceError.invalidResponse
        }
        return url
    }

    private func decodeRootObject(from data: Data) throws -> [String: Any] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CommodityServiceError.decodingFailed
        }

        guard let root = jsonObject as? [String: Any] else {
            throw CommodityServiceError.invalidResponse
        }

        if let providerError = providerError(from: root) {
            throw providerError
        }

        return root
    }

    private func fetchAPIQuotes(forceRefresh: Bool) async throws -> [CommodityQuote] {
        var quotes: [CommodityQuote] = []

        for commodity in Commodity.supportedCases {
            let url = try makeEIASeriesURL(for: commodity)
            let data = try await performJSONRequest(url: url, forceRefresh: forceRefresh)
            let root = try decodeRootObject(from: data)
            let points = try decodeEIASeries(from: root)

            guard let quote = makeQuote(from: points, commodity: commodity) else {
                throw CommodityServiceError.emptyPayload
            }

            quotes.append(quote)
        }

        guard !quotes.isEmpty else {
            throw CommodityServiceError.emptyPayload
        }

        return quotes.sorted { $0.commodity.displayOrder < $1.commodity.displayOrder }
    }

    private func makeEIASeriesURL(for commodity: Commodity) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.eia.gov"
        components.path = "/series/"
        components.queryItems = [
            URLQueryItem(name: "api_key", value: eiaAPIKey),
            URLQueryItem(name: "series_id", value: commodity.eiaSeriesID),
            URLQueryItem(name: "num", value: "2"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "out", value: "json")
        ]

        guard let url = components.url else {
            throw CommodityServiceError.invalidResponse
        }
        return url
    }

    private func mapProviderMessage(_ message: String) -> CommodityServiceError {
        let normalized = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()

        if lowered.contains("api key") || lowered.contains("api_key") {
            return .apiKeyMissing
        }

        if lowered.contains("too many requests")
            || lowered.contains("rate limit")
            || lowered.contains("limit exceeded") {
            return .rateLimited
        }

        return .providerMessage(normalized)
    }

    private func decodeSeries(from root: [String: Any]) throws -> [CommodityPricePoint] {
        guard let items = root["observations"] as? [[String: Any]] else {
#if DEBUG
            print("CommodityService unexpected FRED payload keys=\(Array(root.keys).sorted())")
#endif
            throw CommodityServiceError.decodingFailed
        }

        let points = items.compactMap { item -> CommodityPricePoint? in
            guard let dateString = item["date"] as? String,
                  let rawValue = item["value"],
                  let price = parseNumericValue(rawValue),
                  let date = parseDate(dateString) else {
                return nil
            }

            return CommodityPricePoint(date: date, price: price)
        }
        .sorted { $0.date < $1.date }

        return points
    }

    private func decodeEIASeries(from root: [String: Any]) throws -> [CommodityPricePoint] {
        guard let series = root["series"] as? [[String: Any]],
              let entry = series.first,
              let rows = entry["data"] as? [[Any]] else {
#if DEBUG
            print("CommodityService unexpected EIA payload keys=\(Array(root.keys).sorted())")
#endif
            throw CommodityServiceError.decodingFailed
        }

        let points = rows.compactMap { row -> CommodityPricePoint? in
            guard row.count >= 2,
                  let period = row[0] as? String,
                  let date = parseEIASeriesDate(period),
                  let price = parseNumericValue(row[1]) else {
                return nil
            }

            return CommodityPricePoint(date: date, price: price)
        }
        .sorted { $0.date < $1.date }

        if points.isEmpty {
            throw CommodityServiceError.emptyPayload
        }

        return points
    }

    private func providerError(from root: [String: Any]) -> CommodityServiceError? {
        if let errorObject = root["error"] as? [String: Any] {
            if let message = errorObject["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return mapProviderMessage(message)
            }

            if let code = errorObject["code"] as? String,
               code.uppercased().contains("API_KEY") {
                return .apiKeyMissing
            }
        }

        if let message = root["error_message"] as? String,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mapProviderMessage(message)
        }

        if let message = root["message"] as? String,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mapProviderMessage(message)
        }

        return nil
    }

    private func makeQuote(from points: [CommodityPricePoint], commodity: Commodity) -> CommodityQuote? {
        guard let latest = points.last else {
            return nil
        }

        let previous = points.dropLast().last ?? latest
        let change = latest.price - previous.price
        let changePercent = previous.price == 0 ? 0 : (change / previous.price) * 100

        return CommodityQuote(
            commodity: commodity,
            price: latest.price,
            change: change,
            changePercent: changePercent,
            marketTime: latest.date
        )
    }

    private func shouldFallbackToCachedSeries(for error: CommodityServiceError) -> Bool {
        switch error {
        case .requestTimedOut, .serverError, .networkUnavailable, .httpStatus, .rateLimited:
            return true
        case .apiKeyMissing, .invalidResponse, .decodingFailed, .emptyPayload, .emptyHistory, .providerMessage:
            return false
        }
    }

    private func performJSONRequest(url: URL, forceRefresh: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("CommodityPulse/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyRefreshPolicy(to: &request, forceRefresh: forceRefresh)

        return try await performRequest(request)
    }

    private func performHTMLRequest(url: URL, forceRefresh: Bool) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        applyRefreshPolicy(to: &request, forceRefresh: forceRefresh)

        let data = try await performRequest(request)
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw CommodityServiceError.decodingFailed
        }
        return html
    }

    private func applyRefreshPolicy(to request: inout URLRequest, forceRefresh: Bool) {
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        if forceRefresh {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw CommodityServiceError.requestTimedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                throw CommodityServiceError.networkUnavailable
            default:
                throw CommodityServiceError.serverError
            }
        } catch {
            throw CommodityServiceError.serverError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommodityServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
#if DEBUG
            let bodyPreview = String(data: data.prefix(240), encoding: .utf8) ?? "<non-text body>"
            print("CommodityService non-200 status=\(httpResponse.statusCode) preview=\(bodyPreview)")
#endif
            throw CommodityServiceError.httpStatus(httpResponse.statusCode)
        }

#if DEBUG
        if let bodyPreview = String(data: data.prefix(240), encoding: .utf8) {
            print("CommodityService response status=\(httpResponse.statusCode) preview=\(bodyPreview)")
        }
#endif

        return data
    }

    private func parseNumericValue(_ rawValue: Any) -> Double? {
        if let doubleValue = rawValue as? Double {
            return doubleValue
        }

        if let stringValue = rawValue as? String {
            let sanitized = stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "$", with: "")

            guard sanitized != "." else { return nil }
            return Double(sanitized)
        }

        if let numberValue = rawValue as? NSNumber {
            return numberValue.doubleValue
        }

        return nil
    }

    private func parseDate(_ string: String) -> Date? {
        Self.dateFormatter.date(from: string)
    }

    private func parseEIASeriesDate(_ string: String) -> Date? {
        Self.eiaSeriesDateFormatter.date(from: string)
    }

    private static func resolveEIAAPIKey(from override: String?) -> String {
        if let override {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "EIA_API_KEY") as? String {
            let trimmed = bundleKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let environmentKey = ProcessInfo.processInfo.environment["EIA_API_KEY"] {
            let trimmed = environmentKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return ""
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let eiaSeriesDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

private struct EIADailyPricesParser {
    let html: String

    func parseQuotes() throws -> [CommodityQuote] {
        let quoteDate = parseQuoteDate()
        let pageDate = parsePageDate()

        let quotes = [
            makeOilQuote(for: .wti, label: "WTI", marketDate: quoteDate),
            makeOilQuote(for: .brent, label: "Brent", marketDate: quoteDate),
            makeNaturalGasQuote(for: .naturalGas, region: "Louisiana", marketDate: pageDate ?? quoteDate)
        ]
        .compactMap { $0 }

        let ordered = Commodity.supportedCases.compactMap { commodity in
            quotes.first(where: { $0.commodity == commodity })
        }

        guard !ordered.isEmpty else {
            throw CommodityServiceError.decodingFailed
        }

        return ordered
    }

    private func makeOilQuote(for commodity: Commodity, label: String, marketDate: Date?) -> CommodityQuote? {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"<td class="s2">\s*\#(escapedLabel)\s*</td>\s*<td class="d1">\s*([^<]+?)\s*</td>\s*<td class="[^"]+">\s*([^<]+?)\s*</td>"#
        guard let match = firstMatch(for: pattern),
              let price = parseDouble(match[0]),
              let percentChange = parseDouble(match[1]) else {
            return nil
        }

        return makeQuote(
            commodity: commodity,
            price: price,
            percentChange: percentChange,
            marketDate: marketDate
        )
    }

    private func makeNaturalGasQuote(for commodity: Commodity, region: String, marketDate: Date?) -> CommodityQuote? {
        let escapedRegion = NSRegularExpression.escapedPattern(for: region)
        let pattern = #"<td class="s1">\s*\#(escapedRegion)\s*</td>\s*<td class="d1">\s*([^<]+?)\s*</td>\s*<td class="[^"]+">\s*([^<]+?)\s*</td>"#
        guard let match = firstMatch(for: pattern),
              let price = parseDouble(match[0]),
              let percentChange = parseDouble(match[1]) else {
            return nil
        }

        return makeQuote(
            commodity: commodity,
            price: price,
            percentChange: percentChange,
            marketDate: marketDate
        )
    }

    private func makeQuote(commodity: Commodity, price: Double, percentChange: Double, marketDate: Date?) -> CommodityQuote {
        let ratio = 1 + (percentChange / 100)
        let previousPrice = abs(ratio) < 0.000_001 ? price : price / ratio
        let change = price - previousPrice

        return CommodityQuote(
            commodity: commodity,
            price: price,
            change: change,
            changePercent: percentChange,
            marketTime: marketDate
        )
    }

    private func parseQuoteDate() -> Date? {
        guard let match = firstMatch(for: #"Wholesale Spot Petroleum Prices,\s*([0-9]{1,2}/[0-9]{1,2}/[0-9]{2})\s*Close"#),
              let dateText = match.first else {
            return nil
        }
        return Self.shortDateFormatter.date(from: dateText)
    }

    private func parsePageDate() -> Date? {
        guard let match = firstMatch(for: #"<span class="date">\s*([A-Za-z]+\s+\d{1,2},\s+\d{4})\s*</span>\s*<h1>\s*Daily Prices\s*</h1>"#),
              let dateText = match.first else {
            return nil
        }
        return Self.longDateFormatter.date(from: dateText)
    }

    private func firstMatch(for pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(location: 0, length: (html as NSString).length)
        guard let match = regex.firstMatch(in: html, range: range) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: html) else {
                return nil
            }
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func parseDouble(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")

        guard cleaned.uppercased() != "NA" else { return nil }
        return Double(cleaned)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M/d/yy"
        return formatter
    }()

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
}
