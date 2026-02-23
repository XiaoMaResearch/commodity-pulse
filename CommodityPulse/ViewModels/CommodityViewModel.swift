import Foundation

@MainActor
final class CommodityViewModel: ObservableObject {
    @Published private(set) var quotes: [CommodityQuote] = []
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published private(set) var isLoading = false
    @Published var selectedFilter: QuoteFilter = .all {
        didSet { defaults.set(selectedFilter.rawValue, forKey: filterKey) }
    }

    @Published var selectedCommodity: Commodity?
    @Published var selectedChartRange: CommodityChartRange = .oneMonth
    @Published private(set) var historyPoints: [CommodityPricePoint] = []
    @Published private(set) var isHistoryLoading = false
    @Published var historyErrorMessage: String?

    private struct CachePayload: Codable {
        let quotes: [CommodityQuote]
        let lastUpdated: Date?
    }

    private struct HistoryCacheKey: Hashable {
        let commodity: Commodity
        let range: CommodityChartRange
    }

    private let service = CommodityService()
    private let defaults = UserDefaults.standard
    private let cacheKey = "commodityPulse.cachedQuotes.v1"
    private let favoritesKey = "commodityPulse.favoriteSymbols.v1"
    private let filterKey = "commodityPulse.filter.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var favoriteSymbols: Set<String> = []
    private var historyCache: [HistoryCacheKey: [CommodityPricePoint]] = [:]
    private var autoRefreshTask: Task<Void, Never>?

    init() {
        loadFavorites()
        loadFilter()
        loadCache()
    }

    var displayedQuotes: [CommodityQuote] {
        let base: [CommodityQuote]
        switch selectedFilter {
        case .all:
            base = quotes
        case .favorites:
            base = quotes.filter { isFavorite($0.commodity) }
        }

        return base.sorted { lhs, rhs in
            let lhsFavorite = isFavorite(lhs.commodity)
            let rhsFavorite = isFavorite(rhs.commodity)
            if lhsFavorite != rhsFavorite { return lhsFavorite && !rhsFavorite }
            return lhs.commodity.name < rhs.commodity.name
        }
    }

    var hasFavorites: Bool {
        !favoriteSymbols.isEmpty
    }

    func quote(for commodity: Commodity) -> CommodityQuote? {
        quotes.first { $0.commodity == commodity }
    }

    func isFavorite(_ commodity: Commodity) -> Bool {
        favoriteSymbols.contains(commodity.rawValue)
    }

    func toggleFavorite(_ commodity: Commodity) {
        if isFavorite(commodity) {
            favoriteSymbols.remove(commodity.rawValue)
        } else {
            favoriteSymbols.insert(commodity.rawValue)
        }
        persistFavorites()
        objectWillChange.send()
    }

    func refresh() async {
        if isLoading { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let newQuotes = try await service.fetchQuotes()
            quotes = newQuotes
            lastUpdated = Date()
            errorMessage = nil
            infoMessage = nil
            persistCache()
        } catch {
            errorMessage = error.localizedDescription
            if !quotes.isEmpty {
                infoMessage = "Showing the latest available snapshot."
            }
        }
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func openDetails(for commodity: Commodity) {
        selectedCommodity = commodity
        selectedChartRange = .oneMonth
        historyErrorMessage = nil
        historyPoints = []
        Task { await loadHistory(for: commodity, range: .oneMonth) }
    }

    func closeDetails() {
        selectedCommodity = nil
        historyPoints = []
        historyErrorMessage = nil
        isHistoryLoading = false
    }

    func refreshSelectedHistory(force: Bool = false) async {
        guard let commodity = selectedCommodity else { return }
        await loadHistory(for: commodity, range: selectedChartRange, force: force)
    }

    func setChartRange(_ range: CommodityChartRange) async {
        selectedChartRange = range
        await refreshSelectedHistory()
    }

    func clearCachedQuotes() {
        defaults.removeObject(forKey: cacheKey)
        quotes = []
        lastUpdated = nil
        errorMessage = nil
        infoMessage = "Cache cleared. Pull to refresh for live quotes."
    }

    func resetPreferences() {
        favoriteSymbols.removeAll()
        selectedFilter = .all
        defaults.removeObject(forKey: favoritesKey)
        defaults.removeObject(forKey: filterKey)
        objectWillChange.send()
    }

    private func loadHistory(for commodity: Commodity, range: CommodityChartRange, force: Bool = false) async {
        let key = HistoryCacheKey(commodity: commodity, range: range)

        if !force, let cached = historyCache[key], !cached.isEmpty {
            historyPoints = cached
            historyErrorMessage = nil
            return
        }

        isHistoryLoading = true
        defer { isHistoryLoading = false }

        do {
            let points = try await service.fetchHistory(for: commodity, range: range)
            historyCache[key] = points

            if selectedCommodity == commodity && selectedChartRange == range {
                historyPoints = points
                historyErrorMessage = nil
            }
        } catch {
            if let cached = historyCache[key], !cached.isEmpty {
                historyPoints = cached
            }
            if selectedCommodity == commodity && selectedChartRange == range {
                historyErrorMessage = error.localizedDescription
            }
        }
    }

    private func persistCache() {
        let payload = CachePayload(quotes: quotes, lastUpdated: lastUpdated)
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func loadCache() {
        guard let data = defaults.data(forKey: cacheKey),
              let payload = try? decoder.decode(CachePayload.self, from: data) else { return }
        quotes = payload.quotes
        lastUpdated = payload.lastUpdated
        infoMessage = "Loaded cached prices while fetching live updates."
    }

    private func persistFavorites() {
        defaults.set(Array(favoriteSymbols), forKey: favoritesKey)
    }

    private func loadFavorites() {
        let stored = defaults.stringArray(forKey: favoritesKey) ?? []
        favoriteSymbols = Set(stored)
    }

    private func loadFilter() {
        guard let raw = defaults.string(forKey: filterKey),
              let filter = QuoteFilter(rawValue: raw) else { return }
        selectedFilter = filter
    }
}
