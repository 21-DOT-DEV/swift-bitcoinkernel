import ProjectDescription

// Repo-root Tuist configuration. This file MUST live at the root, not under
// `Projects/`: Tuist's root locator treats `Tuist.swift` as a root marker (as
// are `Tuist/` and `.git`), so a copy inside `Projects/` would relocate the
// project root — and every root-relative lookup — there. Beside `.git` the
// root is unchanged.
//
// Its only job is `additionalPackageResolutionArguments` — the pass-through
// tuist/tuist#8099 provides for the `xcodebuild -resolvePackageDependencies`
// call `tuist generate` runs internally. That call is otherwise unreachable:
// no `tuist generate` flag and no workflow step can attach arguments to it.
//
// The args apply ONLY when `TUIST_CLONED_SOURCE_PACKAGES_DIR` is set — which
// the CI generate steps export (derived from the job's `DERIVED_DATA`).
// `TUIST_*` is the prefix Tuist's manifest evaluator forwards (`Environment`
// reads it through `Environment.clonedSourcePackagesDir`); an unprefixed
// variable never reaches this file's evaluation. A local `tuist generate`
// runs with it unset → no args → Xcode's default DerivedData, which a local
// `xcodebuild` / Xcode open shares — so developers pay no extra re-clone.
//
// With the variable set the internal resolve:
//   * `-scmProvider system` — runs on the Mac's git, the code path that
//     reads `~/.gitconfig`, where `github-git-auth` writes the CI
//     Authorization header (the built-in provider's config handling is
//     never relied on);
//   * `-clonedSourcePackagesDirPath` — writes clones into
//     `$DERIVED_DATA/SourcePackages`, the directory the builds'
//     `-derivedDataPath` already reads, so the workspace graph fetches once
//     inside the retried generate step instead of again at build time
//     (the default-DerivedData split: tuist/tuist#2712);
//   * `-disablePackageRepositoryCache` — keeps clones out of the shared
//     repository cache whose mid-fetch death is fatal
//     (swiftlang/swift-package-manager#9037) — the cache buys nothing on a
//     fresh runner.
//
// `.options()`'s other defaults equal the no-file defaults — verified by a
// byte-identical `project.pbxproj`/`contents.xcworkspacedata` diff of a
// generate run with and without this file (variable unset).
let pinnedSourcePackages = Environment.clonedSourcePackagesDir.getString(default: "")
let packageResolutionArguments: [String] = pinnedSourcePackages.isEmpty ? [] : [
    "-scmProvider", "system",
    "-clonedSourcePackagesDirPath", pinnedSourcePackages,
    "-disablePackageRepositoryCache",
]

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            additionalPackageResolutionArguments: packageResolutionArguments
        )
    )
)
