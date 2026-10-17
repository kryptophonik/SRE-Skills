# Security policy

## Reporting

Please report vulnerabilities privately through GitHub's "Report a vulnerability" (Security Advisories) on this repository. Don't open a public issue. Expect an acknowledgement within 7 days.

## Scope

- **Skill text that could lead an agent to change production without explicit approval.** This is a gate bypass, and we treat it as a vulnerability.
- **Scripts:** anything that writes, leaks credentials, or runs without an explicit target.
- **Generated packaging:** anything that auto-approves tools, starts MCP servers, or enables hooks without the user opting in.

## Design rules

- No secrets in the repo. Credentials come from the user's environment (`PD_API_KEY`, `DD_API_KEY`, and so on) and are never echoed.
- No `.mcp.json` and no auto-enabled hooks. Recommended MCP servers are read-only and version-pinned (see `sre-safety-gates/references/mcp.md`).
- Skills don't set `allowed-tools`, so the host tool's approval prompts stay in force.
