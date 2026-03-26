import SwiftUI
import Charts
import SafariServices

private enum SourceDateText {
    static let monthDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

struct ContentView: View {
    @StateObject private var viewModel = CommodityViewModel()
    @StateObject private var newsViewModel = EnergyNewsViewModel()
    @State private var selectedTab: AppTab = .market
    @State private var cardVisible = false
    @State private var showingSettings = false
    @State private var selectedArticle: EnergyNewsItem?
    @Environment(\.scenePhase) private var scenePhase

    private var visibleQuotes: [CommodityQuote] {
        viewModel.displayedQuotes
    }

    private var visibleCommodityCount: Int {
        visibleQuotes.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
                .tabItem {
                    Label("Market", systemImage: "drop.fill")
                }
                .tag(AppTab.market)

            newsTab
                .tabItem {
                    Label("News", systemImage: "newspaper.fill")
                }
                .tag(AppTab.news)
        }
        .tint(Color(red: 0.99, green: 0.76, blue: 0.26))
    }

    private var dashboardTab: some View {
        NavigationStack {
            ZStack {
                DashboardTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeaderPanel(
                            lastUpdated: viewModel.lastUpdated,
                            isDataStale: viewModel.isDataStale,
                            isRefreshing: viewModel.isLoading,
                            onSettings: { showingSettings = true }
                        )

                        if let info = viewModel.infoMessage {
                            InfoPanel(message: info)
                        }

                        if let error = viewModel.errorMessage {
                            ErrorPanel(message: error)
                        }

                        SectionHeader(visibleCount: visibleCommodityCount)

                        if viewModel.isLoading && visibleQuotes.isEmpty {
                            LoadingCards(count: Commodity.allCases.count)
                        } else if visibleQuotes.isEmpty {
                            EmptyState()
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(Array(visibleQuotes.enumerated()), id: \.element.id) { index, quote in
                                    CommodityCard(
                                        quote: quote,
                                        onOpenDetails: { viewModel.openDetails(for: quote.commodity) }
                                    )
                                    .opacity(cardVisible ? 1 : 0)
                                    .offset(y: cardVisible ? 0 : 24)
                                        .animation(
                                            .spring(response: 0.55, dampingFraction: 0.82)
                                            .delay(Double(index) * 0.06),
                                            value: cardVisible
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await viewModel.refresh(force: true) }
            .task {
                await viewModel.refresh()
                viewModel.startAutoRefresh()
                cardVisible = true
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    viewModel.startAutoRefresh()
                    Task {
                        await viewModel.refresh(force: true)
                    }
                } else if newPhase == .background {
                    viewModel.stopAutoRefresh()
                }
            }
            .onDisappear { viewModel.stopAutoRefresh() }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(viewModel: viewModel, newsViewModel: newsViewModel)
            }
            .sheet(item: $viewModel.selectedCommodity, onDismiss: { viewModel.closeDetails() }) { commodity in
                CommodityDetailSheet(viewModel: viewModel, commodity: commodity)
            }
        }
    }

    private var newsTab: some View {
        NavigationStack {
            ZStack {
                DashboardTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        NewsHeaderPanel(
                            lastUpdated: newsViewModel.lastUpdated,
                            isShowingCachedArticles: newsViewModel.isShowingCachedArticles,
                            isRefreshing: newsViewModel.isLoading
                        )

                        if let error = newsViewModel.errorMessage {
                            ErrorPanel(message: error)
                        }

                        if newsViewModel.isLoading && newsViewModel.articles.isEmpty {
                            NewsLoadingCards()
                        } else if newsViewModel.articles.isEmpty {
                            NewsEmptyState()
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(newsViewModel.articles) { article in
                                    EnergyNewsCard(
                                        article: article,
                                        onOpen: { selectedArticle = article }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await newsViewModel.refresh(force: true) }
            .task {
                await newsViewModel.refreshIfNeeded()
            }
            .sheet(item: $selectedArticle) { article in
                ArticleSheet(article: article)
            }
        }
    }
}

private enum AppTab: Hashable {
    case market
    case news
}

private struct SectionHeader: View {
    let visibleCount: Int

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Energy Spot Prices")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            Spacer()
            if visibleCount > 3 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                    Text("Scroll")
                }
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(red: 0.99, green: 0.76, blue: 0.26))
                .clipShape(Capsule())
            }
        }
    }

    private var subtitle: String {
        let noun = visibleCount == 1 ? "instrument" : "instruments"
        return "\(visibleCount) \(noun) available in view"
    }
}

