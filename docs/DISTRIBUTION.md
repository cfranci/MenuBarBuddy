# Distribution Strategy (Armada stitched output, 2026-07-08)

# Distribution Strategy: MenuBarBuddy

## FIRM RECOMMENDATION: Ship DIRECT WEB DOWNLOAD ONLY — a Developer-ID-signed, notarized, stapled DMG, sold through a merchant-of-record checkout (Lemon Squeezy) at exactly $4.20, auto-updated via Sparkle 2, with the GitHub repo kept PUBLIC but relicensed source-available. Skip the Mac App Store for v1.

This is not a close call. The single decisive reason is technical, not the price. Two more constraints reinforce it. Below: the decision and its code-verified evidence, then the repo call, then the plumbing (notarization, the two ship-blocking signing bugs, updates), then a sequenced launch checklist with reusable artifacts.

---

## Why direct, not the Mac App Store

### 1. THE DEALBREAKER (code-verified): the self-repair watchdog is structurally incompatible with the MAS sandbox

MenuBarBuddy's single biggest differentiator, the thing that lets it survive Tahoe's menu-bar orphaning bug when Bartender/Ice users get bitten, is `performSelfRepair()`. I read it. At `AppDelegate.swift:831-848` it:

1. Rewrites its own `Info.plist` to bump `CFBundleIdentifier` (`SettingsStore.nextBundleID`, currently `com.menubarbuddy.v6` -> `v7` -> ...; line 840),
2. Shells out `sleep 1; /usr/bin/codesign --force -s - "<bundlePath>"; sleep 1; /usr/bin/open "<bundlePath>"` (line 848) to re-sign itself ad-hoc AT RUNTIME and relaunch,
3. Migrates prefs by reading prior domains `com.menubarbuddy.v3..vN` (`SettingsStore.swift:42`),
4. Inspects other apps' windows via `CGWindowListCopyWindowInfo` (`AppDelegate.swift:203`) to find orphaned status-item windows.

