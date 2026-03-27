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

    func testForceRefreshPassesThroughToService() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = RecordingCommodityService()
        let viewModel = CommodityViewModel(service: service, defaults: defaults)

        await viewModel.refresh(force: true)

        let recordedForceFlags = await service.recordedQuoteForceFlags()
        XCTAssertEqual(recordedForceFlags, [true])
    }

    func testEnergyNewsLoadsFromCacheWhenOffline() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let articles = [
            EnergyNewsItem(
                title: "WTI exports rise",
                summary: "Sample cached summary for the EIA article.",
                link: URL(string: "https://www.eia.gov/todayinenergy/detail.php?id=1")!,
                publishedAt: Date()
            )
        ]

        let onlineViewModel = EnergyNewsViewModel(
            service: MockEnergyNewsService(result: .success(articles)),
            defaults: defaults
        )
        await onlineViewModel.refresh(force: true)

        let offlineViewModel = EnergyNewsViewModel(
            service: MockEnergyNewsService(result: .failure(EnergyNewsServiceError.feedUnavailable)),
            defaults: defaults
        )

        XCTAssertEqual(offlineViewModel.articles, articles)

        await offlineViewModel.refresh(force: true)

        XCTAssertEqual(offlineViewModel.articles, articles)
        XCTAssertNil(offlineViewModel.errorMessage)
    }

    func testEnergyNewsForceRefreshPassesThroughToService() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let service = RecordingEnergyNewsService()
        let viewModel = EnergyNewsViewModel(service: service, defaults: defaults)

        await viewModel.refresh(force: true)

        let recordedForceFlags = await service.recordedForceFlags()
        XCTAssertEqual(recordedForceFlags, [true])
    }
}

private struct MockCommodityService: CommodityServicing {
    var quotes: [CommodityQuote] = []
    var history: [Commodity: [CommodityPricePoint]] = [:]

    func fetchQuotes(forceRefresh: Bool) async throws -> [CommodityQuote] {
        quotes
    }

    func fetchHistory(for commodity: Commodity, range: CommodityChartRange, forceRefresh: Bool) async throws -> [CommodityPricePoint] {
        history[commodity] ?? []
    }
}

private actor RecordingCommodityService: CommodityServicing {
    private var quoteForceFlags: [Bool] = []

    func fetchQuotes(forceRefresh: Bool) async throws -> [CommodityQuote] {
        quoteForceFlags.append(forceRefresh)
        return [
            CommodityQuote(commodity: .wti, price: 80, change: 1.2, changePercent: 1.5, marketTime: Date()),
            CommodityQuote(commodity: .brent, price: 84, change: 1.0, changePercent: 1.2, marketTime: Date()),
            CommodityQuote(commodity: .naturalGas, price: 3.2, change: 0.1, changePercent: 3.2, marketTime: Date())
        ]
    }

    func fetchHistory(for commodity: Commodity, range: CommodityChartRange, forceRefresh: Bool) async throws -> [CommodityPricePoint] {
        []
    }

    func recordedQuoteForceFlags() -> [Bool] {
        quoteForceFlags
    }
}

private struct MockEnergyNewsService: EnergyNewsServicing {
    let result: Result<[EnergyNewsItem], Error>

    func fetchNews(forceRefresh: Bool) async throws -> [EnergyNewsItem] {
        try result.get()
    }
}

private actor RecordingEnergyNewsService: EnergyNewsServicing {
    private var forceFlags: [Bool] = []

    func fetchNews(forceRefresh: Bool) async throws -> [EnergyNewsItem] {
        forceFlags.append(forceRefresh)
        return [
            EnergyNewsItem(
                title: "Latest EIA headline",
                summary: "Sample summary",
                link: URL(string: "https://www.eia.gov/todayinenergy/detail.php?id=2")!,
                publishedAt: Date(timeIntervalSince1970: 200)
            )
        ]
    }

    func recordedForceFlags() -> [Bool] {
        forceFlags
    }
}
