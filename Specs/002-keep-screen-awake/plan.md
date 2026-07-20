# Plan — Keep Screen Awake toggle

| | |
|---|---|
| **Feature** | A "Keep Screen Awake" switch in both example apps (`NodeApp` and `KernelApp`) that stops the device auto-locking while the app is on-screen. On iPhone/iPad it disables the auto-lock idle timer; on Mac it prevents the display from idle-sleeping. Off by default. Demo-app polish, **not a library roadmap phase** (the roadmap tracks the `Bitcoin`/`BitcoinKernel` library; see [`.specify/memory/roadmap.md`](../../.specify/memory/roadmap.md)). Second Spec (global counter 002). |
| **Status** | **IN PROGRESS — code complete on branch `DISABLE-LOCK-OPTION` (staged, not committed); flips to Implemented at merge.** All decisions applied: Mac front-only via `appearsActive`; switch in a Display group; keep-awake wired at each **root view** (`ContentView`/`RootView`), not the App scene, for reliable updates. Shared helper, both apps' wiring, and the unit test are written. Validated: shared helper type-checks on iOS + macOS SDKs; `tuist generate` clean; **NodeApp macOS build + both unit tests pass**; **KernelApp builds clean on iOS** (its edits also compiled in a macOS run — a `bitcoind` module error there was a cross-scheme DerivedData artifact, not a real dependency: KernelApp uses BitcoinKernel). Remaining: on-device manual auto-lock checks (yours, on a hand-launched build), then commit. Four review rounds resolved (§9). |
| **Decisions** (planning) | **D1 — All three platforms.** iPhone/iPad use `UIApplication.shared.isIdleTimerDisabled`; Mac uses `ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason:)` (Apple's high-level Foundation API — no IOKit, no entitlements). Researched: on iPhone/iPad preventing auto-lock also keeps the app alive (a locked phone suspends it and stalls sync); on Mac the app runs regardless, so the benefit is a visible, un-locked dashboard during long syncs. **D2 — Off by default.** Opt-in, per Apple's "only disable the idle timer when genuinely needed" guidance and to protect battery. |
| **Assumptions** (in force) | **A1 — Shared mechanism, per-app switch, immediate.** One shared piece in `Projects/Sources/Shared/` (a `@MainActor` `ScreenWakeController` + a `.keepScreenAwake(_:)` SwiftUI view modifier) that both apps apply at their root view; each app owns its own switch bound to its own saved setting. Takes effect **immediately**, not staged behind KernelApp's pending-changes/apply flow — it is a device preference (like KernelApp's existing `loggingEnabled`), not a kernel-restart setting. **A2 — Front window only.** Active only while the app is the active/front window; released automatically otherwise. On iPhone/iPad a backgrounded app cannot hold the screen awake anyway; on Mac the sync runs regardless of display sleep, so holding it from the background is wasted energy Apple's guidance steers away from. Focus is read per platform: iPhone/iPad use `scenePhase == .active`; **Mac uses `@Environment(\.appearsActive)`** (macOS 15+), because `scenePhase` does not report focus loss on Mac. **A3 — Naming/placement.** Label "Keep Screen Awake" with a one-line battery note; placed in each app's existing settings screen (NodeApp `ConfigurationView`, KernelApp `SettingsView`). Saved under each app's own `UserDefaults` key, following that app's convention: NodeApp `keep_screen_awake` (unprefixed, like its other keys); KernelApp `kernel_keep_screen_awake` (the `kernel_` prefix all its keys use). The apps use separate per-app `.standard` domains, so the two keys are independent — the prefix is convention-consistency and future-proofing (a shared App Group), not a live collision. **A4 —** Spec at `Specs/002-keep-screen-awake/plan.md` only. **A5 —** Verified with `tuist generate` + build on both platforms and a unit test of the controller's on/off decision (in the existing `Projects/Sources/SharedTests/`). |

## 1. Goal & success criteria

- Both apps show a "Keep Screen Awake" switch, off by default.
- Switch on + app on-screen: iPhone/iPad do not auto-lock; the Mac display does not idle-sleep.
- Switch off, or app backgrounded: normal auto-lock / display-sleep resumes, with no lingering hold.
- No new permissions or entitlements. Builds clean on iOS and macOS, both apps.

## 2. Scope

**In scope:** one shared controller + view modifier in `Projects/Sources/Shared/`; a switch in each app's settings screen bound to a saved setting; applying the modifier at each app's root.

**Out of scope (follow-ups):** an "only while charging" battery-aware mode; preventing full *system* sleep on Mac (we prevent display sleep only); any change to background execution or background modes.

## 3. Design

### 3.1 Shared mechanism (`Projects/Sources/Shared/KeepScreenAwake.swift`, new)