Every one of those four steps is forbidden or gated in the MAS App Sandbox: runtime code signing, writing to your own bundle, mutating the bundle ID at runtime (MAS requires a stable ID and tracks updates by it, so every future orphaning event that fires self-repair would break the store's update delivery), reading foreign process domains, and CGWindowList inspection of other apps. To pass sandbox review you would rip out the entire watchdog and replace it with, at best, "here's a button you might need to click." That ships a categorically weaker product under the same name and voids the marketing claim ("it heals itself" becomes "click Repair sometimes"). This alone ends the MAS conversation, and unlike the price argument it is not debatable.

(Hidden Bar IS on MAS and proves a menu-bar hider *can* be sandboxed, but only because it is architecturally simpler: static visibility toggling, no dynamic length push, no runtime re-sign, no bundle-ID mutation. MenuBarBuddy's approach is categorically different, so Hidden Bar's presence on the store is not a counterexample.)

### 2. The $4.20 price is a real MAS risk, but NOT the lead reason

Honest read, because the source drafts openly disagreed and one flatly got this wrong: Apple's post-March-2023 pricing added ~900 tiers at $0.10 granularity, so whether exactly $4.20 is selectable in App Store Connect for the US storefront is genuinely uncertain and depends on Apple's generated tier set for your base currency (the classic grid gave you $3.99/$4.99 with no $4.20). Do NOT build the recommendation on "$4.20 is impossible on MAS", because it is the shakiest assertion in the whole analysis, and if it turns out false the argument collapses. You do not need it: reason #1 already kills MAS. Treat the price as a secondary risk (you may be forced to $3.99 or $4.99, breaking the meme that is the brand) rather than the headline. Direct sale removes the risk entirely by charging literally $4.20 with zero ambiguity.

### 3. The meme-price review risk + a per-unit cut that buys you nothing

- A $4.20 price with a "why $4.20? (you know why)" wink in the metadata is exactly the subjective-rejection surface App Review guideline 1.1 ("objectionable") is known for. Direct sale has no reviewer, so the joke lives.
- Economics: on MAS under the Small Business Program (15%, since revenue is well under $1M) Apple takes ~$0.63, leaving ~$3.57; at the default 30% you net ~$2.94. Direct via Lemon Squeezy (~5% + ~$0.50/txn, merchant-of-record so it eats VAT) nets ~$3.49 and hands you the buyer's email for future products. (Exact fees live in the licensing-payments section.) The per-unit money is roughly a wash at the SBP rate; the point is that MAS costs you the price certainty, the moat, AND the direct customer relationship while returning nothing you cannot get direct.

### 4. Discoverability is the ONE real thing you give up, and you win it a better way

MAS search ("menu bar manager") is genuinely valuable traffic you forgo. But your differentiator is a NARRATIVE, not a keyword you can outrank Bartender's marketing budget on. Win it the way indie Mac utilities actually win:
- A strong single-page landing site with the $4.20 price front and center (landing-page section).
- A Product Hunt launch ("$4.20 menu bar hider, open source, Tahoe-proof, not $20 like Bartender").
- Hacker News "Show HN" leading with the engineering story (bundle-ID blacklisting, ObjC `NSException` shielding via the ExceptionShield target, CGWindowList orphan recovery, the self-repair watchdog), genuinely HN-grade content.
- r/macapps + MacRumors + AlternativeTo, leaning on the 2024 Bartender trust scandal (new owners quietly added analytics), an open door for a "read every line, no telemetry" pitch.
- The public repo's own SEO for "menu bar hider macOS Tahoe."

---

## The GitHub repo: keep it PUBLIC, but fix the license first (the nuance all four source drafts missed)

Critical fact none of the source analyses caught, verified just now: **there is no LICENSE file in the repo.** That means it is currently "all rights reserved" by default. It is source-VISIBLE, not open-source: anyone can read it, but no one has any legal right to build, run, redistribute, or resell it. So the "it's open source" trust story everyone is leaning on is not legally true today, and paradoxically no one is even permitted to build it for personal use. Do not market it as "open source" until this is fixed. Fix it first, deliberately:

- **Keep the repo PUBLIC.** It is your sharpest weapon: an auditable codebase is the direct counter to the Bartender trust scandal. It is also SEO and a distribution channel in itself (stars, HN/Reddit links). Going private throws all of that away and stops zero piracy (the code is already cloneable in the wild).
- **Add an explicit source-available `LICENSE`: PolyForm Noncommercial 1.0.0.** Effect: anyone may read, audit, and build for personal use, but may NOT redistribute or resell. This simultaneously (a) ENABLES the honest "build it yourself for free" path, which currently is not actually granted, and (b) closes the fork-and-resell hole a permissive MIT would leave open. It is the single highest-leverage pre-launch legal fix.
- **Open-core split.** Keep the paid machinery (Ed25519 license public key baked into the binary, license activation flow, Sparkle signing keys, Developer-ID notarization) OUT of the public tree, so the public repo builds a fully functional but ad-hoc-signed, manually-installed FREE local build, and the notarized release adds the supporter niceties: signed double-click DMG, auto-updates, support. Bake only the Ed25519 PUBLIC key into the release build.
- **The pitch, which the low price makes honest:** "pay $4.20, or spend an afternoon installing Xcode and building it yourself." At $4.20 the friction of cloning + toolchain + build exceeds the price, so DRM is theater. Do not invest in hard license enforcement; you are selling convenience + auto-updates + support + paying the person who fixed the Tahoe bug, not preventing theft.

---

## Notarization, the two self-repair signing bugs, and updates

### Switch install.sh's ad-hoc signing to Developer ID (non-negotiable)

`install.sh:12` is `codesign --force -s - "$APP"` (ad-hoc). That is fine for your own Mac but triggers Gatekeeper's "unidentified developer" wall for every downloader, a hard conversion killer. For distribution you need the Apple Developer Program ($99/yr), a "Developer ID Application" cert, Hardened Runtime, and notarization. The switch is mechanical:

```bash
codesign --force --options runtime --timestamp \
  -s "Developer ID Application: <Name> (<TEAMID>)" MenuBarBuddy.app
xcrun notarytool submit MenuBarBuddy.dmg --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple MenuBarBuddy.dmg
```

### SHIP-BLOCKING: two self-repair interactions with signing break the notarized build in the field

Both come straight from the repo's own mechanism and MUST be fixed before launch, or the feature that makes the app worth buying bricks itself on first use in the wild.

1. **Self-repair invalidates the notarized signature.** A Developer-ID + Hardened-Runtime build that self-mutates its bundle ID and ad-hoc re-signs at runtime destroys its own Developer ID signature. **Fix: flag-gate the aggressive path with `#if AD_HOC_BUILD`.** Local/dev builds keep the full self-mutation capability; the notarized release build compiles it OUT. The full watchdog DETECTION logic (the CGWindowList orphan scan, the whole value) stays in the signed build; ONLY the runtime bundle-ID mutation + ad-hoc re-sign step is removed.

2. **Gatekeeper blocks the relaunch after self-repair on end-user machines** (the ship-blocking bug only the deepest analysis surfaced, missed by the other three). Even if the DMG installs clean, the moment self-repair fires on a stock Mac it relaunches an ad-hoc-signed bundle that no longer carries the Developer ID signature, and with Gatekeeper on plus library validation under Hardened Runtime, that relaunch can be blocked. **Fix: in the signed build, the degrade is NOT an in-place re-sign.** When detection fires, either (a) relaunch the SAME already-signed bundle via a "Repair & Relaunch" alert, or (b) if a genuinely orphaned bundle-ID requires a fresh copy, open a fresh-download flow (GitHub Releases URL / Sparkle update) and REPLACE the bundle with a clean signed copy rather than re-signing it in place. **TEST this explicitly:** install the notarized DMG on a machine that never built it, force-trigger repair (`--force-repair`), and confirm the relaunch is NOT Gatekeeper-blocked. This is a launch-day bug, not a theoretical one.

### Updates: Sparkle 2 (net-new work, no Sparkle in the repo today)

Verified: `Package.swift` has only `HotKey` (soffes, from 0.2.0) and the `ExceptionShield` ObjC shim; there is no `SUFeedURL`, `SUPublicEDKey`, or appcast anywhere in the tree. Since you are not on MAS (which would hand you updates free), add Sparkle 2 via SPM:

- Add `.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")`.
- Generate an EdDSA key pair with Sparkle's `generate_keys`; store the private key in Keychain, bake `SUPublicEDKey` into Info.plist.
- Host an EdDSA-signed `appcast.xml` on GitHub Pages (`docs/appcast.xml` -> `https://cfranci.github.io/MenuBarBuddy/appcast.xml`); set `SUFeedURL` in Info.plist. Sign each DMG with `sign_update`; the notarized DMG is the GitHub Release enclosure asset.
- Wire `SPUStandardUpdaterController` in `applicationDidFinishLaunching`, add a "Check for Updates…" context-menu item, and check on launch.
- Correct Sparkle namespace: `http://www.andymatuschak.org/xml-namespaces/sparkle`. NOTE: one source template fabricated a bogus namespace (`andymatriculia.com` / similar). Do NOT copy it.

This is your emergency-update path: the inevitable "macOS 27 broke the length cap again" fix reaches every paying user in a day, latency that MAS review would deny you.

### Refunds

Direct = you own the policy. At $4.20 with a free "build it yourself" escape hatch, refund abuse is a non-issue: offer a no-questions refund in the FAQ. It costs almost nothing and builds trust, versus MAS where Apple owns refunds out of your control.

---

## Competitive position

| Product | Price | Distribution | Source |
|---|---|---|---|
| Bartender 5 | ~$20-22 | Direct (notarized DMG) | Closed (2024 trust scandal) |
| Ice | Free | Direct (notarized DMG) | Open (MIT) |
| Hidden Bar | Free | Mac App Store | Open (MIT) |
| **MenuBarBuddy** | **$4.20** | **Direct (notarized DMG)** | **Source-available (PolyForm NC)** |

The honest one-liner: "Bartender costs $20 and had a trust scandal. Ice is free but occasionally breaks on Tahoe. MenuBarBuddy is $4.20, source-available with no telemetry, and has a self-healing watchdog for the exact bug that bites the others." Keep the price at exactly $4.20 everywhere and never discount it, the meme only works if it is consistent, and people screenshot "$4.20" for free reach.

---

## FINAL RECOMMENDATION (one line)

Ship direct only, a Developer-ID-signed, notarized, stapled DMG on a $4.20 Lemon Squeezy checkout, Sparkle auto-updates from a self-hosted EdDSA appcast, GitHub repo kept PUBLIC but relicensed PolyForm Noncommercial as open-core, and skip the Mac App Store for v1, because self-repair (the moat) is structurally incompatible with the sandbox, MAS returns nothing the direct path does not, and both signing bugs must be fixed for the DMG regardless.

---

## LAUNCH CHECKLIST (sequenced: legal/identity -> sellable artifact -> plumbing -> automation -> verify -> launch)

### Phase 0 — Legal & identity (do FIRST; blocks everything downstream)
- [ ] Enroll in the Apple Developer Program ($99/yr); record the Team ID.
- [ ] Create a "Developer ID Application" certificate; install it in the login keychain.
- [ ] Store notarization creds: `xcrun notarytool store-credentials AC_PASSWORD --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>`.
- [ ] **Add a `LICENSE` file: PolyForm Noncommercial 1.0.0.** Add a short NOTICE explaining open-core (free if self-built; $4.20 for the notarized, auto-updating convenience build). Commit and push. (Fixes the current all-rights-reserved state and is what first legally grants the free-build path.)

### Phase 1 — Build the sellable artifact
- [ ] Add `release.sh` (separate from install.sh): `swift build -c release` -> assemble the .app from Support/Info.plist -> `codesign --force --options runtime --timestamp -s "Developer ID Application: …"` -> package a DMG (`create-dmg` or `hdiutil create -format UDZO`).
- [ ] **Flag-gate self-repair with `#if AD_HOC_BUILD`:** signed build keeps watchdog DETECTION, drops the runtime bundle-ID mutation + ad-hoc re-sign at `AppDelegate.swift:840,848`; the local/dev build keeps the full aggressive path.
- [ ] **Fix the Gatekeeper-after-self-repair path:** signed build degrades to "Repair & Relaunch" (same signed bundle) or a fresh-download-and-replace flow, never an in-place ad-hoc re-sign.
- [ ] Bake the Ed25519 license PUBLIC key into the release build; keep validation/activation code out of the public tree (licensing-payments section owns the logic) so the public tree still builds a working free binary.
- [ ] Notarize + staple; verify: `xcrun stapler validate` and `spctl -a -t open --context context:primary-signature MenuBarBuddy.dmg`.

### Phase 2 — Payment, updates, and distribution plumbing
- [ ] Lemon Squeezy: create the product at exactly **$4.20 USD**, enable License Keys, capture the API key + webhook secret (store chmod 600 / in Keychain). License key format `MBB-XXXXX-XXXXX-XXXXX`; payload `{key, email, purchased_at, expires_at|null}` signed Ed25519, validated offline-first with an online fallback to the Lemon Squeezy API.
- [ ] Add a `LicenseManager` Swift class (Keychain storage; menu shows "Licensed to <email>" / "Trial (N days) - Buy" / "Manage License..."). "Buy" opens the checkout in the default browser.
- [ ] Add Sparkle 2 via SPM; EdDSA-sign `appcast.xml`; host on GitHub Pages; point the DMG enclosure at the GitHub Release asset; add a "Check for Updates…" menu item.
- [ ] Stand up the landing page (landing-page section) with the buy button; host on GitHub Pages (`docs/`), custom domain `menubarbuddy.app` (~$15/yr) optional but adds credibility.
- [ ] Update README with a "Purchase" section (the $4.20 buy link) AND keep the documented "build it yourself" path (a feature, not a leak).

### Phase 3 — Release automation (optional but recommended; lift from the runbook attempt)
- [ ] GitHub Actions `release.yml`, tag-triggered (`v*`): checkout -> import Developer ID cert from base64 secret -> `swift build -c release` -> `create-dmg.sh` -> `notarize.sh` -> `softprops/action-gh-release` -> regenerate + commit `appcast.xml`.
- [ ] Repo secrets: `DEVELOPER_ID_CERT` (base64 .p12), `DEVELOPER_ID_CERT_PASSWORD`, `NOTARY_PASSWORD`.
- [ ] Keep `notarize.sh`, `create-dmg.sh`, `generate-appcast.sh` in `scripts/` so releases are reproducible.

### Phase 4 — Fresh-Mac verification (the acceptance gate)
- [ ] On a Mac (or user) that NEVER built the app: download the DMG, drag to /Applications, launch, confirm NO Gatekeeper warning (proves notarization/stapling).
- [ ] **Trigger `--force-repair` on that machine and confirm the relaunch succeeds with Gatekeeper on** (proves the self-repair signing fix). This gate is MANDATORY.
- [ ] Sparkle end-to-end: ship a version bump, confirm an installed copy self-updates from the appcast.
- [ ] License activation happy path + offline case with a real key (licensing-payments owns the logic; distribution confirms the notarized build accepts it).

### Phase 5 — Launch (simultaneous)
- [ ] Product Hunt (tagline from brand-copy), scheduled ~00:01 PT.
- [ ] Hacker News "Show HN: MenuBarBuddy — open source menu bar hider with a macOS 26 Tahoe self-repair watchdog ($4.20)", leading with the Tahoe story + Bartender-scandal contrast.
- [ ] r/macapps + r/macOS (with a collapse-animation GIF), MacRumors software forum, AlternativeTo/MacUpdate listings.
- [ ] Twitter/X thread (collapse GIF + Bartender-scandal contrast + "$4.20 on purpose").
- [ ] Email tip lines: MacStories, 9to5Mac, Cult of Mac (the Bartender scandal is the news hook).

### Phase 6 — Post-launch
- [ ] Support = GitHub Issues + a simple forwarding email (support@menubarbuddy.app); a $4.20 app does not need Zendesk.
- [ ] Monitor refunds (target < 5%, should be near-zero) and license-activation failure rate.
- [ ] Watch macOS 26.x/27 point releases that touch `NSStatusItem.length`; HANDOFF.md documents the exact failure modes. Re-test on each beta, keep a fast Sparkle push and a rollback path ready.
- [ ] MAS remains a possible v2 ONLY as a separately-branded, self-repair-stripped fork, never at the cost of the direct product's moat. Not a launch consideration.

## Open questions
- Does exactly $4.20 exist as a selectable US-storefront price under Apple's post-2023 granular pricing? The source drafts disagreed and it is unverified here. It does not change the recommendation (self-repair already blocks MAS independently), but confirm before making any 'MAS is impossible on price' claim publicly.
- Is '$4.20 is a hard, non-negotiable brand requirement' an actual owner constraint or an assumption from the prompt framing? The whole direct-vs-MAS calculus is robust either way, but if the price could flex to $3.99 a future MAS v2 story gets marginally easier. Worth confirming with the owner.
- Does HotKey's Carbon RegisterEventHotKey actually fail under the MAS sandbox, or is it grantable? Asserted across drafts but not verified. Matters only for a hypothetical MAS v2 (self-repair already blocks v1); settling it would need a test submission.
- Does the chosen merchant-of-record (Lemon Squeezy assumed) support the Ed25519 offline-validation flow via its license-key API, or does that need a thin self-hosted validation endpoint? Owned by the licensing-payments section but load-bearing for the 'no phone-home' claim.
- Beyond a normal Sparkle release, is there an emergency kill-switch / forced-update path if a future macOS point release changes NSStatusItem length behavior again? Worth designing before launch, not after. License-activation device-cap policy (unlimited vs N devices) is also unmodeled; at $4.20 probably not worth defending, but confirm in the licensing section.