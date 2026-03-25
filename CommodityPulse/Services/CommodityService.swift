import Foundation

protocol CommodityServicing {
    func fetchQuotes() async throws -> [CommodityQuote]
    func fetchHistory(for commodity: Commodity, range: CommodityChartRange) async throws -> [CommodityPricePoint]
}

enum CommodityServiceError: LocalizedError, Equatable {
    case networkUnavailable
    case requestTimedOut
    case serverError
    case httpStatus(Int)
    case invalidResponse
    case decodingFailed
    case emptyPayload
    case emptyHistory

    var errorDescription: String? {
        switch self {
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
        }
    }
}

struct CommodityService: CommodityServicing {
    private let hosts = [
        "query1.finance.yahoo.com",
        "query2.finance.yahoo.com"
    ]

    private struct YahooResponse: Decodable {
        struct QuoteResponse: Decodable {
            let result: [Quote]
        }

        struct Quote: Decodable {
            let symbol: String
            let regularMarketPrice: Double?
            let regularMarketChange: Double?
            let regularMarketChangePercent: Double?
            let regularMarketTime: Int?
        }

        let quoteResponse: QuoteResponse
    }

    private struct YahooChartResponse: Decodable {
        struct Chart: Decodable {
            struct Result: Decodable {
                struct Indicators: Decodable {
                    struct Quote: Decodable {
                        let close: [Double?]?
                    }

                    let quote: [Quote]
                }

                let timestamp: [Int]?
                let indicators: Indicators
            }

            let result: [Result]?
        }

        let chart: Chart
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuotes() async throws -> [CommodityQuote] {
        let symbols = Commodity.allCases.map(\.rawValue).joined(separator: ",")
        let data = try await loadData(
            path: "/v7/finance/quote",
            queryItems: [URLQueryItem(name: "symbols", value: symbols)]
        )

        let decoded: YahooResponse
        do {
            decoded = try JSONDecoder().decode(YahooResponse.self, from: data)
        } catch {
            throw CommodityServiceError.decodingFailed
        }
        let mapped: [CommodityQuote] = decoded.quoteResponse.result.compactMap { quote in
            guard let commodity = Commodity(rawValue: quote.symbol),
                  let price = quote.regularMarketPrice else {
                return nil
            }

            let time = quote.regularMarketTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return CommodityQuote(
                commodity: commodity,
                price: price,
                change: quote.regularMarketChange ?? 0,
                changePercent: quote.regularMarketChangePercent ?? 0,
                marketTime: time
            )
        }

        let ordered = Commodity.allCases.compactMap { commodity in
            mapped.first(where: { $0.commodity == commodity })
        }

        if ordered.isEmpty {
            throw CommodityServiceError.emptyPayload
        }
        return ordered
    }

    func fetchHistory(for commodity: Commodity, range: CommodityChartRange) async throws -> [CommodityPricePoint] {
        let data = try await loadData(
            path: "/v8/finance/chart/\(commodity.rawValue)",
            queryItems: [
            URLQueryItem(name: "range", value: range.queryRange),
            URLQueryItem(name: "interval", value: range.queryInterval),
            URLQueryItem(name: "includePrePost", value: "false"),
            URLQueryItem(name: "events", value: "div,splits")
            ]
        )
        let decoded: YahooChartResponse
        do {
            decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        } catch {
            throw CommodityServiceError.decodingFailed
        }

        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators.quote.first?.close else {
            throw CommodityServiceError.invalidResponse
        }

        let points = zip(timestamps, closes).compactMap { timestamp, close -> CommodityPricePoint? in
            guard let close else { return nil }
            return CommodityPricePoint(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                price: close
            )
        }
        .sorted { $0.date < $1.date }

        if points.isEmpty {
            throw CommodityServiceError.emptyHistory
        }
        return points
    }

    private func loadData(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var lastError: Error = CommodityServiceError.serverError

        for host in hosts {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = path
            components.queryItems = queryItems

            guard let url = components.url else {
                lastError = CommodityServiceError.invalidResponse
                continue
            }

            do {
                return try await performRequest(url: url)
            } catch {
                lastError = error
                // Retry on alternate host for upstream/network/provider failures only.
                switch error {
                case CommodityServiceError.networkUnavailable,
                     CommodityServiceError.requestTimedOut,
                     CommodityServiceError.serverError,
                     CommodityServiceError.httpStatus:
                    continue
                default:
                    throw error
                }
            }
        }

        throw lastError
    }

    private func performRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
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
            let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-text body>"
            print("CommodityService non-200 from \(url.host ?? "unknown") status=\(httpResponse.statusCode) preview=\(bodyPreview)")
#endif
            throw CommodityServiceError.httpStatus(httpResponse.statusCode)
        }

#if DEBUG
        if let bodyPreview = String(data: data.prefix(200), encoding: .utf8) {
            print("CommodityService response from \(url.host ?? "unknown") status=\(httpResponse.statusCode) preview=\(bodyPreview)")
        } else {
            print("CommodityService response from \(url.host ?? "unknown") status=\(httpResponse.statusCode) bytes=\(data.count)")
        }
#endif
        return data
    }
}
