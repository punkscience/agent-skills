---
name: wiki-query
description: Answer a question by searching the personal knowledge base wiki and citing its pages. Use when the user asks what the wiki says about a topic, asks a question about their knowledge base, or says "query the wiki".
---

# Wiki Query

Answer a question against the wiki — search the index, read relevant pages,
synthesize an answer with citations, and file the result back into the wiki so
the exploration compounds.

Read `AGENTS.md` first for the wiki's conventions.

## Phase 1 — Understand the question

Clarify the user's question if needed. What form should the answer take?

Forms the agent can produce:
- **Markdown page** — a well-structured answer with citations (the default)
- **Comparison table** — side-by-side breakdown of competing claims or entities
- **Timeline** — chronological synthesis across sources
- **Argument map** — premises, evidence, counterarguments

Ask the user if the default (markdown page) is sufficient, or if they want a
specific form. Don't ask for trivial questions where the default is obvious.

**Completion criterion**: the question is clear and the answer form is chosen.

## Phase 2 — Search and read

1. Read `wiki/index.md`. Identify pages whose titles, summaries, or tags match
   the question's subject.
2. Follow the most promising links — read those pages.
3. Follow cross-references from those pages — the answer may span multiple
   entities and concepts.
4. If the wiki has a search tool configured (check `AGENTS.md`), use it as well;
   otherwise rely on the index and cross-reference traversal.
5. If the wiki has few or no pages covering the topic, say so explicitly: note
   what's missing and ask if the user wants to search the web for sources to
   ingest first.

**Completion criterion**: all wiki pages likely to bear on the question have been
read.

## Phase 3 — Synthesize the answer

Write the answer in the chosen form. Requirements:

- **Citations**: every factual claim links to the wiki page(s) that support it,
  using `([[Page Title]])` inline.
- **Gaps**: note where the wiki doesn't yet have an answer. Don't fabricate.
- **Contradictions**: if pages disagree, present both sides with citations to
  each. Don't pick a winner unless the user directs.
- **Confidence**: distinguish well-sourced claims (multiple sources, consistent)
  from weakly-sourced ones (single source, or tagged `draft`).

**Completion criterion**: the answer is complete, every claim is cited or flagged
as unsourced, and contradictions are surfaced.

## Phase 4 — Present and file

1. Present the answer to the user.
2. Ask: "File this answer as a wiki page?" Default to yes for substantive answers
   (>3 paragraphs, or any answer with cross-references to >2 wiki pages). Skip
   the question for trivial lookups.
3. If filing, create `wiki/queries/<Answer Title>.md` with:

```markdown
---
title: "<Answer Title>"
type: query
tags: [relevant, tags]
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: draft
---

# <Answer Title>

**Question**: <the original question>
**Date answered**: YYYY-MM-DD

<the answer>
```

4. Update `wiki/index.md` — add the query page under `## Queries`.
5. Append to `wiki/log.md`:
   ```markdown
   ## [YYYY-MM-DD] query | <question> — answer filed: [[Answer Title]]
   ```

**Completion criterion**: the answer has been presented. If substantive, the
query page is created, the index is updated, and the log is appended.