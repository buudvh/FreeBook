# FreeBook - Project Rules

This document defines coding guidelines, runtime specifications, and constraints for developers and agentic models working on the **FreeBook** codebase.

## Codebase Guidelines & Swift Architecture

### 1. Persistence & SwiftData Queries
- **Constraint:** Avoid using SwiftData `#Predicate` filters on string properties (e.g., `!localPath.isEmpty`) in SwiftUI `@Query` declarations. SwiftData's SQLite query compiler has translation bugs that may fail to filter correctly.
- **Rule:** Query the complete list and filter in memory using a computed property:
  ```swift
  @Query private var allExtensions: [Extension]
  private var activeExtensions: [Extension] {
      allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
  }
  ```

### 2. Extension Registry & Installation URL
- The `Extension` model includes a `downloadUrl` property.
- When syncing repository files (`RepositoryManagerView.swift`), save the raw `path` from `plugin.json` directly into `downloadUrl` to ensure correct package downloads.
- Do not use hardcoded string replacements to generate zip URLs.

---

## JavaScript Core Runtime & VBook Extensions Integration

### 1. Script Entrypoint
- All JavaScript extensions are structured as isolated modules.
- **Rule:** The entry point function inside ALL script files (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) is named `execute(...)`. Always invoke `"execute"` via `runAsync` in `ExtensionManager.swift`.

### 2. Script File Path Resolution
- Scripts may be stored in the root folder of the extension package or inside a `src/` subdirectory.
- `ExtensionManager.swift`'s `getScriptPath` is configured to search both the root folder and the `src/` subfolder. Respect this fallback search sequence.

### 3. Injected Global JS Objects
The `JSExecutor` injects the following global namespaces/functions into the `JSContext`:
- `Html`: Dom parser bridge (`Html.parse(...)`).
- `console`: Redirects `console.log(...)` to Xcode print logs.
- `fetch`: Asynchronous Promise-based fetch API.
- `Response`: Global response helper namespace:
  - `Response.success(data)` returns the raw data directly.
  - `Response.error(message)` throws an Error.
- `Engine`: Simulates a synchronous headless browser:
  - `Engine.newBrowser()` returns a mocked `Browser` instance supporting `.launch(url, timeout)` (sync network request), `.html()`, and `.close()`.

### 4. Logging & Diagnostics
- **Environment Constraint:** The primary developer does not own a Mac. The application is built using GitHub Actions (CI) and installed on a physical iOS device inside **LiveContainer** to be run. Direct Xcode console attachment is unavailable.
- **Rule:** Write all runtime logs to a file named `app_logs.txt` inside the app's `Documents/` directory using the `AppLogger` utility. This allows logs to be read directly on the device or exported.
- Log all JS exception details including `desc`, `line`, `column`, and `stack` (JS Stacktrace) into both standard output and `app_logs.txt`.
- Keep detailed trace logs of inputs, JS outputs, and parser results in `ExtensionManager` actions to ensure traceability during debugging.
