# Security Policy

## Supported Versions

| Version | Supported | Notes |
| :--- | :--- | :--- |
| **`1.0.0`** | Yes | First Official Public Release |
| `< 1.0.0` | No | Pre-release private builds |

## Built-In Security Safeguards

1. **Local-First & Zero Telemetry**: Runs 100% locally on Windows without cloud accounts or telemetry.
2. **User-Level Execution (`requiresElevation: false`)**: Installs into `%LOCALAPPDATA%` and `%APPDATA%` without requiring Administrator elevation.
3. **Loopback-Only Bindings (`127.0.0.1`)**: All local HTTP/TCP bridges (`:48884`, `:1999`, `:9877`, `:8765`, `:9876`) bind strictly to `127.0.0.1`.
4. **Safe Mode Defaults**: Enables `safe_mode = true` for 3ds Max, scopes AutoCAD `ALLOWED_PATHS` to `Documents\AutoCAD` with `DANGEROUS_COMMANDS_ENABLED=false`, and uses the hardened no-`eval_ruby` SketchUp extension.
5. **Timestamped Backups & Auto-Rollback**: Creates `.backup-YYYYMMDD-HHMMSS` before modifying any file and restores automatically on error.

## Reporting a Vulnerability & Protecting Secrets

Do not post exploitable vulnerabilities or private API keys/tokens (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, etc.) in public GitHub issues. Use GitHub Private Vulnerability Reporting if enabled or contact the repository owner (**Mohamed Abd El-Hafez**).
