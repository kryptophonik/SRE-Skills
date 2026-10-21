# Upgrading

Plugin and extension installs (Claude Code plugin, Gemini CLI extension) update in place: run the tool's update command from its install page. The steps below are for copy installs, where you copied the skill folders into a skills folder yourself.

## From 3.0.x to 3.1.0

3.1.0 removes two skills. Their content moved into `sre-engineer` (`references/architecture.md` and `references/tools-catalog.md`), so a copy install must delete the old folders, or the stale copies keep loading.

1. Find the skills folder you copied into. Common ones: `<your-repo>/.claude/skills`, `~/.claude/skills`, `<your-repo>/.agents/skills`, `~/.agents/skills`, `~/.cursor/skills`, `~/.copilot/skills`, `~/.grok/skills`.
2. Delete the two retired skills there. For example, for a personal Claude Code install:

```bash
rm -r ~/.claude/skills/sre-architect ~/.claude/skills/sre-tools-catalog
```

3. Pull the new release and copy the skills again, as on your tool's install page:

```bash
git -C claude-sre pull
mkdir -p ~/.claude/skills
cp -r claude-sre/.claude/skills/sre-* ~/.claude/skills/
```

4. Replace any `/sre-architect` or `/sre-tools-catalog` in your docs or aliases with `/sre-engineer`.
5. Check: `ls ~/.claude/skills | grep -c '^sre-'` prints 37, and neither retired name is listed.
