# MenuBarBuddy Launch Plan ($4.20, one time)

Built by a 45-agent armada ensemble on 2026-07-08 (plus a 53-agent code review the same day). This is the master doc; details live in the sibling docs.

## The decision: direct web download. No Mac App Store for v1.

The dealbreaker is technical, not the price: the self-repair watchdog (the product's moat) rewrites its own Info.plist, bumps its bundle ID, re-signs itself at runtime, and inspects other apps' windows via CGWindowList. Every one of those is forbidden in the Mac App Store sandbox. Shipping on MAS means shipping a categorically weaker app under the same name. The $4.20 price point on MAS is also uncertain (Apple's tier list may force $3.99 or $4.99, breaking the brand), and the meme price plus wink copy is a subjective App Review rejection surface. Full reasoning: DISTRIBUTION.md.

Confirmation from the field: during asset capture on this very Mac, Tahoe's Control Center host orphaned the app's items (heavy status-item churn). A Control Center restart did NOT fix it. `--force-repair` did, live, migrating v7 to v8 with settings intact. The moat is real; it was witnessed working today. That machinery cannot survive sandboxing.

## The stack

- Payments: Lemon Squeezy checkout at exactly $4.20 (merchant of record, handles VAT, issues license keys). See LICENSING-PAYMENTS.md.
- Delivery: Developer-ID-signed, notarized, stapled DMG. GitHub Releases or Lemon Squeezy hosted.
- Updates: Sparkle 2 with an EdDSA-signed appcast on GitHub Pages.
- Repo: stays PUBLIC, but add a LICENSE first (recommended: PolyForm Noncommercial 1.0.0). There is NO LICENSE file today, so the code is all-rights-reserved by default and "open source" claims are not yet legally true. The landing page copy already hedges ("developed in the open").
- Site: site/index.html (single file, zero build). GitHub Pages target: https://cfranci.github.io/MenuBarBuddy

## What exists right now

- site/index.html — complete landing page: animated menu bar demo in the hero (dot collapses icons, matches the real app), features, real screenshots, demo video, $4.20 pricing card, FAQ, full OG meta. Placeholders remaining: {BUY_URL} x4, {SUPPORT_EMAIL} x2.
- site/assets/ — all real captures from the live app on this Mac (macOS 26 Tahoe): before.png, after.png (collapse contrast, same minute), menu.png (context menu), demo.mp4 (23s, 65KB), poster.png, og.png (social card), demo.gif (bonus for README/Product Hunt).
- docs/DISTRIBUTION.md, LICENSING-PAYMENTS.md, BRAND-COPY.md, ASSETS-RUNBOOK.md, SYNTHESIS.md, pre-launch-review.md.

## Go-live checklist (in order)

1. Fix the fix-before-charging list in pre-launch-review.md. Biggest: the dead "Folder Icon" settings picker (decide: delete it and ship a Dot Style section, or wire it end to end), the settings-window observer leak, timers in .default run-loop mode, the /bin/sh path interpolation in self-repair.
2. Commit a LICENSE (PolyForm NC 1.0.0 recommended).
3. Apple Developer Program ($99/yr) if not already enrolled for this: Developer ID cert, then fix install.sh ad-hoc signing (`codesign --force -s -`) to Developer ID + hardened runtime + notarize + staple. NOTE: the runtime self-repair re-sign must be flag-gated for the notarized build (see DISTRIBUTION.md; ad-hoc re-signing a notarized bundle breaks Gatekeeper on relaunch). Acceptance gate: force-trigger --force-repair on a stock Mac that never built the app.
4. Lemon Squeezy account, product at $4.20, license keys on. Fill {BUY_URL}.
5. Pick the support inbox. Fill {SUPPORT_EMAIL}.
6. Enable GitHub Pages on the repo (serve /site or move to /docs), verify og.png renders in link previews.
7. Sparkle appcast + first notarized DMG release.
8. Launch posts: Product Hunt, Show HN (lead with the Tahoe self-repair engineering story; it happened live during this asset session), r/macapps. Blurbs in BRAND-COPY.md.

## Open questions for Ga'noh

- Custom icons feature: delete (ship "Dot Style: Green / Rainbow") or fix end to end? The review recommends delete; the landing page already only claims the dot.
- License: PolyForm NC vs MIT vs stay source-visible. Blocks the "open" marketing claim.
- Trial: v1 ships with no packaged trial ("build from source" is the honest trial). The 14-day design in LICENSING-PAYMENTS.md is roadmap. OK?
- Seat policy: 3 activations per key via a tiny Cloudflare Worker, or honor-system offline keys only (DRM-as-theater stance)? At $4.20 the review leans light.
- Support email address and whether to buy menubarbuddy.app (~$15/yr) or stay on cfranci.github.io.
