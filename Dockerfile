FROM swift:6.3
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git pkg-config libsqlite3-dev
WORKDIR /workspace
COPY . .
ARG TRAITS=
# In-container clones are anonymous — the runner's git config can't reach
# here — so the bounds travel as env/CLI instead: git aborts a transfer that
# stays under ~1KB/s for 60s (the same stall-killer github-git-auth sets on
# the runner; a hung RUN otherwise had no bound at all), and the swift test
# lines carry --disable-dependency-cache to keep clones out of the shared
# SwiftPM cache (swiftlang/swift-package-manager#9037).
ENV GIT_HTTP_LOW_SPEED_LIMIT=1024 GIT_HTTP_LOW_SPEED_TIME=60
# Two invocations (see .github/AGENTS.md). The first runs the package in
# parallel: the `.kernelSerialized` trait serializes libbitcoinkernel's
# process-global state tests in-process, and the Esplora tests use an in-memory
# HTTP double, so `--no-parallel` is not needed. The one exit test
# (`#expect(processExitsWith:)`, the #35293 trap guard) gates itself off with
# `.enabled(if: env["RUN_EXIT_TESTS"])` and auto-skips here; run it on demand via
# `RUN_EXIT_TESTS=1 swift test --no-parallel`. The second isolates the
# embedded-bitcoind suite, which can't share the global logger with kernel
# LoggingConnection tests. The second RUN reuses the first's build.
RUN swift test --disable-dependency-cache --skip 'BitcoinTests\.BitcoinTests/' ${TRAITS:+--traits $TRAITS}
RUN swift test --disable-dependency-cache --filter 'BitcoinTests\.BitcoinTests/' ${TRAITS:+--traits $TRAITS}
