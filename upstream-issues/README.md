# Upstream Issues

Issues discovered in vendored upstream dependencies that are **not yet patched
locally**. Each entry documents:

1. What we observed.
2. Where in our code we encountered it.
3. The workaround we used.
4. A draft suitable for filing as an upstream issue or PR.

When an issue gets resolved upstream → delete the entry here.
When we apply a local patch instead → migrate the entry to [`patches/`](../patches/README.md).

## Bitcoin Core (`Vendor/bitcoin/`, `Sources/libbitcoinkernel/`)

| # | Issue | Status |
|---|---|---|
| 1 | [`btck_chainstate_manager_get_best_entry` can return null after `setWipeDBs(true, true)`, leading to undocumented SEGV in accessor functions](bitcoin/chainstate-get-best-entry-null-after-wipe.md) | Discovered + isolated + stack trace captured, not yet filed |
