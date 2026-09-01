---
feature: 002
title: Keep Screen Awake toggle in both demo apps
phase: null
status: Implemented
updated: 2026-08-31
adrs: [0004]
---

# Keep Screen Awake toggle

A "Keep Screen Awake" switch in both example apps (`NodeApp` and `KernelApp`) that
stops the device auto-locking while the app is on screen. On iPhone and iPad it
disables the auto-lock idle timer; on Mac it prevents the display idle-sleeping.
Off by default. This is demo-app polish rather than a library roadmap phase; the
[roadmap](../../Roadmap/README.md) tracks the `Bitcoin` and `BitcoinKernel`
libraries. The API choice and the platform split behind it are recorded in
[ADR 0004](../../ADRs/0004-foundation-apis-for-keeping-the-screen-awake.md).

**Still open:** the three manual checks in §5 need a physical device and have not
been done — auto-lock on iPhone or iPad from a hand-launched build, display
idle-sleep on Mac, and release of the hold when the app goes to the background.
The code shipped; those three behaviours are unverified.
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

- `Projects/Sources/KernelApp/Settings/KernelAppSettings.swift`: add `var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) } }`, `Key.keepScreenAwake = "kernel_keep_screen_awake"` (matching the `kernel_` prefix used by every constant in that file's `Key` enum), hydrated to `false` in `init`. Mirrors the existing `loggingEnabled` (immediate write-through, not a pending/apply change).
- `Projects/Sources/KernelApp/Views/SettingsView.swift`: a new dedicated **Display** `Section` at the bottom holding `Toggle("Keep Screen Awake", isOn: $settings.keepScreenAwake)` + footer.
- `Projects/Sources/KernelApp/Views/RootView.swift` (the root view): apply `.keepScreenAwake(settings.keepScreenAwake)` to the body, reading `settings.keepScreenAwake` there (reliably reactive in a `View`, unlike the `App` scene). `KernelApp.swift` stays unchanged.

## 4. Implementation steps

1. Add `Projects/Sources/Shared/KeepScreenAwake.swift` (controller + view modifier).
2. NodeApp: switch in `ConfigurationView`; apply the modifier in `ContentView`, the root
   view. `NodeApp.swift` is not touched.
3. KernelApp: property + key in `KernelAppSettings`; switch in `SettingsView`; apply the
   modifier in `RootView`, the root view. `KernelApp.swift` is not touched.
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
