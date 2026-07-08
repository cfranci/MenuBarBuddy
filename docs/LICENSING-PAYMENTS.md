# Licensing and Payments (Armada stitched output, 2026-07-08)

# MenuBarBuddy — Licensing & Payments

Grounded in the real app: an AppKit `NSApplicationDelegate` menu-bar agent (`LSUIElement`), macOS 14+ / Tahoe-hardened, SwiftPM with one third-party dep (`HotKey`) plus a local `ExceptionShield` target, installed via `install.sh` (release build + **ad-hoc** codesign). Current bundle ID is `com.menubarbuddy.v6` and the app **bumps its own bundle ID and re-signs on self-repair** (`performSelfRepair`, v4→v5→v6→…). The licensing layer must (a) never block the menu bar from appearing at login, (b) survive those bundle-ID bumps the same way `rainbowDot` and `startAtLogin` already do, and (c) not disturb the fragile status-item / watchdog machinery.

---

## 1. Payment provider: Lemon Squeezy (firm pick)

Only option that satisfies all three hard requirements at once for a solo dev selling a $4.20 utility: exact free-form price, true merchant of record, first-class license-key API.

| Requirement | Lemon Squeezy | Gumroad | Paddle | Stripe Payment Links |
|---|---|---|---|---|
| Exact **$4.20** price | Yes, free-form | Yes | Low-price floor reported* | Yes |
| **Merchant of Record** (they file VAT/GST/US sales tax) | **Yes** | Yes | Yes | **No — you owe global VAT** |
| **License-key API** (activate/validate/deactivate) | **Yes, first-class** | Weak/absent | Add-on, heavier | **None — build it yourself** |
| Effective take on $4.20 | ~5% + $0.50 ≈ $0.71* | ~10% flat* | ~5% + $0.50* | 2.9% + $0.30, no MoR/keys |

*\*Verify current terms at launch — provider pricing/minimums change; confirm the LS fee, Gumroad's exact-price support, and Paddle's low-price handling against live docs. Directionally right, not gospel.*

**Why the others lose:** Stripe Payment Links is a processor, not a merchant of record, so you personally owe EU/UK VAT + US state sales tax on cross-border sales and get **no license system**. Gumroad is a fine MoR fallback but its take is ~double LS's and its license API is thin — keep it as a switchable fallback. Paddle leans enterprise, needs manual business review, and is awkward at very low prices.

**Net ≈ $3.49/sale** (assuming ~5% + $0.50) — the price of never touching a VAT return.

**Provider config:** product at **$4.20** one-time; License Keys on with **activation limit = 3** (home/laptop/work), **no expiry**; post-purchase page + receipt email carry the key **and** link to the **GitHub Release DMG** (§6). Keep the **LS API key** and **Ed25519 private key** out of the public repo.

---

## 2. License architecture: offline-first, Ed25519-signed

The app launches at login and must be usable instantly, often with no network. So:

```
Buy on LS -> user gets an LS LICENSE KEY (used once)
   -> paste into "Enter License…" (reuses the Settings window pattern)
   -> app POSTs key to a $0 Cloudflare Worker, which activates it against LS
      server-side and returns a fresh Ed25519-SIGNED, self-contained TOKEN
   -> token stored as a UserDefaults key (rides the bundle-ID migration chain)
   -> app verifies it LOCALLY on every launch with the embedded PUBLIC key.
      NEVER needs the network again.
```

**Two-token design:** the LS key proves purchase and claims a seat, used once. The **signed token** is what the app trusts day-to-day, verified offline.

**Private key never in the app.** It lives ONLY as a Cloudflare Worker secret (~40-line free-tier function). The app holds only the **public** verify key (safe to commit). This is the opposite of embedding the private key in the bundle — doing that would let anyone mint unlimited licenses.

**Token format:** `MBB1-<base32url(payload)>.<base32url(signature)>` where payload is compact JSON `{ v, kid, sku, email, order, iss, seats }`. The `kid` (key id) lets you **rotate the signing key in a future app version without invalidating old tokens**. Signature is Ed25519 over the **raw base32-decoded payload bytes** — not `JSONEncoder().encode(...)`, whose key ordering isn't byte-stable across sign/verify. Verified with CryptoKit `Curve25519.Signing`.

