# AGENTS.md (.github)

This directory contains GitHub configuration and CI workflows.

## Workflow inventory

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `apple-builds.yml` | push/PR to `main` | macOS build+test (incl. wallet trait), iOS + visionOS cross-compile of the umbrella scheme, tvOS cross-compile of the BitcoinKernel scheme only, DocC validation for Bitcoin + BitcoinKernel |
| `docker-builds.yml` | push/PR to `main` | Linux build+test via `docker build .` |
| `docc-release.yml` | release published or manual | Matrix build of DocC archives (Bitcoin + BitcoinKernel), upload to release assets |

**Platform coverage**: macOS (build+test), iOS (build only), visionOS (build only), tvOS (BitcoinKernel only — `Bitcoin` depends on `bitcoind`'s `execvp()` call which is `__TVOS_PROHIBITED`). Linux via Docker. watchOS is blocked by additional POSIX prohibitions (`fork`, `execvp`, etc.) and not in the matrix.

## Boundaries (strict)

- Do not broaden GitHub Actions `permissions` without a clear justification.
- Do not print or log secrets/tokens.
- Do not add new third-party actions without asking.

## Workflow conventions

- **Least-privilege pattern for private repos**: set `permissions: {}` at the **workflow** level (deny-by-default baseline for any job that omits its own block) and grant the **minimum** each job needs at the job level. For `actions/checkout` against a private repo, that minimum is `contents: read`. A bare `permissions: {}` at the job level strips `contents: read` and causes `actions/checkout` to fail with a 404 "repository not found" error on private repos.
- Workflows use `env:` blocks for context values — no inline `${{ }}` interpolation in `run:` scripts.
- Avoid fragile shell output capture for UTF-8 / multiline content; prefer temp files and tools like `jq` reading from files.
- swift-bitcoinkernel gates dev plugins (`swift-plugin-tuist`, `swift-plugin-subtree`, `swift-docc-plugin`) behind `Context.gitInformation?.currentTag` — see `Package.Dependency.developmentDependencies` in `Package.swift`, which returns an empty array when the package is resolved at a tagged ref. Consumers of tagged releases don't download dev tooling. Workflows that need those plugins (e.g. `docc-release.yml` invoking `swift package generate-documentation`) currently check out at the release tag, which excludes the plugin; if DocC generation regresses at tag time, this is the likely cause and the workaround is to delete the local tag before running the plugin, or to pin the plugin outside `developmentDependencies`.

## Gotchas

- The private-repo `permissions: {}` failure mode (404 on checkout) only surfaces on GitHub runners, not locally. Always push a test branch to verify permission changes.
- `docc-release.yml` uses a matrix strategy (`[Bitcoin, BitcoinKernel]`) with a separate `release` job for artifact collection. Adding a new DocC target requires updating both the matrix list and the `release` job's download+upload steps.
- The umbrella scheme (`BitcoinKernel-Package`) builds both products. On tvOS it fails because the `Bitcoin` product transitively uses `execvp()`; the tvOS job uses the per-product `BitcoinKernel` scheme to skip `Bitcoin`. Do not switch the tvOS job back to the umbrella scheme without first guarding the `execvp()` call (or removing the dependency on it) in `Sources/bitcoind/src/util/exec.cpp`. watchOS is similarly blocked and would also need `fork`/`exec` guards in vendored C++ sources.

## Validation

- **macOS**: `swift test && swift test --traits wallet`
- **Linux**: `docker build .`
- **iOS cross-compile**: `xcrun xcodebuild -skipMacroValidation -skipPackagePluginValidation build -scheme "BitcoinKernel-Package" -destination generic/platform=iOS`
- **visionOS cross-compile**: same as iOS, substitute `generic/platform=visionOS`
- **tvOS cross-compile (BitcoinKernel only)**: same shape, but use `-scheme "BitcoinKernel"` and `generic/platform=tvOS`. The umbrella scheme fails on tvOS — see Gotchas.
- **DocC validation**: `swift package generate-documentation --target Bitcoin --analyze --warnings-as-errors` (repeat for `BitcoinKernel`)