# Macstral — Monetization Plan

> Goal: take Macstral from free MIT app → revenue-generating product.
> Model: **Freemium**, **$30 one-time Pro unlock**, via **Lemon Squeezy** (merchant of record).
> Author: planning doc for @izyuumi · Status: DRAFT, pre-implementation.

---

## 0. Why Macstral

Chosen over every other personal repo because it is the closest to revenue in a
*proven-paid* category:

- **Proven market.** Superwhisper (sub ~$8.49/mo), MacWhisper (one-time ~$30–60),
  Wispr Flow (sub ~$12/mo) all make real money doing exactly this.
- **Real moat.** Fully on-device (Voxtral MLX) — "no audio ever uploaded" beats every
  cloud competitor on the one axis buyers care about (privacy).
- **Distribution already solved.** `release.yml` already does Developer ID signing +
  `notarytool` notarization + `stapler` + auto-updates the Homebrew cask. Paid users
  will NOT hit a Gatekeeper "unidentified developer" wall. This is the expensive part,
  and it's done.
- **Mature.** v0.3.0 shipped, CI green, test suite, release-please, clean roadmap.

What's missing is purely the **money plumbing** — there is currently **zero**
licensing/payment code in the repo.

---

## 1. Pricing & Paywall

### Tiers

| Tier | Price | Includes |
|------|-------|----------|
| **Free** | $0 | Core hold-to-dictate, Auto-detect / English only, **Fast** model, paste-last-transcription |
| **Pro** | **$30 one-time** | Everything in Free **plus** the gated features below |

### Pro-gated features (all already built or in 0.4.0 roadmap)

| Feature | Source today | Gate point |
|---------|--------------|-----------|
| Multi-language (JA, FR, DE, ES, IT, PT, ZH) | `TranscriptionLanguage` enum (`Settings/LanguageSettings.swift`) | Picker allows only `.auto` / `.en` when free; others show 🔒 + upsell |
| Transcript history + search + export | `Models/TranscriptHistory.swift`, `UI/HistoryWindow.swift` | History window shows upsell overlay when free |
| Balanced / Accurate models | `ModelQuality` enum (`Settings/ModelQualitySettings.swift`) | Only `.fast` selectable when free |
| Auto-punctuation / smart formatting | NEW (roadmap 0.4.0 P1) | Post-processor only runs when Pro |

**Rationale:** the free tier is genuinely useful (real dictation, English, local) so
the funnel is wide; Pro = the power features that distinguish Macstral from a weekend
toy. Each gated feature already exists, so gating is wiring, not building.

