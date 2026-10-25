## Summary of Changes

- **Related Issue**: `#`
- **Target Host(s) / AI Client(s) Affected**:

## Stability & Safety Checklist

- [ ] Preserves working application behavior without unnecessary refactoring.
- [ ] All `.ps1` scripts under `scripts/` remain strictly 7-bit ASCII (`< 128`) and declare `#Requires -Version 5.1`.
- [ ] No raw `2>&1` outside `Invoke-ArchMcpNativeCommand`.
- [ ] `python3 tests/run_all_tests.py` (`14/14`) and `dotnet test ArchMCP.Hub.sln -c Release` (`17/17`) passed.
- [ ] Contains no API keys, tokens, passwords, or private local paths.
