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