private enum DashboardTheme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.05, blue: 0.09),
            Color(red: 0.07, green: 0.10, blue: 0.16),
            Color(red: 0.12, green: 0.09, blue: 0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let card = LinearGradient(
        colors: [
            Color(red: 0.11, green: 0.14, blue: 0.20),
            Color(red: 0.07, green: 0.09, blue: 0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct HeaderPanel: View {
    let lastUpdated: Date?
    let isDataStale: Bool
    let isRefreshing: Bool
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Commodity Pulse")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("EIA daily prices for WTI, Brent, and Henry Hub gas")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                Spacer()

                if isRefreshing {
                    RefreshStatusCapsule()
                }

                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Open Settings")
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text("Updated \(lastUpdated?.formatted(date: .omitted, time: .standard) ?? "--")")
                if isDataStale {
                    Text("Stale")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.99, green: 0.76, blue: 0.26))
                        .clipShape(Capsule())
                }
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct InfoPanel: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
            Text(message)
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(Color(red: 0.68, green: 0.87, blue: 1.0))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.06, green: 0.18, blue: 0.29))
        )
    }
}

private struct ErrorPanel: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.25, green: 0.08, blue: 0.10))
        )
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
            Text("No Quotes Available")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Pull down to refresh.")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct LoadingCards: View {
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<max(count, 1), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 130)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

private struct CommodityCard: View {
    let quote: CommodityQuote
    let onOpenDetails: () -> Void

    private var changeColor: Color {
        quote.change > 0 ? Color(red: 0.3, green: 0.95, blue: 0.6) : (quote.change < 0 ? Color(red: 1.0, green: 0.45, blue: 0.45) : Color.white.opacity(0.75))
    }

    private var priceText: String {
        quote.price.formatted(.number.precision(.fractionLength(2)))
    }

    private var changePercentText: String {
        let sign = quote.changePercent > 0 ? "+" : ""
        let percent = quote.changePercent.formatted(.number.precision(.fractionLength(2)))
        return "\(sign)\(percent)%"
    }

    private var snapshotText: String {
        guard let marketTime = quote.marketTime else { return "--" }
        return SourceDateText.monthDayYear.string(from: marketTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quote.commodity.name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(quote.commodity.unit)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
                CommodityBadgeMark(commodity: quote.commodity)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("$\(priceText)")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily Change")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.56))
                    StatusCapsule(
                        title: changePercentText,
                        tint: changeColor,
                        foreground: quote.change >= 0 ? .black : .white
                    )
                }

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest published")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Text(snapshotText)
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button(action: onOpenDetails) {
                    Text("Details")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }
                .accessibilityLabel("View detailed chart")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DashboardTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 10)
    }
}

private struct CommodityDetailSheet: View {
    @ObservedObject var viewModel: CommodityViewModel
    let commodity: Commodity
    @Environment(\.dismiss) private var dismiss

    private var quote: CommodityQuote? {
        viewModel.quote(for: commodity)
    }

