---
name: wiki-bootstrap
disable-model-invocation: true
description: Bootstrap a personal knowledge base wiki with the three-layer architecture (raw sources, wiki, schema). Sets up directory structure, seeds AGENTS.md conventions, index.md, and log.md.
---

# Wiki Bootstrap

Set up a personal knowledge base wiki from scratch. The wiki follows a three-layer
architecture where an LLM agent incrementally builds and maintains a structured,
interlinked collection of markdown files between you and your raw sources.

The skill creates the directory structure, seeds the control files (index, log),
and writes the schema that governs the wiki — the conventions the agent follows
for every future operation.

## Phase 1 — Choose the wiki root

1. Ask the user where to create the wiki. Default: `~/wiki/`. Let them override.
2. Ask what domain this wiki covers (research topic, personal knowledge, book
   study, competitive analysis, etc.). Tailor the schema template with domain-
   specific suggestions for entity categories and concept groupings.
3. Ask whether they use Obsidian (or another markdown editor), and whether to
   configure for Obsidian-specific features (wiki links `[[…]]`, Dataview
   frontmatter, attachment folder path).

**Completion criterion**: the wiki root path, domain, and Obsidian preference are
confirmed and recorded.

## Phase 2 — Create directory structure

Create these directories under the wiki root:

```
<root>/
  raw/          → immutable source documents
  wiki/
    sources/    → source summary pages (created on first ingest)
    entities/   → people, organizations, products, places
    concepts/   → ideas, frameworks, theories
    comparisons/→ side-by-side analysis pages
    queries/    → filed answers to user questions
```

Create every directory now — the subdirectories under `wiki/` will be populated
as sources arrive, but the directory structure itself should exist from the
start.

If Obsidian is configured and images will be downloaded, also create
`raw/assets/` for local image storage.

**Completion criterion**: all directories exist on disk.

## Phase 3 — Write the schema (AGENTS.md)

Copy `templates/AGENTS.md` → `<root>/AGENTS.md`, replacing placeholders:

- `__WIKI_ROOT__` → the full path chosen in Phase 1
- `__DOMAIN__` → the domain description
- If Obsidian was selected in Phase 1: remove the `<!-- OBSIDIAN_CONVENTIONS_START`
  and `OBSIDIAN_CONVENTIONS_END -->` comment markers around the Obsidian
  conventions block, leaving the content intact.
- If not using Obsidian: delete the entire block between (and including) the
  `<!-- OBSIDIAN_CONVENTIONS_START` and `OBSIDIAN_CONVENTIONS_END -->` markers.

Tailor the entity and concept category suggestions to the domain if the user
provided one; otherwise leave the generic categories.

Do not generate extra pages yet — only the schema file.

**Completion criterion**: AGENTS.md exists at `<root>/AGENTS.md` with all
placeholders replaced.

## Phase 4 — Seed index.md and log.md

Copy `templates/index.md` → `<root>/wiki/index.md`.
Copy `templates/log.md` → `<root>/wiki/log.md`.

Leave the sample content intact — the first ingest will populate them.

**Completion criterion**: both files exist with the template content.

## Phase 5 — Report

Print a summary:

- Wiki root path
- Directory structure created
- Schema file location
- Next step: "Drop a source into `raw/` and invoke `wiki-ingest` to process it."