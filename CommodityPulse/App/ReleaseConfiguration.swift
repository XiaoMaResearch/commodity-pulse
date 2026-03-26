import Foundation

enum ReleaseConfiguration {
    static let appStoreName = "Commodity Pulse"
    static let bundleIdentifier = "com.xiaomaresearch.commoditypulse"
    static let marketDataProviderName = "FRED (EIA source)"
    static let newsProviderName = "EIA Today in Energy"
    static let supportURL = URL(string: "https://xiaomaresearch.github.io/commodity-pulse/support.html")
    static let privacyPolicyURL = URL(string: "https://xiaomaresearch.github.io/commodity-pulse/privacy-policy.html")
    static let energyNewsPageURLs = [
        URL(string: "https://www.eia.gov/todayinenergy/"),
        URL(string: "https://www.eia.gov/todayinenergy/index.php?tg=energy")
    ].compactMap { $0 }
    static let supportEmail = "maxiaodage1@gmail.com"

    // Keep this empty in source control. Prefer injecting FRED_API_KEY
    // through your Xcode scheme environment variables for local/device builds.
    private static let fredAPIKeyOverride = ""

    static var fredAPIKey: String {
        let inline = fredAPIKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty {
            return inline
        }

        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "FRED_API_KEY") as? String {
            let trimmed = bundleKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let environmentKey = ProcessInfo.processInfo.environment["FRED_API_KEY"] {
            let trimmed = environmentKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return ""
    }
}
