# Contributing

1. **Edit only `.claude/skills/<name>/`** (and the top-level docs). The `skills/` mirror, `.claude-plugin/`, `gemini-extension.json`, `GEMINI.md`, `AGENTS.md`, `.github/copilot-instructions.md` and `.cursor/rules/` are generated. After editing, run `python3 scripts/build-targets.py` and commit the output.
2. **Skill rules:**
   - One level deep, with no nested skills. `name` equals the folder name and starts with `sre-`.
   - `description` is ≤250 characters and leads with the trigger.
   - Every skill contains the standard `## Safety gates (REQUIRED)` block.
   - Don't add `allowed-tools`.
   - Use `disable-model-invocation: true` for anything that injects faults or changes production.
3. **Generic content only:** use the placeholder vocabulary in [SKILLS.md](SKILLS.md). Never include real tenants, hosts, IDs, keys or people.
4. **Scripts:**
   - Read-only, with an explicit target flag and capped output (`MAX_PAGES`, `--limit`, `head`).
   - bash 3.2-compatible: no `mapfile`, and guard empty arrays.
   - Must pass `shellcheck -S warning`.
5. **Citations:** every tool command, API field or MCP tool name should link to its official docs. Write `Last reviewed: YYYY-MM-DD` on volatile reference pages.
6. **Before opening a PR,** run:
   ```bash
   python3 scripts/build-targets.py --check
   python3 scripts/validate.py
   claude plugin validate .            # if the Claude Code CLI is installed
   ```
7. Add a CHANGELOG entry under "Unreleased".
