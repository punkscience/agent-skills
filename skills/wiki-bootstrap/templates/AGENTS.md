# Wiki Schema — __DOMAIN__

This file is the schema for the personal knowledge base at `__WIKI_ROOT__`. It
encodes the conventions and constraints the agent follows during every wiki
operation — ingest, query, lint. The agent reads this first before any operation.

## Architecture

Three layers, each with a distinct owner:

```
__WIKI_ROOT__/
  raw/          → Immutable source documents. Read-only for the agent.
  wiki/         → LLM-maintained markdown pages. Agent writes; human reads.
  AGENTS.md    → This schema. Co-evolved by human and agent over time.
```

## Directory conventions

| Directory | Purpose | Owner |
|-----------|---------|-------|
| `raw/` | Source documents (articles, papers, transcripts, images) | Human |
| `wiki/sources/` | One summary page per ingested source | Agent |
| `wiki/entities/` | People, organizations, products, places | Agent |
| `wiki/concepts/` | Ideas, frameworks, theories, terminology | Agent |
| `wiki/comparisons/` | Side-by-side analyses of competing claims or ideas | Agent |
| `wiki/queries/` | Filed answers to user questions — research that compounds | Agent |
| `wiki/overview.md` | High-level synthesis — the entry point to the wiki | Agent |
| `wiki/index.md` | Content-oriented catalog of every wiki page | Agent |
| `wiki/log.md` | Append-only chronological record of operations | Agent |

## Page format

Every wiki page starts with YAML frontmatter:

```yaml
---
title: "Page Title"
type: source | entity | concept | comparison | overview | query
tags: [tag1, tag2]
created: YYYY-MM-DD
updated: YYYY-MM-DD
source_count: N   # only for source pages: how many raw sources contributed
status: draft | reviewed | evergreen
---
```

- `type` maps to the directory the page lives in (source → sources/, entity →
  entities/, etc.)
- `tags` are lowercase, no spaces. Keep the set small (≤5) and reuse existing tags
  where possible.
- `status: draft` means the page was written but not yet reviewed by the human.
  The human upgrades to `reviewed` or `evergreen`. Pages tagged `needs-review`
  have been updated since the last human review.
- `source_count` is set only on source-summary pages; omit on other types.

<!-- OBSIDIAN_CONVENTIONS_START
## Obsidian conventions

- Wiki links use the `[[Page Title]]` format (Obsidian default).
- Frontmatter fields (`tags`, `created`, `updated`, `status`, `source_count`)
  are Dataview-compatible — install the Dataview plugin to query them.
- Images are downloaded locally to `raw/assets/`. Bind "Download attachments for
  current file" to a hotkey (e.g., Ctrl+Shift+D) for one-click local download
  after web clipping.
- The graph view shows the wiki's cross-reference web — use it to spot hubs
  and orphans visually.
OBSIDIAN_CONVENTIONS_END -->

## Cross-references

- Link to other wiki pages with wiki links: `[[Page Title]]`
- When referencing a specific raw source, link to the source's summary page, then
  from the summary page to `raw/<filename>`.
- When a page makes a factual claim, it should cite its source. Format:
  `([[Source Page Title]])` inline after the claim.
- Claims that contradict an existing claim on another page should add a prominent
  callout: `> ⚠️ Contradiction: [[Other Page]] claims <summary>.` Tag both pages
  with `contradiction` and note the discrepancy.

## index.md conventions

The index is a content-oriented catalog, organized by section:

```markdown
# Wiki Index

## Overview
- [[overview]] — the synthesis entry point

## Sources
- [[Source Title]] — one-line summary of what this source adds (YYYY-MM-DD)

## Entities
- [[Entity Name]] — type (person/org/product/place), one-line description

## Concepts
- [[Concept Name]] — one-line definition or framing

## Comparisons
- [[Comparison Topic]] — what's being compared

## Queries
- [[Query Title]] — the question answered (YYYY-MM-DD)
```

Update the index on every ingest: add the source summary, add any new entity/
concept pages created, and if existing pages gained substantial new content, update
their one-line summary.

## log.md conventions

Append-only, chronological. Each entry starts with a consistent prefix for
parseability:

```markdown
## [YYYY-MM-DD] <operation> | <description>
```

Operations: `ingest`, `query`, `lint`, `bootstrap`.

Format:
- **ingest**: `## [YYYY-MM-DD] ingest | <Source Title> — pages touched: <list>`
- **query**: `## [YYYY-MM-DD] query | <question> — answer filed: [[Page Title]]`
- **lint**: `## [YYYY-MM-DD] lint | <N> issues found, <M> fixed`

The prefix convention makes the log parseable with `grep "^## \[" log.md`.

## Tags

These tags are in use across the wiki. Reuse existing tags before creating new
ones. The agent adds to this list as new tags are introduced.

| Tag | Meaning |
|-----|---------|
| `contradiction` | Page contains a contradiction with another page |
| `needs-review` | Page has been updated since last human review |
| `orphan` | No other page links to this one |
| `stale` | Content may be outdated by newer sources |
| `todo` | Page notes a gap that should be filled |