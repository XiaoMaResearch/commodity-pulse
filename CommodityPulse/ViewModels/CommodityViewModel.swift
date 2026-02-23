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

    private struct CachePayload: Codable {
        let quotes: [CommodityQuote]
        let lastUpdated: Date?
    }

    private let service = CommodityService()
    private let defaults = UserDefaults.standard
    private let cacheKey = "commodityPulse.cachedQuotes.v1"
    private let favoritesKey = "commodityPulse.favoriteSymbols.v1"
    private let filterKey = "commodityPulse.filter.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var favoriteSymbols: Set<String> = []
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
