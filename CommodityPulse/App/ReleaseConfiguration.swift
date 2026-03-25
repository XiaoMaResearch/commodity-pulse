import Foundation

enum ReleaseConfiguration {
    static let appStoreName = "Commodity Pulse"
    static let bundleIdentifier = "com.xiaomaresearch.commoditypulse"
    static let marketDataProviderName = "Alpha Vantage"
    static let supportURL = URL(string: "https://xiaomaresearch.github.io/commodity-pulse/support.html")
    static let privacyPolicyURL = URL(string: "https://xiaomaresearch.github.io/commodity-pulse/privacy-policy.html")
    static let supportEmail = "maxiaodage1@gmail.com"

    // Keep this empty in source control. Prefer injecting ALPHA_VANTAGE_API_KEY
    // through your Xcode scheme environment variables for local/device builds.
    private static let alphaVantageAPIKeyOverride = ""

    static var alphaVantageAPIKey: String {
        let inline = alphaVantageAPIKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty {
            return inline
        }

        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "ALPHA_VANTAGE_API_KEY") as? String {
            let trimmed = bundleKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let environmentKey = ProcessInfo.processInfo.environment["ALPHA_VANTAGE_API_KEY"] {
            let trimmed = environmentKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return ""
    }
}