**Storage: UserDefaults key on the migration chain — NOT Keychain.** This is the single most important correction. The app self-repairs by **bumping its bundle ID and re-signing ad-hoc**; Keychain items for an ad-hoc identity that changes, with no keychain-access-group entitlement, are not guaranteed to survive — a watchdog-triggered v6→v7 self-repair could silently strand a paying customer. The app's own settings dodge this by living in UserDefaults and being copied forward by `SettingsStore.migrateFromOldBundleID`, which already carries `rainbowDot` and `startAtLogin` across domains via `CFPreferencesCopyAppValue`. So:

- Persist the token as `MenuBarBuddy.licenseToken` in `UserDefaults.standard`.
- **Add that key to the hardcoded array in `migrateFromOldBundleID`** (currently lists `selectedEmoji`, `startEmoji`, `pushMultiplier`, `startAtLogin`, `rainbowDot`). One line — the whole `previousBundleIDs` machinery then carries the license across every self-repair for free.

Because the token is Ed25519-signed, UserDefaults storage is safe: tampering breaks the signature. (A bare `status=active` string in any store could be forged; a signed token cannot — this is why signing matters.) The trial clock keys ride the same chain so a reinstall into the same lineage doesn't reset the trial.

---

## 3. Trial policy: 14 days, degrade — never brick

- **14 days fully functional** (Rainbow Dot and custom icons included).
- **Quiet until the last 3 days.** From day 12, one subtle menu item: `Buy MenuBarBuddy — 2 days left ($4.20)`. Entire nag budget.
- **On expiry: degrade, don't disable.** Core **hide/show/collapse keeps working forever.** What gates after trial (mapped to the app's *actual* menu items): **Rainbow Dot** (reverts to classic dot), **Choose Icons…** picker (reverts to `📁`/`☰`), **Start at Login**. Never sabotages the menu bar mid-workday.
- **Trial clock** = first-run timestamp + max-elapsed-days-seen, both in UserDefaults and on the migration chain. **Soft clock-rollback guard:** if the wall clock ever appears earlier than the recorded max-elapsed, trust the stored max. Lightweight, not bulletproof — correct for $4.20.

---

## 4. Anti-abuse stance (deliberately light)

Source is public on GitHub; DRM is pointless. Enforcement surface = **verify the signature + cap at 3 seats server-side (LS activation limit)**. No obfuscation, no debugger checks, no per-launch phone-home, no online re-validation. A **"Deactivate this Mac"** action calls LS `/deactivate` then clears the token so users self-serve transfers. **Fail OPEN, never closed:** if a token is present but the public key fails to load (build bug), assume **licensed**, not trial — mirrors the app's "the UI never lies" ethos. No hardware fingerprinting (brittle, resented; the 3-seat cap suffices). The price is the anti-piracy strategy: cracking costs a compile, buying costs one paste.

---

## 5. Swift implementation

### `LicenseManager.swift` (ObservableObject, no new deps — CryptoKit + Combine are system)

