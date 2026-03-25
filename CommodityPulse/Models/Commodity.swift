import Foundation

enum Commodity: String, CaseIterable, Identifiable, Codable {
    case wti = "wti"
    case gold = "gold"

    static var supportedCases: [Commodity] {
        allCases
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .wti: return "WTI Crude Oil"
        case .gold: return "Gold"
        }
    }

    var unit: String {
        switch self {
        case .wti: return "USD / barrel"
        case .gold: return "USD / troy oz"
        }
    }

    var fmpSymbol: String {
        switch self {
        case .wti: return "CLUSD"
        case .gold: return "GCUSD"
        }
    }

    var providerCadenceLabel: String {
        switch self {
        case .wti, .gold:
            return "Real-time quotes, EOD history"
        }
    }

    var unavailableReason: String? {
        nil
    }

    var displayOrder: Int {
        switch self {
        case .wti: return 0
        case .gold: return 1
        }
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
