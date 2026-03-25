import XCTest
@testable import CommodityPulse

@MainActor
final class CommodityViewModelTests: XCTestCase {
    func testRefreshLoadsQuotesAndCachesState() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockCommodityService(
            quotes: [
                CommodityQuote(commodity: .wti, price: 80, change: 1.2, changePercent: 1.5, marketTime: Date()),
                CommodityQuote(commodity: .naturalGas, price: 2.5, change: -0.2, changePercent: -0.8, marketTime: Date())
            ]
        )

        let viewModel = CommodityViewModel(service: service, defaults: defaults)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.displayedQuotes.count, 2)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.lastUpdated)
    }

    func testToggleFavoritePersistsAndFilters() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockCommodityService(
            quotes: [
                CommodityQuote(commodity: .wti, price: 80, change: 1.2, changePercent: 1.5, marketTime: Date()),
                CommodityQuote(commodity: .gold, price: 2200, change: 10, changePercent: 0.5, marketTime: Date())
            ]
        )

        let viewModel = CommodityViewModel(service: service, defaults: defaults)
        viewModel.toggleFavorite(.gold)
        let restoredViewModel = CommodityViewModel(service: service, defaults: defaults)
        restoredViewModel.selectedFilter = .favorites

        XCTAssertTrue(restoredViewModel.isFavorite(.gold))
    }

    func testHistoryRangeLoadsPoints() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let history = [
            CommodityPricePoint(date: Date(timeIntervalSince1970: 1), price: 10),
            CommodityPricePoint(date: Date(timeIntervalSince1970: 2), price: 11)
        ]

        let service = MockCommodityService(
            quotes: [
                CommodityQuote(commodity: .silver, price: 25, change: 0.2, changePercent: 1.0, marketTime: Date())
            ],
            history: [.silver: history]
        )

        let viewModel = CommodityViewModel(service: service, defaults: defaults)
        viewModel.selectedCommodity = .silver
        await viewModel.refreshSelectedHistory()

        XCTAssertEqual(viewModel.historyPoints.count, 2)
    }

    func testTabSplitShowsExpandedFreeTierCatalog() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockCommodityService(
            quotes: [
                CommodityQuote(commodity: .wti, price: 80, change: 1.2, changePercent: 1.5, marketTime: Date()),
                CommodityQuote(commodity: .gold, price: 2200, change: 10, changePercent: 0.5, marketTime: Date()),
                CommodityQuote(commodity: .copper, price: 8400, change: 40, changePercent: 0.5, marketTime: Date()),
                CommodityQuote(commodity: .corn, price: 230, change: 1, changePercent: 0.4, marketTime: Date())
            ]
        )

        let viewModel = CommodityViewModel(service: service, defaults: defaults)

        XCTAssertEqual(viewModel.displayedQuotes(in: .oilAndGas).map(\.commodity), [.wti])
        XCTAssertEqual(viewModel.displayedQuotes(in: .commodities).map(\.commodity), [.gold, .copper, .corn])
        XCTAssertTrue(viewModel.unavailableCommodities(in: .commodities).isEmpty)
    }
}

private struct MockCommodityService: CommodityServicing {
    var quotes: [CommodityQuote] = []
    var history: [Commodity: [CommodityPricePoint]] = [:]

    func fetchQuotes() async throws -> [CommodityQuote] {
        quotes
    }

    func fetchHistory(for commodity: Commodity, range: CommodityChartRange) async throws -> [CommodityPricePoint] {
        history[commodity] ?? []
    }
}
