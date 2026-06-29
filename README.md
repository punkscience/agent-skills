# agent-skills

A small collection of [Agent Skills](https://github.com/anthropics/skills) for
automating software distribution. Each skill is a self-contained folder with a
`SKILL.md` (YAML frontmatter + instructions) and its own `templates/` and
`scripts/`. They follow the cross-agent `SKILL.md` standard and work with Claude
Code, Codex, Cursor, Gemini CLI, and other SKILL.md-compatible agents.

## Skills

| Skill | What it does |
|-------|--------------|
| [`apt-setup`](apt-setup/) | Take a repo end-to-end for **APT (Debian/Ubuntu)** distribution — produce signed `.deb` packages, publish a GPG-signed APT repository on GitHub Pages, and a one-line `curl \| bash` installer, with full automated verification against the live repo. |
| [`choco-setup`](choco-setup/) | Take a repo end-to-end for **Chocolatey (Windows)** distribution — ensure a Windows build/release pipeline, produce versioned zip artifacts with checksums, generate the Chocolatey package + publisher workflow, with local pack/install verification. |

## Layout

```
<skill>/
  SKILL.md      # skill definition (frontmatter: name, description)
  templates/    # files the skill copies into target repos
  scripts/      # helper scripts the skill runs
```

## Using a skill

Copy a skill folder into your agent's skills directory (for Claude Code that's
`~/.claude/skills/` or `~/.agents/skills/`), then invoke it by name. The skill's
`SKILL.md` describes its phases; it drives the setup and verifies the result
before reporting success.

## License

Each skill ships its own license. The setup skills default new target projects to
the [Unlicense](https://unlicense.org/) when no license is present, but that is a
default the skill applies to *your* project — see each `SKILL.md`.
