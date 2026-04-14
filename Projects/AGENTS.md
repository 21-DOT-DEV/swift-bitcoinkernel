# AGENTS.md (Projects)

This directory contains Tuist-managed targets for additional validation (including XCFramework workflows).

## Generate the Xcode project

```bash
swift package --disable-sandbox tuist generate -p Projects/ --no-open
```

## Preferred: Tuist build/test (matches CI)

```bash
swift package --disable-sandbox tuist build Bitcoin -p Projects/ --platform ios
swift package --disable-sandbox tuist build BitcoinKernel -p Projects/ --platform ios
swift package --disable-sandbox tuist test Bitcoin-Workspace -p Projects/ --platform ios
```

## Fallback: xcodebuild test (macOS)

```bash
xcodebuild test -workspace Projects/Bitcoin.xcworkspace -scheme <TargetName> -destination 'platform=macOS'
```

## Notes

- Prefer updating `Projects/README.md` if the workflow changes.
