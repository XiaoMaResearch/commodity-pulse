# App Store Release Checklist

This project now includes:

- App icon asset catalog
- Support and privacy-policy web pages under `docs/`
- Unit tests under `CommodityPulseTests/`
- Shared Xcode scheme with tests wired in
- Production bundle identifier default: `com.xiaomaresearch.commoditypulse`

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

- The app currently uses Alpha Vantage free-tier commodity endpoints. Before submission, confirm the commercial terms fit your distribution model and upgrade to a paid/live market-data plan if you need minute-level refresh at scale.
