# Commodity Tracker iOS App (Xcode Local Preview + App Store Guide)

This repo includes a ready-to-use SwiftUI codebase for an iOS app that tracks:
- WTI Crude Oil
- Brent Crude Oil
- Natural Gas
- Energy news headlines from EIA

Features implemented:
- Optional auto refresh every 1 minute while the app is active
- Pull-to-refresh on market, chart, and news screens
- Last updated time + market timestamp
- Cached quotes fallback for poor connectivity
- Cached news fallback for temporary EIA outages
- Enhanced loading, empty, info, and error states
- Per-commodity detail screen with historical chart
- Touch-scrubbing on detail charts for exact date/price lookup
- Selectable chart ranges (`1D`, `5D`, `1M`, `3M`, `1Y`)
- Historical period stats (low, high, period change)
- Daily trend sparklines on dashboard cards (with synthetic fallback)
- Automatic retry/backoff on transient network failures
- In-app Settings sheet with maintenance/disclaimer
- Separate Energy News tab powered by EIA's official Today in Energy page
- In-app article reader for EIA headlines
- Free-tier catalog trimmed to WTI, Brent, and natural gas on daily FRED/EIA spot series
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
5. Add your FRED API key:
   - For simulator/dev runs from Xcode:
     - `Product -> Scheme -> Edit Scheme`
     - `Run -> Arguments`
     - Add environment variable `FRED_API_KEY`
   - For standalone device use after unplugging:
     - target `Info` tab
     - add custom property `FRED_API_KEY`
     - set it to your free FRED API key
6. Build and run on Simulator or iPhone.
7. Run tests with `Cmd+U` or by selecting the `CommodityPulse` scheme and choosing `Product -> Test`.

Notes:
- Price data uses FRED daily spot series sourced from the U.S. Energy Information Administration:
  - `DCOILWTICO` for WTI
  - `DCOILBRENTEU` for Brent
  - `DHHNGSP` for Henry Hub natural gas
- Energy headlines come from the official EIA `Today in Energy` website.
- These feeds are daily spot data, not minute-by-minute futures data.
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

- Add UI tests for refresh, chart, and news-reader flows
- Replace the local FRED key workflow with a production-safe key delivery strategy before broad distribution
- Add final App Store screenshots, marketing copy, and a clearer in-app onboarding screen
