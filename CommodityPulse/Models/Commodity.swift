import Foundation

enum Commodity: String, CaseIterable, Identifiable, Codable {
    case wti = "wti"
    case brent = "brent"
    case naturalGas = "natural_gas"
    case gold = "gold"
    case silver = "silver"
    case platinum = "platinum"
    case corn = "corn"
    case soybeans = "soybeans"

    static var supportedCases: [Commodity] {
        allCases.filter(\.isSupportedByProvider)
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .wti: return "WTI Crude Oil"
        case .brent: return "Brent Crude Oil"
        case .naturalGas: return "Natural Gas"
        case .gold: return "Gold"
        case .silver: return "Silver"
        case .platinum: return "Platinum"
        case .corn: return "Corn"
        case .soybeans: return "Soybeans"
        }
    }

    var unit: String {
        switch self {
        case .wti, .brent: return "USD / barrel"
        case .naturalGas: return "USD / MMBtu"
        case .gold, .silver, .platinum: return "USD / troy oz"
        case .corn, .soybeans: return "USD / metric ton"
        }
    }

    var tab: CommodityTab {
        switch self {
        case .wti, .brent, .naturalGas:
            return .oilAndGas
        case .gold, .silver, .platinum, .corn, .soybeans:
            return .commodities
        }
    }

    var isSupportedByProvider: Bool {
        switch self {
        case .platinum, .soybeans:
            return false
        case .wti, .brent, .naturalGas, .gold, .silver, .corn:
            return true
        }
    }

    var unavailableReason: String? {
        switch self {
        case .platinum, .soybeans:
            return "Unavailable on the current Alpha Vantage free-tier commodity feed."
        case .wti, .brent, .naturalGas, .gold, .silver, .corn:
            return nil
        }
    }

    var alphaVantageFunction: String? {
        switch self {
        case .wti:
            return "WTI"
        case .brent:
            return "BRENT"
        case .naturalGas:
            return "NATURAL_GAS"
        case .gold, .silver:
            return "GOLD_SILVER_HISTORY"
        case .corn:
            return "CORN"
        case .platinum, .soybeans:
            return nil
        }
    }

    var alphaVantageSymbol: String? {
        switch self {
        case .gold:
            return "GOLD"
        case .silver:
            return "SILVER"
        case .wti, .brent, .naturalGas, .platinum, .corn, .soybeans:
            return nil
        }
    }

    var alphaVantageInterval: String {
        switch self {
        case .wti, .brent, .naturalGas, .gold, .silver:
            return "daily"
        case .corn:
            return "monthly"
        case .platinum, .soybeans:
            return "monthly"
        }
    }
}

enum CommodityTab: String, CaseIterable, Identifiable {
    case oilAndGas = "Oil & Gas"
    case commodities = "Commodities"

    var id: String { rawValue }

    var commodities: [Commodity] {
        Commodity.allCases.filter { $0.tab == self }
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

    var requestedPointCount: Int {
        switch self {
        case .oneDay:
            return 2
        case .fiveDays:
            return 5
        case .oneMonth:
            return 22
        case .threeMonths:
            return 66
        case .oneYear:
            return 260
        }
    }
}

struct CommodityPricePoint: Identifiable, Equatable {
    let date: Date
    let price: Double

    var id: TimeInterval { date.timeIntervalSince1970 }
}