```swift
import Foundation
import CryptoKit
import Combine

enum LicenseState: Equatable { case licensed(email: String); case trial(daysLeft: Int); case expired }

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    private static let publicKeyB64 = "REPLACE_WITH_BASE64_PUBLIC_KEY"          // safe to commit
    private static let activateURL = URL(string: "https://license.menubarbuddy.app/activate")!
    private let trialDays = 14
    // ALL added to SettingsStore.migrateFromOldBundleID:
    private let tokenKey = "MenuBarBuddy.licenseToken"
    private let firstRunKey = "MenuBarBuddy.trialFirstRun"
    private let maxDaysKey = "MenuBarBuddy.trialMaxDays"
    @Published private(set) var state: LicenseState = .expired
    private let defaults = UserDefaults.standard
    private init() { refresh() }

    func refresh() {                                  // pure-local; never blocks the menu bar
        if let t = defaults.string(forKey: tokenKey), let c = verify(token: t) {
            state = .licensed(email: c.email); return
        }
        if let t = defaults.string(forKey: tokenKey), publicKeyMissing(), !t.isEmpty {
            state = .licensed(email: ""); return       // FAIL OPEN on build fault
        }
        state = trialState()
    }
    var isLicensed: Bool { if case .licensed = state { return true }; return false }
    var isUsable: Bool { if case .expired = state { return false }; return true }   // gates premium

    func activate(key: String) async -> Result<Void, LicenseError> {
        var req = URLRequest(url: Self.activateURL); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["license_key": key, "instance": deviceName()])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return .failure(.serverRejected) }
            let token = (try? JSONDecoder().decode([String:String].self, from: data))?["token"] ?? ""
            guard verify(token: token) != nil else { return .failure(.badToken) }
            defaults.set(token, forKey: tokenKey); await MainActor.run { self.refresh() }
            return .success(())
        } catch { return .failure(.network) }
    }
    func deactivate() async {                          // frees a seat, clears local token
        var req = URLRequest(url: Self.activateURL.appendingPathComponent("deactivate")); req.httpMethod = "POST"
        req.httpBody = defaults.string(forKey: tokenKey)?.data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
        defaults.removeObject(forKey: tokenKey); await MainActor.run { self.refresh() }
    }

    struct Claim: Codable { let v: Int; let kid: String; let sku: String
                            let email: String; let order: String; let iss: Int }
    private func publicKeyMissing() -> Bool { Data(base64Encoded: Self.publicKeyB64) == nil }
    private func verify(token: String) -> Claim? {
        guard token.hasPrefix("MBB1-") else { return nil }
        let p = token.dropFirst(5).split(separator: ".")
        guard p.count == 2,
              let payload = Base32.decode(String(p[0])),         // raw bytes we signed
              let sig = Base32.decode(String(p[1])),
              let pk = Data(base64Encoded: Self.publicKeyB64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pk),
              pub.isValidSignature(sig, for: payload),           // verify over exact bytes
              let c = try? JSONDecoder().decode(Claim.self, from: payload), c.sku == "menubarbuddy"
        else { return nil }
        return c
    }
    private func trialState() -> LicenseState {
        if defaults.object(forKey: firstRunKey) == nil { defaults.set(Date(), forKey: firstRunKey) }
        let first = defaults.object(forKey: firstRunKey) as? Date ?? Date()
        let elapsed = max(0, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0)
        let seen = max(elapsed, defaults.integer(forKey: maxDaysKey))   // rollback guard
        defaults.set(seen, forKey: maxDaysKey)
        let left = trialDays - seen
        return left > 0 ? .trial(daysLeft: left) : .expired
    }
    private func deviceName() -> String { Host.current().localizedName ?? "Mac" }
    enum LicenseError: Error { case network, serverRejected, badToken }
}
```

`Base32` is a ~30-line Crockford codec. **`SettingsStore.migrateFromOldBundleID` must add `MenuBarBuddy.licenseToken`, `.trialFirstRun`, `.trialMaxDays`** to its key array so they ride `previousBundleIDs`.

### `LicenseSheet.swift` — reuse the existing Settings window

Do NOT hand-roll a new NSPanel/activation-policy dance. `openSettings()` (AppDelegate lines 858–908) already has a working `.accessory`-restoring window flow. Add `@objc openLicense()` that clones that exact block into a `licenseWindow` ivar: `NSHostingView(rootView: LicenseSheet(...))` → titled `NSWindow` → `setActivationPolicy(.regular)` → restore `.accessory` on `willCloseNotification`. The SwiftUI sheet is an `@ObservedObject var mgr = LicenseManager.shared` with a monospaced key `TextField`, a status banner reflecting `.licensed`/`.trial`/`.expired`, a "Buy for $4.20" button, an "Activate" default-action button, and a "Deactivate this Mac" affordance when licensed.

### Menu integration in `setupContextMenu()`

Insert **before the Quit separator** (currently line 590). Drive from `LicenseManager.shared.state`; subscribe once via Combine so the item rebuilds when activation flips state. When licensed: a disabled "Licensed to <email>" item. In trial: "Enter License…", plus a "Buy … N days left ($4.20)" item only when `daysLeft <= 3`. When expired: "Buy MenuBarBuddy ($4.20)" + "Enter License…". Handlers: `openBuy()` opens the LS checkout URL; `openLicense()` clones the settings-window flow.

**Premium gating** is one guard the existing feature actions consult:

```swift
@objc private func toggleRainbowDot() {
    guard LicenseManager.shared.isUsable else { openBuy(); return }   // trial OR licensed
    rainbowEnabled.toggle(); /* existing logic */
}
```

Same guard on Choose Icons… and Start at Login.

---

## 6. Delivery: notarized DMG on GitHub Releases

**The #1 pre-ship blocker.** `install.sh` uses **ad-hoc** codesign (`codesign --force -s -`) — a paying customer hits Gatekeeper's "cannot verify the developer" wall and bounces. For sale you need a real **Developer ID Application** cert (**Apple Developer Program, $99/yr**) + hardened runtime + notarization + stapling. (The **self-repair path keeps re-signing ad-hoc** — that's fine, it's a local recovery, not the shipped artifact.) Adapt `install.sh` into a `release.sh`:

