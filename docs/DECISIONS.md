# Architecture Decision Log

## ADR-001: WPF desktop app
Chosen for Windows-native integration and mature desktop support.

## ADR-002: .NET 10 LTS
Chosen as the current LTS baseline as of October 2026. Re-check Microsoft's lifecycle before each release. Official policy: https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core

## ADR-003: Hybrid portable
The Hub can be published self-contained, but host-native plugins may still require installation into app/user directories. Portability is not claimed for third-party host plugins.

## ADR-004: Hybrid MCP topology
The Hub manages and configures per-host integrations; agents connect directly to the relevant integration server where supported. The Hub is not a mandatory data proxy.

## ADR-005: Latest stable compatible
Release freshness is subordinate to compatibility, integrity, and verified test evidence.

## ADR-006: Integration registry is declarative
Registry data cannot contain arbitrary executable shell commands. Use typed install operations and explicit allow-lists.

## ADR-007: Compatibility status is evidence-based
Version range claims alone are not enough for Verified status. Exact host-version tests are required.

## ADR-008: Test strategy
Use both automated CI/unit tests and real host-application tests. See TEST-PLAN.md.