    private var lineColor: Color {
        guard let change = quote?.change else { return Color(red: 0.3, green: 0.75, blue: 1.0) }
        return change >= 0 ? Color(red: 0.3, green: 0.95, blue: 0.6) : Color(red: 1.0, green: 0.45, blue: 0.45)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        detailHeader
                        RangeSelector(
                            selectedRange: viewModel.selectedChartRange,
                            onSelect: { range in
                                Task { await viewModel.setChartRange(range) }
                            }
                        )

                        if viewModel.isHistoryLoading && viewModel.historyPoints.isEmpty {
                            ProgressView("Loading history...")
                                .progressViewStyle(.circular)
                                .foregroundStyle(.white)
                                .padding(20)
                        }

                        if let error = viewModel.historyErrorMessage {
                            ErrorPanel(message: error)
                        }

                        if !viewModel.historyPoints.isEmpty {
                            CommodityHistoryChart(
                                points: viewModel.historyPoints,
                                lineColor: lineColor,
                                selectedRange: viewModel.selectedChartRange
                            )
                            .frame(height: 250)

                            HistoryStatsPanel(points: viewModel.historyPoints, lineColor: lineColor)
                        }

                        Text("Historical data is provided for informational use only and may be delayed.")
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Text("Current provider cadence: \(commodity.providerCadenceLabel)")
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.refreshSelectedHistory(force: true)
                }
            }
            .navigationTitle(commodity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if viewModel.selectedCommodity != commodity {
                    viewModel.openDetails(for: commodity)
                }
                if viewModel.historyPoints.isEmpty {
                    await viewModel.refreshSelectedHistory()
                }
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commodity.name)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(commodity.unit)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer()
                if let quote {
                    Text("$\(quote.price.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }

            if let quote {
                let sign = quote.change >= 0 ? "+" : ""
                let changeText = "\(sign)\(quote.change.formatted(.number.precision(.fractionLength(2)))) (\(sign)\(quote.changePercent.formatted(.number.precision(.fractionLength(2))))%)"
                Text(changeText)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(lineColor)

                HStack(spacing: 8) {
                    DetailMetaPill(
                        title: "Latest Published",
                        value: quote.marketTime.map { SourceDateText.monthDayYear.string(from: $0) } ?? "--"
                    )
                    DetailMetaPill(title: "Cadence", value: "Daily Spot")
                }
            } else {
                DetailMetaPill(title: "Cadence", value: "Daily Spot")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct RangeSelector: View {
    let selectedRange: CommodityChartRange
    let onSelect: (CommodityChartRange) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CommodityChartRange.allCases) { range in
                    Button(action: { onSelect(range) }) {
                        Text(range.rawValue)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(selectedRange == range ? .black : Color.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedRange == range
                                    ? Color(red: 0.99, green: 0.76, blue: 0.26)
                                    : Color.white.opacity(0.08)
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct CommodityHistoryChart: View {
    let points: [CommodityPricePoint]
    let lineColor: Color
    let selectedRange: CommodityChartRange

    @State private var selectedPoint: CommodityPricePoint?

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.date),
                y: .value("Price", point.price)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [lineColor.opacity(0.32), lineColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", point.date),
                y: .value("Price", point.price)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(lineColor)
            .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

            if let selectedPoint {
                RuleMark(x: .value("Selected Time", selectedPoint.date))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                PointMark(
                    x: .value("Selected Time", selectedPoint.date),
                    y: .value("Selected Price", selectedPoint.price)
                )
                .symbolSize(70)
                .foregroundStyle(lineColor)
            }
        }
        .chartXScale(domain: chartDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let frame = geometry[proxy.plotAreaFrame]
                                guard frame.contains(value.location) else { return }
                                let xPosition = value.location.x - frame.origin.x
                                guard let date: Date = proxy.value(atX: xPosition) else { return }
                                selectedPoint = nearestPoint(to: date)
                            }
                            .onEnded { _ in }
                    )
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                    .foregroundStyle(Color.white.opacity(0.18))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(formatted(date, style: xAxisLabelStyle))
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text("$\(price.formatted(.number.precision(.fractionLength(0...2))))")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                }
            }
        }
        .chartPlotStyle { plotContent in
            plotContent
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if let selectedPoint {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatted(selectedPoint.date, style: .monthDayYear))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("$\(selectedPoint.price.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(12)
            }
        }
    }

    private var xAxisLabelStyle: SourceAxisDateStyle {
        switch selectedRange {
        case .oneDay:
            return .monthDay
        case .fiveDays:
            return .monthDay
        case .oneMonth, .threeMonths:
            return .monthDay
        case .oneYear:
            return .month
        }
    }

    private var chartDomain: ClosedRange<Date> {
        let lower = points.first?.date ?? Date()
        let upper = points.last?.date ?? Date()
        return lower...upper
    }

    private var xAxisDates: [Date] {
        guard !points.isEmpty else { return [] }

        switch selectedRange {
        case .oneDay:
            return deduplicatedDates([points.first?.date, points.last?.date])
        case .fiveDays:
            return points.map(\.date)
        case .oneMonth:
            return evenlySpacedDates(targetCount: 4)
        case .threeMonths:
            return evenlySpacedDates(targetCount: 5)
        case .oneYear:
            return evenlySpacedDates(targetCount: 6)
        }
    }

    private var yAxisValues: [Double] {
        let prices = points.map(\.price)
        guard let low = prices.min(), let high = prices.max() else { return [] }
        if abs(high - low) < 0.0001 { return [low] }
        let midpoint = (low + high) / 2
        return [low, midpoint, high]
    }

    private func evenlySpacedDates(targetCount: Int) -> [Date] {
        guard !points.isEmpty else { return [] }
        guard points.count > targetCount else { return points.map(\.date) }

        let maxIndex = points.count - 1
        let step = Double(maxIndex) / Double(max(targetCount - 1, 1))

        let dates = (0..<targetCount).map { position in
            let index = Int(round(Double(position) * step))
            return points[min(index, maxIndex)].date
        }

        return deduplicatedDates(dates)
    }

    private func deduplicatedDates(_ dates: [Date?]) -> [Date] {
        var seen = Set<TimeInterval>()
        return dates.compactMap { $0 }.filter { date in
            let key = date.timeIntervalSince1970
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func nearestPoint(to date: Date) -> CommodityPricePoint? {
        points.min(by: { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        })
    }

    private func formatted(_ date: Date, style: SourceAxisDateStyle) -> String {
        switch style {
        case .monthDay:
            return SourceDateText.monthDay.string(from: date)
        case .month:
            return SourceDateText.month.string(from: date)
        case .monthDayYear:
            return SourceDateText.monthDayYear.string(from: date)
        }
    }
}

private enum SourceAxisDateStyle {
    case monthDay
    case month
    case monthDayYear
}

private struct DetailMetaPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.56))
            Text(value)
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HistoryStatsPanel: View {
    let points: [CommodityPricePoint]
    let lineColor: Color

    private var low: Double? {
        points.map(\.price).min()
    }

    private var high: Double? {
        points.map(\.price).max()
    }

    private var absoluteChange: Double? {
        guard let first = points.first?.price, let last = points.last?.price else { return nil }
        return last - first
    }

    private var percentChange: Double? {
        guard let first = points.first?.price, let abs = absoluteChange, first != 0 else { return nil }
        return (abs / first) * 100
    }

    private var changeText: String {
        guard let absoluteChange, let percentChange else { return "--" }
        let sign = absoluteChange >= 0 ? "+" : ""
        return "\(sign)\(absoluteChange.formatted(.number.precision(.fractionLength(2)))) (\(sign)\(percentChange.formatted(.number.precision(.fractionLength(2))))%)"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatPill(title: "Low", value: priceText(low), tint: Color.white.opacity(0.8))
                StatPill(title: "High", value: priceText(high), tint: Color.white.opacity(0.8))
            }
            StatPill(title: "Period Change", value: changeText, tint: lineColor)
        }
    }

    private func priceText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "$\(value.formatted(.number.precision(.fractionLength(2))))"
    }
}