```bash
swift build -c release
codesign --force --options runtime --timestamp \
  -s "Developer ID Application: <Your Name> (TEAMID)" MenuBarBuddy.app
create-dmg --volname "MenuBarBuddy" --app-drop-link 380 120 \
  --icon "MenuBarBuddy.app" 120 120 "MenuBarBuddy-1.0.0.dmg" MenuBarBuddy.app
xcrun notarytool submit MenuBarBuddy-1.0.0.dmg --keychain-profile "MBB-NOTARY" --wait
xcrun stapler staple MenuBarBuddy-1.0.0.dmg
gh release create v1.0.0 MenuBarBuddy-1.0.0.dmg --title "MenuBarBuddy 1.0.0" --notes "First paid release."
```

**One artifact, one URL, verified two ways** (Apple notarization + Sparkle EdDSA): DMG on the GitHub Release; LS post-purchase page + receipt link to it; Sparkle enclosure points at the same URL. Public source means gating the download buys nothing.

---

## 7. Sparkle auto-update (appcast on GitHub Pages)

Add **Sparkle 2** as a second SwiftPM dep. `Sparkle/bin/generate_keys` → public EdDSA key into `Info.plist` (`SUPublicEDKey`), private key off-repo; `SUFeedURL` → `https://cfranci.github.io/MenuBarBuddy/appcast.xml`. Wire once with the **real** initializer (not any `startUpdater(true)`):

```swift
import Sparkle
private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
// "Check for Updates…" -> updater.checkForUpdates(nil)
```

Each release: `Sparkle/bin/sign_update MenuBarBuddy-1.0.0.dmg`, paste the resulting **`sparkle:edSignature`** + byte length into a new top `<item>` whose `enclosure url` is the GitHub Release DMG. Sparkle 2 **refuses unsigned enclosures**, so `edSignature` is mandatory. `appcast.xml` served free from `docs/` via GitHub Pages.

---

## 8. Secrets checklist (public repo)

- **Safe to commit:** Ed25519 license **public** key, Sparkle **public** EdDSA key, `SUFeedURL`, all Swift source.
- **NEVER commit:** Ed25519 license **private** key (Worker secret only), Sparkle **private** EdDSA key, LS **API key**, notarization creds, Developer ID `.p12`.

---

## 9. Launch checklist

1. Apple Developer Program ($99/yr) → Developer ID cert.
2. LS product at $4.20, License Keys on, 3 activations, no expiry; confirm live fee/terms.
3. Cloudflare Worker: activate-against-LS + Ed25519 sign + `/deactivate` route; LS API key and Ed25519 private key as Worker secrets.
4. Sparkle keys; public key → Info.plist; add Sparkle dep.
5. Add `LicenseManager.swift` + `LicenseSheet.swift`; embed Ed25519 **public** key.
6. **Add `MenuBarBuddy.licenseToken`, `.trialFirstRun`, `.trialMaxDays` to `SettingsStore.migrateFromOldBundleID`'s key array.**
7. `openLicense()` cloned from `openSettings()`; license items before the Quit separator; gate Rainbow Dot / Choose Icons / Start at Login on `isUsable`.
8. `release.sh`: Developer ID codesign + DMG + notarize + staple.
9. GitHub Release v1.0.0 with DMG; GitHub Pages `appcast.xml` with `edSignature`.
10. LS post-purchase page + email link to the Release DMG.
11. Smoke test: buy test key → activate → confirm token in UserDefaults → **force a self-repair (`--force-repair`) and confirm the license survives** → confirm Sparkle finds an update.

## Summary

Lemon Squeezy sells at exactly **$4.20** as merchant of record, issues keys, and links to a **notarized DMG on GitHub Releases** (replacing the ad-hoc signing, the #1 blocker). Keys activate once against a **$0 Cloudflare Worker** returning an **Ed25519-signed, offline-verifiable token** stored as a **UserDefaults key that rides the app's existing bundle-ID migration chain** (the crucial fix: Keychain would silently die on self-repair). Trial is **14 days that degrades, never bricks**, gating only Rainbow Dot / custom icons / Start-at-Login. Anti-abuse is light (3 server-side seats, fail-open, self-serve transfer). Sparkle keeps everyone current via an EdDSA-signed appcast. Two SwiftPM deps added alongside the existing HotKey/ExceptionShield, zero disturbance to the Tahoe watchdog.