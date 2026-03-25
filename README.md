# Commodity Tracker iOS App (Xcode Local Preview + App Store Guide)

This repo includes a ready-to-use SwiftUI codebase for an iOS app that tracks:
- WTI Crude Oil
- Brent Crude Oil
- Natural Gas
- Gold
- Silver
- Corn
- Platinum (UI placeholder on current free-tier provider)
- Soybeans (UI placeholder on current free-tier provider)

Features implemented:
- Two market tabs: `Oil & Gas` and `Commodities`
- Auto refresh every 1 minute
- Manual refresh button
- Pull-to-refresh gesture
- Last updated time + market timestamp
- Favorites (star), Favorites filter, and persisted preferences
- Cached quotes fallback for poor connectivity
- Enhanced loading, empty, info, and error states
- Per-commodity detail screen with historical chart
- Selectable chart ranges (`1D`, `5D`, `1M`, `3M`, `1Y`)
- Historical period stats (low, high, period change)
- Daily trend sparklines on dashboard cards (with synthetic fallback)
- Top gainer / top loser market snapshot panel
- Automatic retry/backoff on transient network failures
- In-app Settings sheet with maintenance/disclaimer
- Unsupported instruments are shown explicitly as unavailable instead of silently disappearing
- App icon asset catalog and accent color asset catalog
- XCTest target with service and view-model coverage
- Privacy policy and support pages under `docs/`

## 1) Open in Xcode (local preview)

1. Install full Xcode from the App Store.
2. Ensure developer tools point to Xcode:
   - `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
   - `sudo xcodebuild -runFirstLaunch`
3. Open this project directly:
   - `open "/Users/manqingguo/Documents/New project/CommodityPulse.xcodeproj"`
4. In project settings, set:
   - Team
   - Bundle Identifier (e.g., `com.yourname.commoditypulse`)
5. Add your Alpha Vantage API key:
   - In Xcode, go to `Product -> Scheme -> Edit Scheme`
   - Select `Run -> Arguments`
   - Under `Environment Variables`, add `ALPHA_VANTAGE_API_KEY`
   - Set its value to your free Alpha Vantage API key
6. Build and run on Simulator or iPhone.
7. Run tests with `Cmd+U` or by selecting the `CommodityPulse` scheme and choosing `Product -> Test`.

Notes:
- Data source uses Alpha Vantage commodity endpoints.
- The free-tier provider returns delayed daily commodity series, not intraday futures ticks.
- The app still supports manual refresh and periodic refresh, but free-tier provider limits will cap how often the server can be queried successfully.
- App Store support/privacy pages can be published from the `docs/` folder using GitHub Pages.

## 2) Publish to App Store (step-by-step)

1. Apple Developer account
   - Enroll in Apple Developer Program (paid).

2. App ID + signing
   - In Xcode, set a unique Bundle Identifier (e.g., `com.yourname.commoditypulse`).
   - Enable Automatic Signing with your Team.

3. App metadata in App Store Connect
   - Go to App Store Connect -> My Apps -> New App.
   - Fill app name, bundle ID, primary language, SKU.

4. Prepare assets
   - App icon (all required sizes)
   - Screenshots for required device sizes
   - Privacy policy URL (required)
   - Description, keywords, support URL

5. Versioning
   - In Xcode target: set Version (`1.0`) and Build (`1`).

6. Archive build
   - In Xcode: select `Any iOS Device (arm64)`.
   - Product -> Archive.

7. Upload build
   - In Organizer: select archive -> Distribute App -> App Store Connect -> Upload.

8. Complete App Store listing
   - In App Store Connect, open the app version.
   - Select uploaded build.
   - Fill age rating, category, content rights, privacy labels.

9. Submit for review
   - Click Submit for Review.
   - Resolve any review feedback if needed.

10. Release
   - Choose manual release or automatic release after approval.

## 3) Recommended next improvements before publishing

- Add selectable currency and units
- Add UI tests for refresh and favorites flows
- Upgrade to a paid market data plan that supports minute-level updates and commercial distribution
