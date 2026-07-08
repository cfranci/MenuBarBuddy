# Brand and Copy (Armada stitched output, 2026-07-08)

> Reconciliation note: the custom-icons feature is a verified dead no-op (see pre-launch-review.md). Strip every custom-icon claim from this copy before publishing; customization claims are scoped to the classic green dot and Rainbow Dot only. The landing page already reflects this.

# MenuBarBuddy - Brand & Copy

> Voice rules (apply to every surface below): benefit first, mechanism second. Name the specific behavior, never "simple and intuitive." Land the $4.20 joke exactly once per surface, then drop it. No superlatives ("best," "ultimate," "most powerful"). No em dashes anywhere. Write the name as one word, camelCase: **MenuBarBuddy** (never "Menu Bar Buddy" or "menubarbuddy") in all prose.

---

## Name check: keep MenuBarBuddy

**Keep it.** It is the right name and there is no reason to churn it.

- It says exactly what the app is. A stranger reads "MenuBarBuddy" and knows it lives in the menu bar and it is on their side.
- It is already load-bearing: the repo, the bundle ID (com.menubarbuddy.v6), the settings domain, and the running app on disk are all built on it. Renaming means re-signing, migrating defaults, and burning the discoverability the public GitHub repo already has.
- The friendly, unpretentious tone pairs coherently with a $4.20 price. A serious-sounding name at a joke price reads as a mismatch; a friendly name at a friendly price is coherent.

---

## Tagline

**Primary:** Your menu bar, tidied for $4.20.

The price rides along as a natural coda, confident and warm, not a punchline afterthought.

**Alternates (same voice):**
- Hide the clutter. Keep the calm.
- One dot. Zero clutter.
- One click and the mess is gone.

---

## Headlines (3 options + pick)

**Option A (recommended for the hero):**
> **Your menu bar was hiding 12 icons. Now it hides itself.**
> Subhead: MenuBarBuddy tucks away the icons you don't need and brings them back the instant you do. $4.20, once. No subscription, ever.

**Option B (calm variant, best for ads / social):**
> **A clean menu bar is one click away.**
> Subhead: One dot to collapse the clutter, one hotkey to bring it back. $4.20 one time.

**Option C (features-section headline, not the hero):**
> **The menu bar cleaner that survives macOS Tahoe.**
> Subhead: Hardened for macOS 26 with a self-healing watchdog most paid apps still don't have.

**PICK: Option A for the hero.** It names the pain viscerally, delivers the solution as a punchline, and implies the product's cleverness in one breath. Use a modest, believable number (12) rather than an inflated one so it reads as observation, not marketing. Use Option B on ad surfaces where the reader has less context, and Option C as the headline over the Tahoe/hardening section. The price lives in the subhead, where it reassures rather than reads as a gag.

---

## Benefit-first feature bullets

Lead with the outcome in bold, name the mechanism second.

- **One click to a clean menu bar.** Click the dot and everything left of the separator slides out of sight. Click again and it all comes right back, exactly where it was.
- **Bring it all back without touching the trackpad.** A global hotkey, Ctrl + Opt + Space, collapses and expands from anywhere, mid-task, even inside full-screen apps.
- **You decide what stays and what hides.** Cmd-drag the separator to set the line. Anything to its left tucks away; anything to its right stays visible, always.
- **Make it yours.** Pick any emoji or symbol for the toggle and the separator, from a quick-pick grid or the full macOS Character Viewer.
- **Rainbow Dot.** Flip it on and the toggle drifts through the color wheel in a soft two-tone wave, vivid when expanded and muted when collapsed. It is the best-looking pixel in your menu bar. Or keep it a classic solid dot.
- **Set it and forget it.** Turn on Start at Login (standard SMAppService, no Terminal, no config files) and MenuBarBuddy is quietly ready every time you sit down.
- **Built to survive macOS 26 Tahoe.** A background watchdog watches its own status items and repairs itself if the system knocks them loose, so it keeps working through the exact OS changes that broke other hiders.
- **Featherweight and private.** Native Swift, no menu bar takeover, no account, no telemetry, no network. It hides icons and gets out of your way.

---

## Pricing framing

**The frame:** MenuBarBuddy is not the cheap option. It is the honest one. It does one job well and charges you once for it. $4.20 is the honest middle: about a fifth of Bartender's price with no ownership drama, and more supported than the free tools when the OS shifts underneath them.

**Pricing card headline:**
> **$4.20, one time. All updates included. No subscription, not now, not later.**

**Comparison table:**

