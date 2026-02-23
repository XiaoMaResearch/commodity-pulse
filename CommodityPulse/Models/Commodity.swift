import Foundation

enum Commodity: String, CaseIterable, Identifiable, Codable {
    case oil = "CL=F"
    case gas = "NG=F"
    case gold = "GC=F"
    case silver = "SI=F"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .oil: return "Crude Oil"
        case .gas: return "Natural Gas"
        case .gold: return "Gold"
        case .silver: return "Silver"
        }
    }

    var unit: String {
        switch self {
        case .oil: return "USD / barrel"
        case .gas: return "USD / MMBtu"
        case .gold: return "USD / troy oz"
        case .silver: return "USD / troy oz"
        }
    }
}

enum QuoteFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case favorites = "Favorites"

    var id: String { rawValue }
}

struct CommodityQuote: Identifiable, Equatable, Codable {
    let commodity: Commodity
    let price: Double
    let change: Double
    let changePercent: Double
    let marketTime: Date?

    var id: String { commodity.id }
}

enum CommodityChartRange: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case fiveDays = "5D"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"

    var id: String { rawValue }

    var queryRange: String {
        switch self {
        case .oneDay: return "1d"
        case .fiveDays: return "5d"
        case .oneMonth: return "1mo"
        case .threeMonths: return "3mo"
        case .oneYear: return "1y"
        }
    }

    var queryInterval: String {
        switch self {
        case .oneDay: return "5m"
        case .fiveDays: return "30m"
        case .oneMonth: return "1d"
        case .threeMonths: return "1d"
        case .oneYear: return "1wk"
        }
    }
}

struct CommodityPricePoint: Identifiable, Equatable {
    let date: Date
    let price: Double

    var id: TimeInterval { date.timeIntervalSince1970 }
}
