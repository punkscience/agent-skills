---
name: wiki-lint
description: Health-check the personal knowledge base wiki. Use when the user wants to lint the wiki, check wiki health, audit the wiki, find contradictions, fix the wiki, or mentions "lint".
---

# Wiki Lint

Audit the wiki for structural and content issues — contradictions, stale claims,
orphan pages, missing cross-references, and gaps the existing pages imply but
don't fill.

Read `AGENTS.md` first for the wiki's conventions.

## Phase 1 — Inventory

Read `wiki/index.md` to get the full page list, organized by section. Follow
every link and note each page's existence, type, and cross-references (scan for
`[[...]]` links). Build an internal map:

- Which pages link to which
- Which pages have zero inbound links (orphans)
- Which pages have the `contradiction` or `stale` tag
- Pages whose `updated:` date is more than 60 days old and tagged `draft`

**Completion criterion**: the agent has read every wiki page listed in the index
and built the cross-reference map.

## Phase 2 — Lint passes

Run each pass over every page. Do not stop at the first issue found in a pass —
complete the pass across all pages before moving to the next.

### Pass A: Contradictions

For each pair of pages where both make factual claims on the same topic, compare
them. A contradiction exists when two pages assert incompatible facts. Relevance
test: trivial disagreements (e.g. one page says "~50" while another says "~52")
are not contradictions unless precision matters. Genuine conflicts (opposing
conclusions, contradictory timelines, incompatible interpretations) are.

Check pages already tagged `contradiction` — has the conflict been resolved by
later sources?

### Pass B: Staleness

For each page:
- Is the `updated:` date older than the most recent source that touches the same
  topic? Read the log to find recent ingests in the same category; if a newer
  source covers the same entity/concept but the page wasn't updated, flag it.
- Does the page reference claims from an ingested source whose conclusions were
  later contradicted? If so, flag the page as potentially carrying stale
  information.

### Pass C: Orphans

Every page needs at least one inbound link. A page with no other page linking to
it is an orphan — it exists in the index but not in the wiki's cross-reference
web. Flag every orphan. (index.md and log.md are excluded from this check.)

### Pass D: Missing cross-references

For each page, scan its content for:
- Entity or concept names mentioned in prose but not linked with `[[...]]`
- Claims without a source citation `([[Source]])` where the source is known
- Pages that should link to each other based on shared topics but don't

### Pass E: Missing pages

Scan all pages for terms or names formatted as wiki links `[[...]]` that resolve
to no existing page — these are redlinks. Sort them by how many pages reference
them; the most-referenced redlinks are the highest-priority pages to create.

### Pass F: Data gaps

For entity and concept pages flagged `status: draft`, check whether they
explicitly note what's missing (e.g. "TODO: source needed for claim X"). If the
`todo` tag is present, collect outstanding items.

**Completion criterion**: every pass has been applied to every page. No page was
skipped.

## Phase 3 — Report

Present findings organized by severity:

1. **Critical**: contradictions on factual claims
2. **Important**: stale pages, high-priority missing pages (>2 inbound redlinks)
3. **Nice-to-have**: orphans, missing cross-references, data gaps

For each finding, include:
- Which page(s) are affected
- The specific issue
- A suggested fix (e.g. "resolve the contradiction by checking source X", "create
  a concept page for Y", "link Z to W in paragraph 3")

Offer to apply fixes. For contradictions, ask the user how to resolve them before
acting. For orphans, link them from the most relevant existing page. For missing
pages, offer to create stubs. For missing cross-references, add the links. For
staleness, flag with the `stale` tag and note the newer source in a
`> ⚠️ Stale: [[Newer Source]] may supersede this.` callout.

**Completion criterion**: findings are reported with page references and suggested
fixes. The user has accepted or declined each fix category.

## Phase 4 — Apply fixes and log

1. Apply the fixes the user accepted.
2. For contradictions the user couldn't resolve, ensure both pages carry the
   `contradiction` tag and a cross-reference to each other.
3. Append to `wiki/log.md`:
   ```markdown
   ## [YYYY-MM-DD] lint | <N> issues found, <M> fixed
   ```
4. Print a summary of what was fixed and what was flagged for later.