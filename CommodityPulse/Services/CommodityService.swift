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
            return "Add your FRED API key in the Xcode scheme environment or ReleaseConfiguration before refreshing."
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
    private let apiKey: String
    private let cache: CommoditySeriesCache
    private let cacheMaxAge: TimeInterval

    init(
        session: URLSession = .shared,
        apiKey: String = ReleaseConfiguration.fredAPIKey,
        cacheMaxAge: TimeInterval = 55
    ) {
        self.session = session
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cache = CommoditySeriesCache()
        self.cacheMaxAge = cacheMaxAge
    }

    func fetchQuotes(forceRefresh: Bool = false) async throws -> [CommodityQuote] {
        guard !apiKey.isEmpty else {
            throw CommodityServiceError.apiKeyMissing
        }

        var quotes: [CommodityQuote] = []
        var lastError: Error = CommodityServiceError.emptyPayload

        for commodity in Commodity.supportedCases {
            do {
                let points = try await loadSeries(for: commodity, forceRefresh: forceRefresh)
                if let quote = makeQuote(from: points, commodity: commodity) {
                    quotes.append(quote)
                }
            } catch {
                lastError = error
            }
        }

        let ordered = Commodity.supportedCases.compactMap { commodity in
            quotes.first(where: { $0.commodity == commodity })
        }

        if ordered.isEmpty {
            throw lastError
        }

        return ordered
    }

    func fetchHistory(for commodity: Commodity, range: CommodityChartRange, forceRefresh: Bool = false) async throws -> [CommodityPricePoint] {
        guard !apiKey.isEmpty else {
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
            let data = try await performRequest(url: url, forceRefresh: forceRefresh)
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
            URLQueryItem(name: "api_key", value: apiKey),
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

    private func providerError(from root: [String: Any]) -> CommodityServiceError? {
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

    private func performRequest(url: URL, forceRefresh: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("CommodityPulse/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        if forceRefresh {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }

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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
