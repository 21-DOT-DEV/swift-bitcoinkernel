# Let the host app own `main()`

Bitcoin Core's executables declare their entry point through a macro, `MAIN_FUNCTION`, so Windows builds can decorate `main()` for a security fix (keeping address-space randomization working). When an app embeds the daemon, the app already has a `main()`, and two entry points collide at link time. This patch wraps the macro's definition in a standard `#ifndef` guard so a build system can predefine it — we predefine it to rename the daemon's entry point to `bitcoind_main()`, which Swift then calls like any function. Nothing changes for anyone who doesn't predefine the macro.

| | |
|---|---|
| **Status** | Applied here; not yet filed upstream. Applies cleanly to the vendored v31.0 tree (checked 2026-07-17); still unguarded on master (checked 2026-07-02). |
| **Touches** | `src/compat/compat.h` (the macro is consumed in `src/bitcoind.cpp` and the other executables) |
| **Depends on** | Nothing. |
| **File as** | Direct pull request — step 3 of [the pipeline](../UPSTREAMING.md#the-pipeline). Link the discussion thread as embedding context once it exists; the PR stands alone either way. No separate issue: this is a capability tweak, not a bug — a code-less feature issue invites design debate, and the restart thread is its context. |
| **PR title** | `compat: make MAIN_FUNCTION overridable` |
| **Cite** | [#18702](https://github.com/bitcoin/bitcoin/pull/18702) — origin of the macro (the Windows fix, first in `bitcoin-cli` only). [#25251](https://github.com/bitcoin/bitcoin/pull/25251) — consolidated it into `compat.h` for all executables. Cite this lineage precisely. |

## The change

```diff
diff --git a/src/compat/compat.h b/src/compat/compat.h
--- a/src/compat/compat.h
+++ b/src/compat/compat.h
@@ -87,6 +87,7 @@ typedef unsigned int SOCKET;
 typedef SSIZE_T ssize_t;
 #endif
 
+#ifndef MAIN_FUNCTION
 #ifdef WIN32
 // Export main() and ensure working ASLR when using mingw-w64.
 // Exporting a symbol will prevent the linker from stripping
@@ -97,6 +98,7 @@ typedef SSIZE_T ssize_t;
 #else
 #define MAIN_FUNCTION int main(int argc, char* argv[])
 #endif
+#endif
```

This is the `.patch` artifact verbatim; it matches the vendored v31.0 tree (`src/compat/compat.h:90-99`) and applies cleanly to it. The section is unchanged on master (checked 2026-07-02); rebase onto current `master` before opening the PR.

## Writing the PR

Must say:

- Two lines; zero behavior change unless a build system predefines the macro, which nothing upstream does.
- The precise lineage (#18702 → #25251) and the standard-C-practice framing: an `#ifndef` guard is the ordinary pattern for an overridable default.
- The embedding motivation in one sentence: a host application or test harness that provides its own `main()` currently has to patch this header.

Must not:

- Do not promise a first-class CMake option for the override. Mention it as a possible follow-up at most, and let maintainers decide.

## Notes — why not the alternatives

| Approach | Verdict |
|---|---|
| Mark `main()` weak (`__attribute__((weak))`) | Fails — the host's strong `main()` wins, and the library ends up calling the host's entry point recursively. |
| `-Dmain=entry` compiler flag | Dangerous — renames every standalone `main` token in every file. |
| `#ifndef MAIN_FUNCTION` guard | Standard C pattern; zero risk; zero change for existing builds. |