|                        | MenuBarBuddy   | Bartender 5   | Ice / Hidden Bar |
|------------------------|----------------|---------------|------------------|
| Price                  | $4.20 once     | ~$20 once     | Free             |
| macOS 26 Tahoe         | Hardened       | Partial       | Partial          |
| Self-repair watchdog   | Yes            | No            | No               |
| Rainbow Dot            | Yes            | No            | No               |
| Custom icons           | Yes            | Limited       | No               |
| Trust transparency     | Public source  | Ownership change, 2024 | Open source |

**Supporting copy:**
> Bartender is a good app that costs around twenty dollars and got tangled in an ownership change nobody asked for. The free hiders are genuinely good until an OS update breaks them and nobody is around to fix it. MenuBarBuddy does the part you actually use, click-to-hide, for the price of a coffee, and it is hardened for the exact Tahoe changes that broke the others.

**One-liners for tight spaces:**
- Cheaper than Bartender. More supported than free. $4.20, once.
- Free is a hobby. $4.20 is a hobby that gets supported.

---

## Why $4.20?

> **Q: Why $4.20?**
> Because a good menu bar cleaner should cost less than lunch, and we could not resist the number. It is a real price for a real app, we just happen to like the way it looks on the button. If it makes you smile, that is a feature. If it does not, it is still the cheapest full-featured menu bar hider you will find, so everybody wins. Pay it once and you are done forever.

The joke works because it is dry and confident: it states the number, admits the wink in one clause, then pivots straight back to the honest value. It never spells out the reference or elbows you in the ribs, which is what would make it cringe.

---

## FAQ copy

**Is there a free trial?**
The full source is public on GitHub, so you can build it, run it, and live with it for as long as you like before you decide it is worth $4.20. When there is a paid build to buy, buying it supports the work that keeps it working. (Note: a packaged trial and license flow are planned, not yet shipped.)

**What is your refund policy?**
If MenuBarBuddy does not do what you hoped, email us within 30 days and we will refund you, no interrogation. It is $4.20. We are not going to make it weird.