`ScreenWakeController` — a `@MainActor` reference type with `update(enabled:isActive:)`. Let `shouldKeepAwake = enabled && isActive`. The controller is **idempotent**: repeated calls in the same state are no-ops, so nothing leaks when `update` fires more than once while staying on (the modifier calls it on every scene-phase change, flag change, and on appear).

- iPhone/iPad (`#if canImport(UIKit)`): `UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake`. Setting a `Bool` to the same value repeatedly is inherently idempotent — no guard needed.
- Mac (`#elseif os(macOS)`): guard on a stored token so **exactly one** activity is ever held. Begin only when none is held; end only when one is:

  ```swift
  private var token: (any NSObjectProtocol)?
  // inside update():
  if shouldKeepAwake {
      if token == nil {
          token = ProcessInfo.processInfo.beginActivity(
              options: .idleDisplaySleepDisabled, reason: "Keep Screen Awake")
      }
  } else if let held = token {
      ProcessInfo.processInfo.endActivity(held)
      token = nil
  }
  ```
  This keeps `beginActivity`/`endActivity` balanced one-to-one, per Apple's contract (hold the returned token; call `endActivity` exactly once). Without the `token == nil` guard, repeated on-calls would leak wake-locks.

A `.keepScreenAwake(_ enabled: Bool)` `ViewModifier` holds the controller in `@State` and reads the front-window signal per platform: `@Environment(\.scenePhase)` on iPhone/iPad (`isActive = scenePhase == .active`), `@Environment(\.appearsActive)` on Mac (`isActive = appearsActive`; `scenePhase` does not report Mac focus loss). It calls `update(enabled:isActive:)` on appear, on change of the flag, and on change of that signal, and releases on disappear.

Testable seam: the platform effect is injected as `begin`/`end` closures that default to the real `ProcessInfo`/`UIApplication` calls, so a unit test asserts (a) awake only when `enabled && isActive`, and (b) `begin` fires once across repeated on-calls and `end` once on the off-transition — proving no token leak without touching real system APIs.

### 3.2 NodeApp wiring (raw `@AppStorage`, matches its existing switches)

- `Projects/Sources/NodeApp/ConfigurationView.swift`: `@AppStorage("keep_screen_awake") private var keepScreenAwake = false` + a new dedicated **Display** `Section` at the bottom of the form holding `Toggle("Keep Screen Awake", isOn: $keepScreenAwake)` with a battery-note footer.
- `Projects/Sources/NodeApp/ContentView.swift` (the root view): declare `@AppStorage("keep_screen_awake") private var keepScreenAwake = false` and apply `.keepScreenAwake(keepScreenAwake)` to the body. Reading the value in the **root view** (not the `App` scene) guarantees a reactive update when `ConfigurationView` toggles the same key: same-key `@AppStorage` auto-syncs, and `@AppStorage` in the `App` scene body is a documented reactivity weak spot. `NodeApp.swift` stays unchanged.

### 3.3 KernelApp wiring (its `@Observable` settings model)

- `Projects/Sources/KernelApp/Settings/KernelAppSettings.swift`: add `var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) } }`, `Key.keepScreenAwake = "kernel_keep_screen_awake"` (matching the `kernel_` prefix on all 14 existing keys, lines 310–323), hydrated to `false` in `init`. Mirrors the existing `loggingEnabled` (immediate write-through, not a pending/apply change).
- `Projects/Sources/KernelApp/Views/SettingsView.swift`: a new dedicated **Display** `Section` at the bottom holding `Toggle("Keep Screen Awake", isOn: $settings.keepScreenAwake)` + footer.
- `Projects/Sources/KernelApp/Views/RootView.swift` (the root view): apply `.keepScreenAwake(settings.keepScreenAwake)` to the body, reading `settings.keepScreenAwake` there (reliably reactive in a `View`, unlike the `App` scene). `KernelApp.swift` stays unchanged.

## 4. Implementation steps

1. Add `Projects/Sources/Shared/KeepScreenAwake.swift` (controller + view modifier).
2. NodeApp: switch in `ConfigurationView`; apply the modifier in `NodeApp.swift`.
3. KernelApp: property + key in `KernelAppSettings`; switch in `SettingsView`; apply the modifier in `KernelApp.swift`.
4. Add a unit test of `update(enabled:isActive:)` in `Projects/Sources/SharedTests/`: awake only when both true, and — via the injected effect — `begin` fires once across repeated on-calls and `end` once on the off-transition (no token leak).
5. `swift package --disable-sandbox tuist generate -p Projects/ --no-open`, then build both apps (iOS simulator + macOS); confirm no warnings.

## 5. Verification

