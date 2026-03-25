import Foundation

protocol CommodityServicing {
    func fetchQuotes() async throws -> [CommodityQuote]
    func fetchHistory(for commodity: Commodity, range: CommodityChartRange) async throws -> [CommodityPricePoint]
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
            return "Add your FMP API key in the Xcode scheme environment or ReleaseConfiguration before refreshing."
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .requestTimedOut:
            return "Request timed out. Please try again."
        case .serverError:
            return "The price service is temporarily unavailable."
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
            return "FMP free-tier limit reached. Wait and try again later."
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
    private let apiKey: String
    private let cache: CommoditySeriesCache
    private let cacheMaxAge: TimeInterval

    init(
        session: URLSession = .shared,
        apiKey: String = ReleaseConfiguration.fmpAPIKey,
        cacheMaxAge: TimeInterval = 55
    ) {
        self.session = session
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cache = CommoditySeriesCache()
        self.cacheMaxAge = cacheMaxAge
    }

    func fetchQuotes() async throws -> [CommodityQuote] {
        guard !apiKey.isEmpty else {
            throw CommodityServiceError.apiKeyMissing
        }

        let url = try makeBatchQuotesURL()
        let data = try await performRequest(url: url)
        let items = try decodeArrayPayload(from: data)

        let ordered: [CommodityQuote] = Commodity.supportedCases.compactMap { commodity -> CommodityQuote? in
            guard let item = items.first(where: { quoteSymbol(from: $0) == commodity.fmpSymbol }) else {
                return nil
            }
            return makeQuote(from: item, commodity: commodity)
        }

        if ordered.isEmpty {
            throw CommodityServiceError.emptyPayload
        }
        return ordered
    }

    func fetchHistory(for commodity: Commodity, range: CommodityChartRange) async throws -> [CommodityPricePoint] {
        guard !apiKey.isEmpty else {
            throw CommodityServiceError.apiKeyMissing
        }

        let points = try await loadSeries(for: commodity)
        let filtered = Array(points.suffix(range.requestedPointCount))

        if filtered.isEmpty {
            throw CommodityServiceError.emptyHistory
        }
        return filtered
    }

    private func loadSeries(for commodity: Commodity) async throws -> [CommodityPricePoint] {
        if let cached = await cache.freshSeries(for: commodity, maxAge: cacheMaxAge), !cached.isEmpty {
            return cached
        }

        let url = try makeHistoryURL(for: commodity)

        do {
            let data = try await performRequest(url: url)
            let points = try decodeSeries(from: data)

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

    private func makeBatchQuotesURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "financialmodelingprep.com"
        components.path = "/stable/batch-commodity-quotes"
        components.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]

        guard let url = components.url else {
            throw CommodityServiceError.invalidResponse
        }
        return url
    }

    private func makeHistoryURL(for commodity: Commodity) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "financialmodelingprep.com"
        components.path = "/stable/historical-price-eod/light"
        components.queryItems = [
            URLQueryItem(name: "symbol", value: commodity.fmpSymbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        guard let url = components.url else {
            throw CommodityServiceError.invalidResponse
        }
        return url
    }

    private func decodeJSONArray(from data: Data) throws -> [Any] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CommodityServiceError.decodingFailed
        }

        if let root = jsonObject as? [String: Any],
           let providerError = providerError(from: root) {
            throw providerError
        }

        guard let array = jsonObject as? [Any] else {
            throw CommodityServiceError.invalidResponse
        }
        return array
    }

    private func mapProviderMessage(_ message: String) -> CommodityServiceError {
        let normalized = message
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()

        if lowered.contains("api key") || lowered.contains("apikey") {
            return .apiKeyMissing
        }

        if lowered.contains("call frequency")
            || lowered.contains("rate limit")
            || lowered.contains("requests per day")
            || lowered.contains("too many requests")
            || lowered.contains("limit reached")
            || lowered.contains("request limit")
            || lowered.contains("usage limit") {
            return .rateLimited
        }

        return .providerMessage(normalized)
    }

    private func decodeArrayPayload(from data: Data) throws -> [[String: Any]] {
        let items = try decodeJSONArray(from: data)
            .compactMap { $0 as? [String: Any] }

        if items.isEmpty {
            throw CommodityServiceError.emptyPayload
        }

        return items
    }

    private func decodeSeries(from data: Data) throws -> [CommodityPricePoint] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CommodityServiceError.decodingFailed
        }

        let rawItems: [[String: Any]]

        if let items = jsonObject as? [[String: Any]] {
            rawItems = items
        } else if let root = jsonObject as? [String: Any] {
            if let providerError = providerError(from: root) {
                throw providerError
            }

            if let historical = root["historical"] as? [[String: Any]] {
                rawItems = historical
            } else if let dataItems = root["data"] as? [[String: Any]] {
                rawItems = dataItems
            } else {
#if DEBUG
                print("CommodityService unexpected FMP payload keys=\(Array(root.keys).sorted())")
#endif
                throw CommodityServiceError.decodingFailed
            }
        } else {
            throw CommodityServiceError.invalidResponse
        }

        let points = rawItems.compactMap { item -> CommodityPricePoint? in
            guard let dateString = item["date"] as? String,
                  let rawValue = item["price"] ?? item["close"] ?? item["value"],
                  let price = parseNumericValue(rawValue),
                  let date = parseDate(dateString) else {
                return nil
            }

            return CommodityPricePoint(date: date, price: price)
        }
        .sorted { $0.date < $1.date }

        return points
    }

    private func providerError(from root: [String: Any]) -> CommodityServiceError? {
        let keys = ["Error Message", "error", "Error", "message", "Message", "Information", "Note"]
        for key in keys {
            if let message = root[key] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return mapProviderMessage(message)
            }
        }
        return nil
    }

    private func quoteSymbol(from item: [String: Any]) -> String? {
        if let symbol = item["symbol"] as? String {
            return symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func makeQuote(from item: [String: Any], commodity: Commodity) -> CommodityQuote? {
        guard let rawPrice = item["price"],
              let price = parseNumericValue(rawPrice) else {
            return nil
        }

        let change: Double = {
            guard let rawChange = item["change"] else { return 0 }
            return parseNumericValue(rawChange) ?? 0
        }()

        let changePercent: Double = {
            if let rawChangesPercentage = item["changesPercentage"],
               let parsed = parseNumericValue(rawChangesPercentage) {
                return parsed
            }
            let previousClose = price - change
            guard previousClose != 0 else { return 0 }
            return (change / previousClose) * 100
        }()

        let marketTime = parseTimestamp(item["timestamp"])
            ?? parseDate(item["date"] as? String ?? "")

        return CommodityQuote(
            commodity: commodity,
            price: price,
            change: change,
            changePercent: changePercent,
            marketTime: marketTime
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

    private func performRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("CommodityPulse/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "$", with: "")
            return Double(sanitized)
        }

        if let numberValue = rawValue as? NSNumber {
            return numberValue.doubleValue
        }

        return nil
    }

    private func parseTimestamp(_ rawValue: Any?) -> Date? {
        guard let rawValue else { return nil }

        if let timeInterval = parseNumericValue(rawValue) {
            return Date(timeIntervalSince1970: timeInterval)
        }

        return nil
    }

    private func parseDate(_ string: String) -> Date? {
        if let date = Self.dateFormatter.date(from: string) {
            return date
        }
        if let date = Self.dateTimeFormatter.date(from: string) {
            return date
        }
        return ISO8601DateFormatter().date(from: string)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
