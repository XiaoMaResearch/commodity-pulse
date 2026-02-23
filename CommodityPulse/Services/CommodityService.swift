import Foundation

enum CommodityServiceError: LocalizedError {
    case networkUnavailable
    case requestTimedOut
    case serverError
    case invalidResponse
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
        case .invalidResponse:
            return "Unable to parse quote data right now."
        case .emptyPayload:
            return "No quote data was returned."
        case .emptyHistory:
            return "No historical price data is available for this period."
        }
    }
}

struct CommodityService {
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
        guard let url = URL(string: "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(symbols)") else {
            throw CommodityServiceError.invalidResponse
        }
        let data = try await loadData(from: url)

        let decoded: YahooResponse
        do {
            decoded = try JSONDecoder().decode(YahooResponse.self, from: data)
        } catch {
            throw CommodityServiceError.invalidResponse
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
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(commodity.rawValue)")
        components?.queryItems = [
            URLQueryItem(name: "range", value: range.queryRange),
            URLQueryItem(name: "interval", value: range.queryInterval),
            URLQueryItem(name: "includePrePost", value: "false"),
            URLQueryItem(name: "events", value: "div,splits")
        ]

        guard let url = components?.url else {
            throw CommodityServiceError.invalidResponse
        }

        let data = try await loadData(from: url)
        let decoded: YahooChartResponse
        do {
            decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        } catch {
            throw CommodityServiceError.invalidResponse
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

    private func loadData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("CommodityPulse/1.0", forHTTPHeaderField: "User-Agent")

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

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CommodityServiceError.serverError
        }
        return data
    }
}
