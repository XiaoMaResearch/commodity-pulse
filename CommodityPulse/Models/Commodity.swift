import Foundation

enum Commodity: String, CaseIterable, Identifiable, Codable {
    case wti = "wti"
    case brent = "brent"
    case naturalGas = "natural_gas"

    static var supportedCases: [Commodity] {
        allCases
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .wti: return "WTI Crude Oil"
        case .brent: return "Brent Crude Oil"
        case .naturalGas: return "Natural Gas"
        }
    }

    var unit: String {
        switch self {
        case .wti: return "USD / barrel"
        case .brent: return "USD / barrel"
        case .naturalGas: return "USD / MMBtu"
        }
    }

    var fredSeriesID: String {
        switch self {
        case .wti: return "DCOILWTICO"
        case .brent: return "DCOILBRENTEU"
        case .naturalGas: return "DHHNGSP"
        }
    }

    var eiaSeriesID: String {
        switch self {
        case .wti: return "PET.RWTC.D"
        case .brent: return "PET.RBRTE.D"
        case .naturalGas: return "NG.RNGWHHD.D"
        }
    }

    var providerCadenceLabel: String {
        switch self {
        case .wti, .brent, .naturalGas:
            return "Daily published data"
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