**Is it on the Mac App Store?**
Not right now. A direct download lets us hold the exact $4.20 price (Apple's price tiers do not include it) and ship Tahoe fixes without waiting in a review queue. If the App Store becomes the better option for buyers, we will revisit it.

**How do updates work, and do they cost extra?**
Every update is included, forever, for the one-time price. Today updates are a quick re-download of the latest build from the site (an in-app updater is on the roadmap). No upgrade fees, no "MenuBarBuddy 2" that makes you pay again.

**Does it work on macOS 26 Tahoe?**
Yes, and this is where MenuBarBuddy earns its keep. Tahoe changed how the menu bar works in ways that broke several hiders (one change makes a status item throw an exception past a certain width, and the failure gets swallowed silently mid-toggle). MenuBarBuddy shields that exception, verifies its own collapse, and ships a watchdog that repairs its status items if the system knocks them loose, without a relaunch. It runs on macOS 14 and later.

**Which icons actually get hidden?**
You draw the line. Cmd-drag the separator anywhere in your menu bar. Everything to the left of it hides when you collapse; everything to the right stays visible. Move the line whenever your setup changes.

**Is it open source? Can I just build it myself?**
Yes, and you are welcome to. The source is public at github.com/cfranci/MenuBarBuddy, so you can read every line before you trust it in your menu bar: no telemetry, no network calls, nothing hidden. A few minutes with Xcode gets you a running build. Paying $4.20 buys the finished, ready-to-run build and the ongoing work to keep it alive through every macOS release. You are paying for the finished product, not for permission to see the code.

**Does it need scary permissions or slow down my Mac?**
No special permissions. It uses only the standard macOS status-item APIs, no Accessibility grant, no screen recording, no network. The only system hook is the optional Start at Login toggle (SMAppService). It runs a couple of lightweight background checks and, if Rainbow Dot is on, animates the dot; footprint you will not notice in normal use.

**Which Macs does it run on?**
Apple Silicon Macs (M-series), macOS 14 or later, including macOS 26 Tahoe.

---

## App-Store-style description

**Subtitle:** Hide the clutter. One click.

**Full description:**
> Your menu bar fills up fast. Dropbox, dictation, Wi-Fi, input switchers, that one app you forgot you installed. MenuBarBuddy clears the clutter with a single click and brings it all back the moment you need it.
>
> Two items live in your menu bar: a dot you click, and a separator that marks the line. Click the dot and everything to the left of the separator slides out of sight. Click again, or press Ctrl + Opt + Space from anywhere, and your full menu bar is back exactly as you left it. Cmd-drag the separator to decide where the line goes; anything past it stays visible.
>
> Make it yours. Choose any emoji or symbol for the dot and separator from a quick-pick grid or the full Character Viewer. Turn on Rainbow Dot for a soft two-tone glow that drifts through the color wheel. Flip on Start at Login and MenuBarBuddy is quietly ready every time you open your Mac.
>
> Built native in Swift, MenuBarBuddy is featherweight and private: no account, no telemetry, no network. It is hardened for macOS 26 Tahoe and includes a self-healing watchdog that keeps its icons working through the exact system changes that broke other menu bar tools.
>
> One-time price. All updates included. No subscription, ever.
>
> Requires macOS 14 or later on Apple Silicon.

**Keyword list (SEO / ASO, comma-friendly):**
menu bar, menu bar manager, menu bar cleaner, hide menu bar icons, menu bar organizer, menu bar hider, macOS menu bar, mac menu bar, declutter menu bar, clean menu bar, bartender alternative, ice alternative, hidden bar alternative, vanilla alternative, menu bar icons, hide status icons, status bar cleaner, notch menu bar, macbook menu bar, macos 14, macos 15, macos 26, macOS Tahoe menu bar, menu bar hotkey, keyboard shortcut, global shortcut, rainbow dot, custom icon, emoji icon, start at login, mac productivity, minimal mac, one time purchase mac app

---

## OG / meta

**Meta description (~155 chars):**
> Clean up your Mac menu bar with one click. MenuBarBuddy hides the clutter and brings it back instantly. $4.20 once, no subscription. macOS 14+ and Tahoe-ready.

**og:title:** MenuBarBuddy: a clean menu bar for $4.20
**og:description:** One click hides the clutter, one hotkey brings it back. Custom icons, a rainbow dot, and a Tahoe-proof watchdog. $4.20 once, no subscription.
**twitter:description:** Hide menu bar clutter with one click. $4.20 one-time. Hardened for macOS 26 Tahoe. No subscription, no drama.

---

## Launch blurbs (tweet-length)

**Blurb 1 (benefit-led):**
> Your menu bar is a mess. MenuBarBuddy fixes it in one click, hides what you don't need, brings it back with a hotkey. Custom icons, a rainbow dot, and it's hardened for macOS Tahoe. $4.20 once. No subscription, ever. [link]

**Blurb 2 (positioning):**
> Bartender is ~$20 and had an ownership change nobody asked for. The free hiders break on Tahoe. MenuBarBuddy is $4.20 one time, self-heals on macOS 26, and does the one thing you actually want: click a dot, the clutter's gone. [link]

**Blurb 3 (developer credibility, for HN / r/macapps):**
> macOS 26 broke most menu-bar hiders: a status item throws an NSException past a width cap and the failure gets swallowed silently mid-toggle. MenuBarBuddy shields the exception, verifies its own collapse, and runs a watchdog that self-repairs. Open source. $4.20. github.com/cfranci/MenuBarBuddy

**Product Hunt tagline:**
> The $4.20 menu bar hider that actually works on macOS 26 Tahoe.
> Runner-up: One dot. All your menu bar clutter, gone. $4.20, not $20.

---

## Channel notes

- **Landing page:** hero (Option A) + demo/animation + pricing card & table + FAQ. Emotional hook, visual proof, rational close.
- **Mac App Store (if launched):** feature-dense, keyword-rich, state macOS version support clearly.
- **Twitter / X:** mix casual and technical; use $4.20 as a conversation starter, then drop it.
- **Reddit (r/macapps, r/macos):** lead with "I built this tiny menu bar hider," lean on open source + the Tahoe technical story.
- **GitHub README:** same tone as the app, direct and no fluff; note the license funds active maintenance.
- When showing the collapse animation: "Watch it collapse in real time, and notice the icons you kept stay put."

## Open questions
- Trial/license/nag mechanics are written as forward-looking intent because none exist in the code yet (pre-commercialization). Confirm the intended model before publishing the trial and updates FAQ answers as current behavior.
- Updates are currently a manual re-download; the copy promises an in-app updater 'on the roadmap.' If you do not intend to add Sparkle or a self-updater, soften that line to avoid an unmet promise.
- Binary is arm64-only today. Copy says 'Apple Silicon, macOS 14+.' If you plan to ship a universal build for Intel, update the requirements line before launch; if not, leave as-is (do not let any surface claim Intel support).
- Distribution uses ad-hoc codesign, not Apple notarization, so no surface claims 'notarized.' If you notarize before launch, you can add that as a trust bullet on the pricing/FAQ surfaces.
- Bartender's price is written as '~$20' and its 2024 event as an 'ownership change' rather than a 'trust scandal / supply-chain incident,' which is the safer, less-datable framing. Verify current Bartender pricing and preferred wording before going live.
- The hero headline uses a hard-coded '12 icons.' If you can detect the visitor's real menu-bar item count client-side, using the true number would make it hit harder; otherwise keep 12 as a believable default.