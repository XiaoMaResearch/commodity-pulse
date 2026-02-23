import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CommodityViewModel()
    @State private var cardVisible = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeaderPanel(
                            lastUpdated: viewModel.lastUpdated,
                            isLoading: viewModel.isLoading,
                            onRefresh: { Task { await viewModel.refresh() } },
                            onSettings: { showingSettings = true }
                        )

                        Picker("Filter", selection: $viewModel.selectedFilter) {
                            ForEach(QuoteFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)

                        if let info = viewModel.infoMessage {
                            InfoPanel(message: info)
                        }

                        if let error = viewModel.errorMessage {
                            ErrorPanel(message: error)
                        }

                        if viewModel.isLoading && viewModel.displayedQuotes.isEmpty {
                            LoadingCards()
                        } else if viewModel.displayedQuotes.isEmpty {
                            EmptyState(hasFavorites: viewModel.hasFavorites, selectedFilter: viewModel.selectedFilter)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(Array(viewModel.displayedQuotes.enumerated()), id: \.element.id) { index, quote in
                                    CommodityCard(
                                        quote: quote,
                                        isFavorite: viewModel.isFavorite(quote.commodity),
                                        onFavoriteTap: { viewModel.toggleFavorite(quote.commodity) }
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
                viewModel.startAutoRefresh()
                cardVisible = true
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    viewModel.startAutoRefresh()
                    Task { await viewModel.refresh() }
                } else if newPhase == .background {
                    viewModel.stopAutoRefresh()
                }
            }
            .onDisappear { viewModel.stopAutoRefresh() }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(viewModel: viewModel)
            }
        }
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
    let isLoading: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Commodity Pulse")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Live overview: oil, gas, gold, silver")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                Spacer()

                HStack(spacing: 10) {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Open Settings")

                    Button(action: onRefresh) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.black)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.99, green: 0.76, blue: 0.26))
                        .clipShape(Capsule())
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh Quotes")
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
    let hasFavorites: Bool
    let selectedFilter: QuoteFilter

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
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

    private var title: String {
        selectedFilter == .favorites ? "No Favorites Yet" : "No Quotes Available"
    }

    private var subtitle: String {
        if selectedFilter == .favorites && !hasFavorites {
            return "Tap the star on a commodity card to add it to your favorites list."
        }
        return "Pull down to refresh or use the Refresh button."
    }
}

private struct LoadingCards: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 116)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

private struct CommodityCard: View {
    let quote: CommodityQuote
    let isFavorite: Bool
    let onFavoriteTap: () -> Void

    private var changeColor: Color {
        quote.change > 0 ? Color(red: 0.3, green: 0.95, blue: 0.6) : (quote.change < 0 ? Color(red: 1.0, green: 0.45, blue: 0.45) : Color.white.opacity(0.75))
    }

    private var priceText: String {
        quote.price.formatted(.number.precision(.fractionLength(2)))
    }

    private var changeText: String {
        let change = quote.change.formatted(.number.precision(.fractionLength(2)))
        let percent = quote.changePercent.formatted(.number.precision(.fractionLength(2)))
        return "\(change) (\(percent)%)"
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
                Button(action: onFavoriteTap) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color(red: 0.99, green: 0.76, blue: 0.26) : Color.white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .accessibilityLabel(isFavorite ? "Remove Favorite" : "Add Favorite")
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("$\(priceText)")
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(quote.marketTime?.formatted(date: .omitted, time: .shortened) ?? "--")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                Text(changeText)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(changeColor)
            }

            TrendSparkline(quote: quote, lineColor: changeColor)
                .frame(height: 38)
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

    private var points: [CGFloat] {
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

private struct SettingsSheet: View {
    @ObservedObject var viewModel: CommodityViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    Text("Source: Yahoo Finance quote endpoint.")
                    Text("Quotes may be delayed and are for informational use only.")
                }

                Section("Preferences") {
                    Text("Auto-refresh runs every 60 seconds while app is active.")
                    Text("Manual refresh is always available from the dashboard.")
                }

                Section("Maintenance") {
                    Button("Clear Cached Quotes") {
                        viewModel.clearCachedQuotes()
                    }
                    Button("Reset Favorites & Filter") {
                        viewModel.resetPreferences()
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
