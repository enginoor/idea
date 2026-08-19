## 2026-08-17 - Unsafe Process Execution via Bare Command Names in Foundation Process

**Vulnerability:** External command execution via `Process.executableURL` passed unresolved command strings (e.g., `"c2patool"`) directly as `fileURLWithPath:`, causing Foundation to resolve paths relative to current working directory (`./c2patool`) instead of searching system `PATH`.
**Learning:** Passing a relative command name to `URL(fileURLWithPath:)` does not trigger system `PATH` resolution when initializing `Process`. It defaults to the process working directory, which poses a binary hijacking risk if untrusted files exist in the working directory and fails system PATH lookup.
**Prevention:** Always resolve command names against system `PATH` environment variable using an explicit path resolver before passing to `Process.executableURL`.
