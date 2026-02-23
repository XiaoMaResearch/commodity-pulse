# Commodity Tracker iOS App (Xcode Local Preview + App Store Guide)

This repo includes a ready-to-use SwiftUI codebase for an iOS app that tracks:
- Crude Oil (`CL=F`)
- Natural Gas (`NG=F`)
- Gold (`GC=F`)
- Silver (`SI=F`)

Features implemented:
- Auto refresh every 1 minute
- Manual refresh button
- Pull-to-refresh gesture
- Last updated time + market timestamp
- Favorites (star), Favorites filter, and persisted preferences
- Cached quotes fallback for poor connectivity
- Enhanced loading, empty, info, and error states
- In-app Settings sheet with maintenance/disclaimer

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
5. Build and run on Simulator or iPhone.

Notes:
- Data source uses Yahoo Finance quote endpoint.
- Prices may be delayed based on market/data provider policies.

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
- Add true historical chart API and real historical sparkline data
- Add unit tests for service parsing + view model cache/favorites behavior
- Add UI tests for refresh and favorites flows
- Replace data source with an official market data API and licensing terms suitable for production
