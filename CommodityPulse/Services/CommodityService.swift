import Foundation

enum CommodityServiceError: LocalizedError {
    case networkUnavailable
    case requestTimedOut
    case serverError
    case invalidResponse
    case emptyPayload

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

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuotes() async throws -> [CommodityQuote] {
        let symbols = Commodity.allCases.map(\.rawValue).joined(separator: ",")
        guard let url = URL(string: "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(symbols)") else {
            throw CommodityServiceError.invalidResponse
        }

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

        let decoded = try JSONDecoder().decode(YahooResponse.self, from: data)
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
}
