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
                CommodityQuote(commodity: .brent, price: 84, change: 1.0, changePercent: 1.2, marketTime: Date()),
                CommodityQuote(commodity: .naturalGas, price: 3.2, change: 0.1, changePercent: 3.2, marketTime: Date())
            ]
        )

        let viewModel = CommodityViewModel(service: service, defaults: defaults)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.displayedQuotes.count, 3)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.lastUpdated)
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
                CommodityQuote(commodity: .wti, price: 80, change: 1.2, changePercent: 1.5, marketTime: Date())
            ],
            history: [.wti: history]
        )

        let viewModel = CommodityViewModel(service: service, defaults: defaults)
        viewModel.selectedCommodity = .wti
        await viewModel.refreshSelectedHistory()

        XCTAssertEqual(viewModel.historyPoints.count, 2)
    }

    func testDisplayedQuotesShowsEnergyCatalog() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = MockCommodityService(
            quotes: [
                CommodityQuote(commodity: .naturalGas, price: 3.2, change: 0.1, changePercent: 3.2, marketTime: Date()),
                CommodityQuote(commodity: .wti, price: 80, change: 1.2, changePercent: 1.5, marketTime: Date()),
                CommodityQuote(commodity: .brent, price: 84, change: 1.0, changePercent: 1.2, marketTime: Date())
            ]
        )

        let viewModel = CommodityViewModel(service: service, defaults: defaults)

        XCTAssertEqual(viewModel.displayedQuotes.map(\.commodity), [.wti, .brent, .naturalGas])
    }

    func testAutoRefreshDefaultsOffAndPersists() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let viewModel = CommodityViewModel(service: MockCommodityService(), defaults: defaults)
        XCTAssertFalse(viewModel.isAutoRefreshEnabled)

        viewModel.isAutoRefreshEnabled = true

        let restoredViewModel = CommodityViewModel(service: MockCommodityService(), defaults: defaults)
        XCTAssertTrue(restoredViewModel.isAutoRefreshEnabled)
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
