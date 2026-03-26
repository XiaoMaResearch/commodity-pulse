# App Store Release Checklist

This project now includes:

- App icon asset catalog
- Support and privacy-policy web pages under `docs/`
- Unit tests under `CommodityPulseTests/`
- Shared Xcode scheme with tests wired in
- Production bundle identifier default: `com.xiaomaresearch.commoditypulse`
- Daily market data from FRED/EIA for WTI, Brent, and Henry Hub natural gas
- Energy news sourced from EIA Today in Energy with cached fallback
- In-app article reader for news headlines

Remaining admin work outside the codebase:

1. Install full Xcode and select it with `xcode-select`.
2. Open `CommodityPulse.xcodeproj`.
3. Set your Apple Developer team in `Signing & Capabilities`.
4. Confirm `Bundle Identifier` is available under your Apple account.
5. Run on simulator and physical iPhone.
6. Run tests with `Cmd+U`.
7. Enable GitHub Pages from the `docs/` folder.
8. Verify these pages are live:
   - `https://xiaomaresearch.github.io/commodity-pulse/privacy-policy.html`
   - `https://xiaomaresearch.github.io/commodity-pulse/support.html`
9. In App Store Connect, create the app record.
10. Fill metadata, screenshots, privacy answers, and support/privacy URLs.
11. Archive from Xcode and upload the build.
12. Submit for review.

High-risk review item:

- The app uses official daily public-data sources, not live market feeds. Your App Store copy, screenshots, and onboarding should not imply real-time or intraday trading data.
- If you expand beyond the current FRED/EIA daily feeds later, review the commercial terms of any replacement data provider before submission.