### Why one-time, not subscription
Privacy/local-first buyers actively resist subscriptions ("I run it on my own machine,
why rent it?"). One-time $30 matches MacWhisper's mental model and removes churn /
recurring-billing infra. Future major versions (1.0, 2.0) can be **paid upgrades** if
recurring revenue is later desired.

---

## 2. Licensing (legal)

**Blocker #1 — must happen before charging.** The repo is currently **MIT**. You cannot
meaningfully sell a binary whose source anyone may rebuild and redistribute for free.

### Action
1. Replace `LICENSE` (MIT) with a **proprietary EULA** (or source-available license such
   as Functional Source License / Business Source License if you want the source to stay
   public but forbid resale/redistribution and commercial competing use).
2. Add a `EULA.md` shown/linked in onboarding + Preferences → About.
3. Update `README.md` License section accordingly.

### Caveat (accept, don't fight)
Old git tags (≤ v0.3.0) remain MIT — someone *could* rebuild 0.3.0 for free. This is
acceptable: all **Pro features + auto-punctuation land in post-relicense versions**, and
for a $30 indie utility the activation friction is enough deterrence. Do **not** sink
time into anti-piracy beyond standard license-key validation.

---

## 3. Lemon Squeezy setup (manual, dashboard)

Done by @izyuumi in the Lemon Squeezy dashboard — produces the IDs the app needs.

1. Create a **Store**.
2. Create a **Product** "Macstral Pro", price **$30**, single payment.
3. Enable **License keys** on the product variant (Lemon Squeezy issues a key per order).
   - Activation limit: **3 instances** (lets a user activate on multiple Macs — generous,
     reduces support complaints; tune later).
   - License length: **no expiry** (one-time purchase).
4. Generate an **API key** (Settings → API) — used only for server-side / not embedded.
5. Record: `STORE_ID`, `PRODUCT_ID`, `VARIANT_ID`. These are non-secret and may live in
   a config file; the **API key is secret** and must NOT be committed.

### Endpoints used (no secret needed for these three — they take the license key itself)
- `POST https://api.lemonsqueezy.com/v1/licenses/activate`  — key + `instance_name`
- `POST https://api.lemonsqueezy.com/v1/licenses/validate`  — key + `instance_id`
- `POST https://api.lemonsqueezy.com/v1/licenses/deactivate` — key + `instance_id`

These are designed to be called **client-side** from the app; they do not require the
secret API key, so Macstral can validate licenses with no Macstral-run backend.

---

## 4. App implementation

> Follow t-wada TDD: write the failing test first, then implement. New code is Swift,
> matching existing style (`@Observable`, enums with `displayName`, `MARK:` sections).

### 4.1 `LicenseManager` (core)

New file: `Macstral/Licensing/LicenseManager.swift`
New tests: `MacstralTests/LicenseManagerTests.swift`

**Responsibilities**
- `var isPro: Bool` — single source of truth the UI observes (`@Observable`).
- `activate(key:) async throws` → calls `/activate`, on success stores
  `{ key, instanceId, lastValidated }` in **Keychain** (not UserDefaults — survives,
  not trivially editable).
- `validate() async` — called on launch + periodically; refreshes `lastValidated`.
- **Offline grace**: if last successful validation < **14 days** ago, remain Pro even
  when `/validate` is unreachable. Beyond grace with no network → drop to Free (warn,
  don't punish abruptly).
- `deactivate()` — frees an instance slot (for "Deactivate this Mac" button).

**Testability**
- Inject a `LicenseAPIClient` protocol (real impl = URLSession; tests = mock returning
  canned `activate`/`validate` JSON).
- Inject a `Clock`/date provider so offline-grace expiry is testable without sleeping.
- Inject a `LicenseStore` protocol over Keychain (tests use in-memory).

**Test cases (write first)**
1. activate success → `isPro == true`, credentials persisted.
2. activate with invalid key → throws, `isPro == false`, nothing stored.
3. validate success refreshes `lastValidated`.
4. validate network failure within grace → stays Pro.
5. validate network failure past 14-day grace → drops to Free.
6. cold start with stored valid creds → `isPro == true` before network returns.
7. deactivate → clears store, `isPro == false`.

### 4.2 Feature gating

Add a `FeatureGate` helper (or compute in `AppState`) reading `licenseManager.isPro`.

- **Language** (`PreferencesView` language picker): when free, disable rows other than
  `.auto` / `.en`; append 🔒 to their label; tapping a locked row opens the upsell sheet.
  Enforce in the code path that sends language to the backend so it can't be bypassed via
  stale UserDefaults (clamp to `.auto`/`.en` when `!isPro`).
- **Model quality** (`PreferencesView` model picker): same — clamp selectable to `.fast`
  when free; enforce at the point `ModelQuality.modelID` is requested.
- **History** (`HistoryWindow`): when free, render the list blurred/empty with an upsell
  overlay ("Transcript history is a Pro feature"). Don't persist history when free (avoid
  building a dataset the user can't access — or persist but gate access; decide: **gate
  access, keep persistence** so upgrading reveals back-history → nicer upgrade moment).
- **Auto-punctuation**: post-processor (4.4) is a no-op when free.

### 4.3 Licensing UI

- **Preferences → License tab** (extend `PreferencesView` / `PreferencesWindow`):
  - Free: "Macstral Free" badge, feature comparison, **Upgrade — $30** button → opens
    Lemon Squeezy checkout URL in browser, + "Already bought? Enter license key" field.
  - Pro: "Macstral Pro ✓", masked key, "Deactivate this Mac" button.
- **Upsell sheet** — reusable SwiftUI sheet shown when a free user hits a locked feature;
  lists Pro features + Upgrade button. One component, called from each gate point.
- **Post-checkout return**: Lemon Squeezy shows the key on the success page + emails it.
  Simplest reliable flow = user copies key → pastes into the License tab. (Optional later:
  register a `macstral://activate?key=...` URL scheme so the success page can deep-link.)

### 4.4 Auto-punctuation (Pro carrot + conversion booster)

Roadmap 0.4.0 Priority 1. Highest output-quality ROI; makes Pro visibly better.

- New `Macstral/Formatting/TranscriptFormatter.swift` + tests.
- Runs on the **final `done`** transcript (NOT during streaming — avoids cursor jumps).
- Phase 1 heuristics: capitalize first letter, ensure terminal punctuation, trim
  whitespace, collapse double spaces.
- Pure function → trivially unit-tested (table of input→expected).
- Gated: only applied when `isPro`.

---

## 5. Landing page + checkout

Reuse the existing `ship.yumi.to` scaffold (Next.js + Convex; already hosts `joblog`,
`hourproof`, `estatedraft` sub-pages).

- Add a `macstral/` page (or dedicated `macstral.app` domain if desired).
- Sections: hero ("Hold a key. Speak. Release."), privacy/on-device pitch, feature grid,
  language list, **Buy Pro — $30** (Lemon Squeezy checkout link/overlay), **Download free**
  (Homebrew cmd + Releases zip), FAQ.
- Keep the existing waitlist route as a fallback email capture.
- Lemon Squeezy provides hosted checkout + JS overlay (`lemon.js`) — no payment UI to build.

---

## 6. Distribution notes (already in place — verify, don't rebuild)

- `release.yml`: Developer ID sign → notarize → staple → zip → update Homebrew cask. ✅
- App Store is **ruled out** (bundled Python backend → Guideline 2.5.2 auto-reject;
  Accessibility text injection incompatible with sandbox). Direct distribution only —
  which is exactly why self-serve Lemon Squeezy licensing is the right call.

---

## 7. Milestones / sequencing

| # | Milestone | Output | Effort |
|---|-----------|--------|--------|
| M1 | Relicense | EULA replaces MIT, README updated | S |
| M2 | `LicenseManager` + tests (TDD) | Pro state engine, Keychain, offline grace | M |
| M3 | Feature gating | Language/model/history/auto-punct gated on `isPro` | M |
| M4 | Licensing UI | License tab + upsell sheet + checkout link | M |
| M5 | Auto-punctuation | `TranscriptFormatter` + tests, Pro-gated | S |
| M6 | Lemon Squeezy dashboard | Product, $30, license keys, IDs | S (manual) |
| M7 | Landing page | Macstral page on ship.yumi.to + buy button | S |
| M8 | Ship v0.4.0 | Tag → signed/notarized release → cask update | S |

**Critical path to first dollar:** M1 → M2 → M3 → M4 → M6 → M7. M5 ships alongside but
isn't strictly required to charge. Realistic: ~1–2 focused weekends.

---

## 8. Open decisions

- [ ] License: full proprietary EULA vs source-available (FSL/BSL)? (default: proprietary EULA)
- [ ] Activation instance limit: 3 Macs? (default: 3)
- [ ] History when free: gate-access-but-keep-persistence (recommended) vs don't-store?
- [ ] Domain: sub-page on ship.yumi.to vs dedicated macstral.app?
- [ ] URL-scheme deep-link activation now or later? (default: later, manual paste first)

---

## 9. Risks

- **Voxtral / voxmlx redistribution license** — ✅ RESOLVED (verified 2026-05-29). All
  Voxtral tiers (mlx-community 4bit/6bit/fp16) and the Mistral base models
  (`Voxtral-Mini-4B-Realtime-2602`, `Voxtral-Mini-3B-2507`) are **Apache-2.0**; voxmlx is
  **MIT** (© Awni Hannun). Commercial use + redistribution permitted. Required attribution
  (Apache-2.0 NOTICE for Voxtral, MIT notice for voxmlx) is bundled in
  `THIRD_PARTY_LICENSES.md` and linked from Preferences → License → About. GREEN to sell.
- **Bundled Python backend size/fragility** — already shipping, but large download; not a
  monetization blocker, just support surface.
- **Refund/support load** — one-time + merchant-of-record (LS handles tax + refunds)
  keeps this minimal.
