import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var viewModel = CommodityViewModel()
    @StateObject private var newsViewModel = EnergyNewsViewModel()
    @State private var selectedTab: AppTab = .market
    @State private var cardVisible = false
    @State private var showingSettings = false
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
                    Label("WTI", systemImage: "drop.fill")
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
                                        sparklinePoints: viewModel.sparklinePoints(for: quote.commodity),
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
            .refreshable { await viewModel.refresh() }
            .task {
                await viewModel.refresh()
                await viewModel.refreshSparklinesIfNeeded()
                viewModel.startAutoRefresh()
                cardVisible = true
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    viewModel.startAutoRefresh()
                    Task {
                        await viewModel.refresh()
                        await viewModel.refreshSparklinesIfNeeded(force: true)
                    }
                } else if newPhase == .background {
                    viewModel.stopAutoRefresh()
                }
            }
            .onDisappear { viewModel.stopAutoRefresh() }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(viewModel: viewModel)
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
                            lastUpdated: newsViewModel.lastUpdated
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
                                    EnergyNewsCard(article: article)
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
                Text("WTI Crude Oil")
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
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Commodity Pulse")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("WTI spot tracker with EIA energy news")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                Spacer()

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

private struct MarketSnapshotPanel: View {
    let topGainer: CommodityQuote?
    let topLoser: CommodityQuote?
    let isLoadingSparklines: Bool

    var body: some View {
        HStack(spacing: 10) {
            SnapshotPill(
                title: "Top Gainer",
                quote: topGainer,
                tint: Color(red: 0.3, green: 0.95, blue: 0.6)
            )
            SnapshotPill(
                title: "Top Loser",
                quote: topLoser,
                tint: Color(red: 1.0, green: 0.45, blue: 0.45)
            )
        }
        .overlay(alignment: .topTrailing) {
            if isLoadingSparklines {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.75))
                    .padding(8)
            }
        }
    }
}

private struct SnapshotPill: View {
    let title: String
    let quote: CommodityQuote?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
            Text(quote?.commodity.name ?? "--")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(changeText)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var changeText: String {
        guard let quote else { return "--" }
        let sign = quote.changePercent >= 0 ? "+" : ""
        return "\(sign)\(quote.changePercent.formatted(.number.precision(.fractionLength(2))))%"
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
    let sparklinePoints: [CommodityPricePoint]
    let onOpenDetails: () -> Void

    private var changeColor: Color {
        quote.change > 0 ? Color(red: 0.3, green: 0.95, blue: 0.6) : (quote.change < 0 ? Color(red: 1.0, green: 0.45, blue: 0.45) : Color.white.opacity(0.75))
    }

    private var priceText: String {
        quote.price.formatted(.number.precision(.fractionLength(2)))
    }

    private var changeText: String {
        let sign = quote.change > 0 ? "+" : ""
        let change = quote.change.formatted(.number.precision(.fractionLength(2)))
        let percent = quote.changePercent.formatted(.number.precision(.fractionLength(2)))
        return "\(sign)\(change) (\(sign)\(percent)%)"
    }

    private var snapshotText: String {
        guard let marketTime = quote.marketTime else { return "--" }
        return marketTime.formatted(date: .abbreviated, time: .omitted)
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
                Button(action: onOpenDetails) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Open historical chart")
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("$\(priceText)")
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(snapshotText)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                Text(changeText)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(changeColor)
            }

            HStack {
                TrendSparkline(quote: quote, lineColor: changeColor, realPoints: sparklinePoints)
                    .frame(height: 38)
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

private struct TrendSparkline: View {
    let quote: CommodityQuote
    let lineColor: Color
    let realPoints: [CommodityPricePoint]

    private var points: [CGFloat] {
        if realPoints.count > 1 {
            let prices = realPoints.map(\.price)
            let low = prices.min() ?? 0
            let high = prices.max() ?? 0
            let span = max(high - low, 0.0001)

            return prices.map { price in
                let normalized = ((price - low) / span) * 2 - 1
                return CGFloat(normalized)
            }
        }

        let seed = quote.commodity.rawValue.unicodeScalars.map(\.value).reduce(0, +)
        let magnitude = min(max(abs(quote.changePercent) / 3.0, 0.3), 1.4)

        return (0..<20).map { index in
            let wave = sin(CGFloat(index) * 0.55 + CGFloat(seed % 10))
            let drift = CGFloat(index) / 19.0 * CGFloat(quote.change >= 0 ? 1 : -1) * CGFloat(magnitude) * 0.45
            return wave * 0.22 + drift
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let step = width / CGFloat(max(points.count - 1, 1))

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                Path { path in
                    for (idx, value) in points.enumerated() {
                        let x = CGFloat(idx) * step
                        let y = height * 0.5 - value * height * 0.42
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
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
                        value: quote.marketTime?.formatted(date: .abbreviated, time: .omitted) ?? "--"
                    )
                    DetailMetaPill(
                        title: "Cadence",
                        value: "Daily Spot"
                    )
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
                        Text(date, format: xAxisFormat)
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
                    Text(selectedPoint.date, format: selectedDateFormat)
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

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .oneDay:
            return .dateTime.month(.abbreviated).day()
        case .fiveDays:
            return .dateTime.month(.abbreviated).day()
        case .oneMonth, .threeMonths:
            return .dateTime.month(.abbreviated).day()
        case .oneYear:
            return .dateTime.month(.abbreviated)
        }
    }

    private var selectedDateFormat: Date.FormatStyle {
        switch selectedRange {
        case .oneDay, .fiveDays:
            return .dateTime.month(.abbreviated).day().year()
        case .oneMonth, .threeMonths, .oneYear:
            return .dateTime.month(.abbreviated).day().year()
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
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text("Updated \(lastUpdated?.formatted(date: .omitted, time: .standard) ?? "--")")
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

private struct EnergyNewsCard: View {
    let article: EnergyNewsItem

    var body: some View {
        Link(destination: article.link) {
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
                    Text("Open Article")
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                    Image(systemName: "arrow.up.right")
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    Text("WTI source: \(ReleaseConfiguration.marketDataProviderName)")
                    Text("Energy news source: \(ReleaseConfiguration.newsProviderName)")
                    Text("WTI is daily spot data and may not update intraday.")
                    Text("Prices and news are for informational use only.")
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
                    Text("Auto refresh is off by default for the daily WTI feed.")
                    Text("When enabled, refresh runs every 60 seconds while the app is active.")
                    Text("WTI source data is daily, so most minute-by-minute refreshes will not change the price.")
                    Text("Manual refresh is always available from the dashboard, chart view, and news page.")
                }

                Section("Maintenance") {
                    Button("Clear Cached Quotes") {
                        viewModel.clearCachedQuotes()
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
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