private struct StatPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct NewsHeaderPanel: View {
    let lastUpdated: Date?
    let isShowingCachedArticles: Bool
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Energy News")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Official \(ReleaseConfiguration.newsProviderName) headlines")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                Spacer()
                HStack(spacing: 8) {
                    if isRefreshing {
                        RefreshStatusCapsule()
                    }
                    if isShowingCachedArticles {
                        StatusCapsule(
                            title: "Cached",
                            tint: Color(red: 0.99, green: 0.76, blue: 0.26),
                            foreground: .black
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text("Updated \(lastUpdated?.formatted(date: .omitted, time: .standard) ?? "--")")
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))

            Text(isShowingCachedArticles ? "Showing the most recent saved headlines because the live EIA page was unavailable." : "Pull down to refresh the latest official EIA headlines.")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct EnergyNewsCard: View {
    let article: EnergyNewsItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text("EIA")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.99, green: 0.76, blue: 0.26))
                        .clipShape(Capsule())

                    Spacer()

                    if let publishedAt = article.publishedAt {
                        Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }

                Text(article.title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                }

                HStack(spacing: 8) {
                    Text("Read In App")
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                    Image(systemName: "safari")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.99, green: 0.76, blue: 0.26))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(DashboardTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct NewsLoadingCards: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 150)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
    }
}

