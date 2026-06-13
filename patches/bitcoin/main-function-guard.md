# Bitcoin Core Upstream PR: `MAIN_FUNCTION` Guard

Prepared draft for contributing an `#ifndef MAIN_FUNCTION` guard to Bitcoin Core's `src/compat/compat.h`.

## PR Title

```
compat: allow overriding MAIN_FUNCTION macro via build system
```

## PR Description

```markdown
Add an `#ifndef MAIN_FUNCTION` guard around the `MAIN_FUNCTION` macro definition
in `src/compat/compat.h`, allowing it to be overridden via compiler flags (e.g.
`-DMAIN_FUNCTION="int entry(int argc, char* argv[])"`).

**Motivation:**

Projects embedding Bitcoin Core as a library need to avoid duplicate `main()`
symbols when the host application or test harness provides its own entry point.
Currently, the only way to achieve this is to maintain a patched copy of
`compat.h` or post-process `bitcoind.cpp` with `sed`.

The `MAIN_FUNCTION` macro was designed to abstract the entry point signature
(originally for Windows `__declspec(dllexport)` support). Adding a standard
`#ifndef` guard makes it overridable via `-D` compiler flags — a common C
pattern for configurable defaults — without changing any existing behavior.

This aligns with Bitcoin Core's ongoing library extraction efforts
(libbitcoinkernel, #24303) by making it easier for external projects to
integrate Bitcoin Core components.

**Change:**

```diff
+#ifndef MAIN_FUNCTION
 #ifdef WIN32
 #define MAIN_FUNCTION __declspec(dllexport) int main(int argc, char* argv[])
 #else
 #define MAIN_FUNCTION int main(int argc, char* argv[])
 #endif
+#endif
```

**Impact:**

- Zero behavior change for existing builds (the guard is only active when
  `MAIN_FUNCTION` is pre-defined)
- No test changes required
- Does not affect consensus code
```

## Commit Message

```
compat: allow overriding MAIN_FUNCTION macro via build system

Add an #ifndef guard around the MAIN_FUNCTION definition in
src/compat/compat.h, allowing projects that embed Bitcoin Core as a
library to override the entry point signature via -D compiler flags.

This is useful when the host application or test runner provides its
own main(), which would otherwise conflict with the MAIN_FUNCTION
expansion. The guard follows standard C practice for overridable macro
defaults and does not change behavior for existing builds.
```

## File Changed

**`src/compat/compat.h`** — 2 lines added (`#ifndef MAIN_FUNCTION` + `#endif`)

### Diff (against v26.0)

```diff
diff --git a/src/compat/compat.h b/src/compat/compat.h
--- a/src/compat/compat.h
+++ b/src/compat/compat.h
@@ -83,11 +83,13 @@ typedef char* sockopt_arg_type;
 #endif
 
+#ifndef MAIN_FUNCTION
 #ifdef WIN32
 // Export main() and ensure working ASLR when using mingw-w64.
 // Exporting a symbol will prevent the linker from stripping
 // the .reloc section from the binary, which is a requirement
 // for ASLR. While release builds are not affected, anyone
 // building with a binutils < 2.36 is subject to this ld bug.
 #define MAIN_FUNCTION __declspec(dllexport) int main(int argc, char* argv[])
 #else
 #define MAIN_FUNCTION int main(int argc, char* argv[])
 #endif
+#endif
```

> **Note:** This diff is against `v26.0`. The actual PR branch must be rebased
> onto `master` before opening. The current `master` version of `compat.h` has
> diverged slightly (e.g. dropped `HAVE_CONFIG_H` include, added `sa_family_t`
> typedef), but the `MAIN_FUNCTION` section is unchanged.

## Bitcoin Core PR Process Checklist

Per [CONTRIBUTING.md](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md):

- [ ] Fork `bitcoin/bitcoin` and create a branch from `master`
- [ ] Rebase the change onto current `master` (not `v26.0`)
- [ ] Verify the diff applies cleanly to current `master`'s `compat.h`
- [ ] Run the existing test suite: `ctest --test-dir build` (no new tests needed — no behavior change)
- [ ] PR title uses area prefix: `compat:` (matches file location `src/compat/`)
- [ ] Commit message follows project conventions (imperative mood, no `@` mentions)
- [ ] No `@` mentions in PR description (use follow-up comments for pings)
- [ ] Consider pinging reviewers who last touched this code (use `git blame src/compat/compat.h`)

## Context & Prior Art

### How `MAIN_FUNCTION` works today

- Defined in `src/compat/compat.h` (since PR #18702, April 2020)
- Used in: `bitcoind.cpp`, `bitcoin-cli.cpp`, `bitcoin-tx.cpp`, `bitcoin-util.cpp`, `bitcoin-wallet.cpp`
- Original purpose: Windows ASLR fix — `__declspec(dllexport)` on `main()` prevents `.reloc` section stripping by mingw-w64 ld
- Non-Windows: expands to plain `int main(int argc, char* argv[])`

### Related PRs

| PR | Title | Relevance |
|---|---|---|
| [#18702](https://github.com/bitcoin/bitcoin/pull/18702) | `build: fix ASLR for bitcoin-cli on Windows` | Introduced `MAIN_FUNCTION` macro in `compat.h` |
| [#24303](https://github.com/bitcoin/bitcoin/issues/24303) | `The libbitcoinkernel Project` | Ongoing effort to extract consensus engine as a library — aligns with making Bitcoin Core more embeddable |

### Why `#ifndef` guard (not other approaches)

| Approach | Verdict |
|---|---|
| `__attribute__((weak))` on `main()` | Doesn't work — weak `main()` gets overridden by host's strong `main()`, causing infinite recursion when the library tries to call its own entry point |
| `-Dmain=entry` compiler flag | Dangerous — replaces ALL standalone `main` tokens in all source files |
| `#ifndef MAIN_FUNCTION` guard | Standard C pattern, zero risk, zero behavior change for existing builds |

*Issue states: see [patches/README.md](../README.md#cited-upstream-issues) (verified 2026-06-13).*