- [x] Builds clean on iOS + macOS, both apps. (NodeApp built for macOS, KernelApp built for iOS; shared helper type-checks against both SDKs.)
- [x] Unit test: awake only when both true; repeated on-calls hold exactly one activity (`begin` once, `end` once) — no token leak. (Both pass on macOS.)
- [ ] Manual iPhone/iPad **on a hand-launched build, not via the Xcode debugger** (the debugger auto-disables the idle timer and would mask a regression): switch on + leave idle → no auto-lock; switch off → auto-locks.
- [ ] Manual Mac: switch on → display does not idle-sleep; off → normal.
- [ ] Background the app with the switch on → the hold is released.

## 6. Risks and mitigations

- The Xcode debugger auto-disables the iOS idle timer, so a debugger run always "passes." → The manual iOS check must be a hand-launched build on a device.
- A lingering hold (screen never re-locks / display never sleeps) if not released. → Release on background/inactive and when the switch turns off; the Mac activity token is ended and cleared.
- `UIApplication.shared` must be touched on the main actor. → The controller is `@MainActor`.

## 7. Out of scope (follow-ups)

- "Only while charging" battery-aware mode (as the Insomnia library offers).
- Preventing full system sleep on Mac (we intentionally prevent display sleep only).

## 8. Division of labor

- **Agent:** all of it — shared code, both apps' wiring, the unit test, and the build check. No GUI or human step required.

## 9. Review resolutions

**Round 1.**
- Assumption count: Status corrected to "5 assumptions in force (A1–A5)."
- KernelApp key prefix: uses `kernel_keep_screen_awake`, matching the `kernel_` prefix on all 14 `KernelAppSettings.Key` entries (`KernelAppSettings.swift:310–323`); NodeApp keeps unprefixed `keep_screen_awake`. Production uses per-app `.standard` domains (no shared App Group — the `UserDefaults(suiteName:)` uses are test-only), so this is convention-consistency and future-proofing, not a live collision.
- macOS token leak: §3.1 spells out the one-token idempotency guard (`begin` only when none held, `end` only when one is), balanced per Apple's `beginActivity`/`endActivity` contract; iOS `isIdleTimerDisabled` is a `Bool` and inherently idempotent; the injected effect makes begin-once/end-once testable.

**Round 2 (staged-plan review).** Six findings. Three were already resolved in Round 1 — the review ran against the pre-Round-1 staged blob and did not see those fixes — and three were new and are now fixed.

- Already resolved in Round 1, no action: F1 (assumption count), F5 (KernelApp key prefix), F6 (injected testable seam).
- **F2 (paths) FIXED.** Every demo-app/shared path now carries the `Projects/` prefix (`Projects/Sources/Shared/…`, `Projects/Sources/NodeApp/…`, `Projects/Sources/KernelApp/…`, `Projects/Sources/SharedTests/`). The repo has both a root SPM `Sources/` (the `Bitcoin` library) and the demo-app `Projects/Sources/`; files created at the root paths would land outside the app targets and not build.
- **F3 (update call) FIXED.** The modifier now calls `update(enabled: enabled, isActive: scenePhase == .active)`; the prior `update(enabled:isActive: …)` supplied only `isActive` and was invalid Swift.
- **F4 (NodeApp declaration) FIXED.** `Projects/Sources/NodeApp/NodeApp.swift` now declares its own `@AppStorage("keep_screen_awake")`; same-key `@AppStorage` auto-syncs with `ConfigurationView`'s, so the app-level modifier reads a valid, in-sync value.

**Round 3 (pre-implementation ritual).** Two decisions refined the plan before coding:
- **Mac holds only while the front window** (not the whole time it runs): the Mac sync continues regardless of display sleep, so background-holding is wasted energy per Apple's guidance. Focus is detected via `appearsActive` (macOS 15+), not `scenePhase` (which does not report Mac focus loss) — see A2 and §3.1.
- **Switch placed in a dedicated "Display" group** at the bottom of each settings screen (§3.2, §3.3).

**Round 4 (implementation review).** Nine files, staged — one BUG, one INFO, two unverified.
- **[BUG] README status mismatch — FIXED.** The index row said `Planned` while the plan said `Implemented`; per the "Implemented at merge" convention (this branch is unmerged), both now read `In Progress`, and the README documents the three states.
- **[unverified → real] App-scene `@AppStorage` reactivity — FIXED.** The keep-awake modifier now reads its value in each **root view** (`ContentView`, `RootView`) instead of the `App` scene, so toggling the switch updates it live. Research confirms `@AppStorage` in the `App` scene body is a documented weak spot (§3.2, §3.3).
- **[INFO] Settings MARK — FIXED.** `keepScreenAwake` moved out from under `// MARK: - Logging` into its own `// MARK: - Display` in `KernelAppSettings`.
- **[unverified] Copyright header — already resolved.** The working-tree `2026-present` fix is already staged; the reviewer saw a stale snapshot.
