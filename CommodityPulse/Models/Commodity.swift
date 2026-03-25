import Foundation

enum Commodity: String, CaseIterable, Identifiable, Codable {
    case wti = "wti"
    case brent = "brent"
    case naturalGas = "natural_gas"
    case gold = "gold"
    case silver = "silver"
    case copper = "copper"
    case aluminum = "aluminum"
    case wheat = "wheat"
    case corn = "corn"
    case cotton = "cotton"
    case sugar = "sugar"
    case coffee = "coffee"

    static var supportedCases: [Commodity] {
        allCases
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .wti: return "WTI Crude Oil"
        case .brent: return "Brent Crude Oil"
        case .naturalGas: return "Natural Gas"
        case .gold: return "Gold"
        case .silver: return "Silver"
        case .copper: return "Copper"
        case .aluminum: return "Aluminum"
        case .wheat: return "Wheat"
        case .corn: return "Corn"
        case .cotton: return "Cotton"
        case .sugar: return "Sugar"
        case .coffee: return "Coffee"
        }
    }

    var unit: String {
        switch self {
        case .wti, .brent: return "USD / barrel"
        case .naturalGas: return "USD / MMBtu"
        case .gold, .silver: return "USD / troy oz"
        case .copper, .aluminum, .wheat, .corn, .cotton, .sugar, .coffee: return "USD / provider unit"
        }
    }

    var tab: CommodityTab {
        switch self {
        case .wti, .brent, .naturalGas:
            return .oilAndGas
        case .gold, .silver, .copper, .aluminum, .wheat, .corn, .cotton, .sugar, .coffee:
            return .commodities
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
        case .copper:
            return "COPPER"
        case .aluminum:
            return "ALUMINUM"
        case .wheat:
            return "WHEAT"
        case .corn:
            return "CORN"
        case .cotton:
            return "COTTON"
        case .sugar:
            return "SUGAR"
        case .coffee:
            return "COFFEE"
        }
    }

    var alphaVantageSymbol: String? {
        switch self {
        case .gold:
            return "GOLD"
        case .silver:
            return "SILVER"
        case .wti, .brent, .naturalGas, .copper, .aluminum, .wheat, .corn, .cotton, .sugar, .coffee:
            return nil
        }
    }

    var alphaVantageInterval: String {
        switch self {
        case .wti, .brent, .naturalGas, .gold, .silver:
            return "daily"
        case .copper, .aluminum, .wheat, .corn, .cotton, .sugar, .coffee:
            return "monthly"
        }
    }

    var unavailableReason: String? {
        nil
    }

    var displayOrder: Int {
        switch self {
        case .wti: return 0
        case .brent: return 1
        case .naturalGas: return 2
        case .gold: return 10
        case .silver: return 11
        case .copper: return 12
        case .aluminum: return 13
        case .wheat: return 20
        case .corn: return 21
        case .cotton: return 22
        case .sugar: return 23
        case .coffee: return 24
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