private struct NewsEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
            Text("No energy news yet")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Pull to refresh to load the latest EIA energy headlines.")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SettingsSheet: View {
    @ObservedObject var viewModel: CommodityViewModel
    @ObservedObject var newsViewModel: EnergyNewsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("App") {
                    Text(ReleaseConfiguration.appStoreName)
                    Text("Version \(appVersion)")
                    Text("Built for informational daily energy tracking and headlines.")
                }

                Section("Data") {
                    Text("Current price source: EIA API daily series")
                    Text("Historical chart source: FRED")
                    Text("Energy news source: \(ReleaseConfiguration.newsProviderName)")
                    Text("WTI, Brent, and natural gas use official EIA daily series when an EIA API key is configured.")
                    Text("Prices and news are for informational use only and should not be treated as trading advice.")
                }

                Section("Content") {
                    Text("Market cards open into historical charts with the latest published observation date.")
                    Text("News articles open inside the app using the official EIA article page.")
                    Text("The app caches the latest quotes and headlines so it can recover more gracefully from temporary source outages.")
                }

                Section("Support") {
                    if let supportURL = ReleaseConfiguration.supportURL {
                        Link("Support Page", destination: supportURL)
                    }
                    if let privacyPolicyURL = ReleaseConfiguration.privacyPolicyURL {
                        Link("Privacy Policy", destination: privacyPolicyURL)
                    }
                    Text("Support Email: \(ReleaseConfiguration.supportEmail)")
                }

                Section("Preferences") {
                    Toggle("Auto Refresh Every 60 Seconds", isOn: $viewModel.isAutoRefreshEnabled)
                    Text("Auto refresh is off by default for the daily spot feeds.")
                    Text("When enabled, refresh runs every 60 seconds while the app is active.")
                    Text("These source series are daily, so most minute-by-minute refreshes will not change the prices.")
                    Text("Pull down to refresh is available on the dashboard, chart view, and news page.")
                }

                Section("Maintenance") {
                    Button("Clear Cached Quotes") {
                        viewModel.clearCachedQuotes()
                    }
                    Button("Clear Cached News") {
                        newsViewModel.clearCachedNews()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct StatusCapsule: View {
    let title: String
    let tint: Color
    let foreground: Color

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint)
            .clipShape(Capsule())
    }
}

private struct RefreshStatusCapsule: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Refreshing")
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
    }
}

private struct CommodityBadgeMark: View {
    let commodity: Commodity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(background)
        .clipShape(Capsule())
    }

    private var label: String {
        switch commodity {
        case .wti:
            return "WTI"
        case .brent:
            return "BRENT"
        case .naturalGas:
            return "GAS"
        }
    }

    private var systemImage: String {
        switch commodity {
        case .wti, .brent:
            return "drop.fill"
        case .naturalGas:
            return "flame.fill"
        }
    }

    private var background: Color {
        switch commodity {
        case .wti:
            return Color(red: 0.99, green: 0.76, blue: 0.26)
        case .brent:
            return Color(red: 0.95, green: 0.52, blue: 0.26)
        case .naturalGas:
            return Color(red: 0.28, green: 0.73, blue: 0.95)
        }
    }

    private var foreground: Color {
        switch commodity {
        case .wti, .brent:
            return .black
        case .naturalGas:
            return .white
        }
    }
}

private struct ArticleSheet: View {
    let article: EnergyNewsItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SafariArticleView(url: article.link)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Energy News")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("EIA")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.secondary)
                            Text(article.title)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .lineLimit(1)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct SafariArticleView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
