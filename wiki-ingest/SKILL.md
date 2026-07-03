---
name: wiki-ingest
description: Ingest a source into the personal knowledge base wiki. Use when the user wants to ingest a source, process an article, add a document to the wiki, file a source, or mentions "ingest".
---

# Wiki Ingest

Read a new source, discuss it with the user, and integrate it into the wiki —
writing a source-summary page, updating entity and concept pages across the wiki,
refreshing the index, and appending to the log.

Before each step, read the wiki's `AGENTS.md` schema to confirm conventions the
wiki was bootstrapped with (directory layout, page format, cross-referencing
style).

## Phase 1 — Locate and read the source

1. Identify what to ingest. Accept:
   - **A path to a file** already in `raw/` (the user dropped it there).
   - **A URL** — fetch it with the agent's fetch tool and save a copy to `raw/`
     first.
   - **Pasted text** — the user provides content in the conversation; save it as
     a markdown file in `raw/` with a descriptive filename.

2. Read the source in full. For long sources (book chapters, podcast transcripts,
   >10k words), read it end-to-end but work section by section.

3. If images are referenced in the source and the wiki was configured for images
   (check `AGENTS.md`), note them. View key images to gain visual context.

**Completion criterion**: the source is fully read; the agent can summarize its
core claims, evidence, and what's novel relative to the existing wiki.

## Phase 2 — Pre-ingest scan

Read the existing `wiki/index.md` and the `wiki/overview.md` (if it exists). Scan
entity and concept pages that overlap with the source's subject matter — search
for names, terms, and claims the source might update or contradict. This is the
agent's internal legwork; no output to the user yet.

**Completion criterion**: the agent has a mental map of which existing pages this
source touches, and where it might update, extend, or contradict.

## Phase 3 — Discuss with the user

Present the key takeaways, organized as:

1. **What's new** — information not in the wiki.
2. **What it updates** — existing claims this source reinforces or refines.
3. **What it contradicts** — claims in the wiki the source disagrees with.
4. **What to emphasize** — ask the user what to foreground vs. background.

Guide the discussion, but let the user direct emphasis. The user may want to
dismiss some takeaways as irrelevant, or go deeper on others before filing.

**Completion criterion**: the user has confirmed which takeaways to file and with
what emphasis. Ambiguity about whether to include something is resolved (ask if
needed; default to include).

## Phase 4 — Write the source-summary page

Create `wiki/sources/<Source Title>.md` with these sections:

```markdown
---
title: "<Source Title>"
type: source
tags: [relevant, tags]
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: draft
source_count: 1
---

# <Source Title>

**Source**: raw/<filename>  (or URL if web-sourced)
**Date ingested**: YYYY-MM-DD

## Summary
<1–2 paragraph synthesis of the source's core argument and evidence>

## Key Claims
- Claim with citation to other wiki pages where relevant ([[Page]])
- ...

## Connections
- **Extends**: [[Page]] — how this source builds on it
- **Contradicts**: [[Page]] — the disagreement (tag both pages `contradiction`)
- **New**: introduces the concept of X — consider a concept page

## Quotes
> Notable passages the user flagged or that capture a key idea.
```

The **Connections** section is the most important part — it builds the wiki's
cross-reference web. Be specific: "how" matters more than "that".

**Completion criterion**: the source-summary page exists at the correct path with
all sections populated. Connections link to at least the pages identified in the
pre-ingest scan (Phase 2).

## Phase 5 — Update entity and concept pages

For each entity or concept page the source touches:

1. If the page **already exists**, add a section or paragraph integrating the new
   information. Cite the source: `([[Source Title]])`. If the new information
   contradicts an existing claim, add a contradiction callout (see `AGENTS.md`
   conventions) and tag both pages.
2. If the page **does not exist**, create a stub page for the entity or concept.
   A stub needs: frontmatter with `status: draft`, a one-paragraph description,
   a `## Sources` section linking to the source-summary page, and a `## Mentions`
   section (empty, to be filled as more sources arrive).
3. Update `updated:` in the frontmatter of every touched page.

After all entity and concept pages are updated, check the overview:

4. If the source substantially changes the synthesis, update `wiki/overview.md`
   (create it from the source summary if this is the first ingest; otherwise
   integrate the new material into the evolving synthesis).

**Completion criterion**: every entity, concept, and overview page the source
touches has been updated or created. No page references a source that hasn't been
linked.

## Phase 6 — Update index and log

1. **index.md**: add the source-summary page under `## Sources`. If new entity or
   concept pages were created, add them under their sections. If existing pages
   gained substantial new content, update their one-line summary.
2. **log.md**: append an entry:
   ```markdown
   ## [YYYY-MM-DD] ingest | <Source Title> — pages touched: <comma-separated list>
   ```
   List every page created or updated, including index.md and log.md.

**Completion criterion**: index.md lists the new source and any new entities/
concepts. log.md has an entry for today's date with the full page list.

## Phase 7 — Report

Print a summary:

```
Ingested: <Source Title>
Pages created: <count> — <list>
Pages updated: <count> — <list>
Source summary: wiki/sources/<filename>.md
```

If the source introduced contradictions, flag them explicitly: "⚠️ Contradictions
introduced — review [[Page A]] and [[Page B]]."