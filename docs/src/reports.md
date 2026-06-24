# Reports and Manifests

PaperFetch.jl reports are the main output of a check. They are designed to
support review, not automatic editing: the input `.bib` file is never rewritten.

## Check Reports

`check` mode writes two files:

- a Markdown report for direct human review;
- an INC report for spreadsheets and downstream tooling.

From the command line, report names default to the input file stem:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check examples/01_exact_article.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

This writes `paperfetch_out/01_exact_article.md` and
`paperfetch_out/01_exact_article.inc`. Use `--report-basename NAME` to choose a
different basename.

Direct Julia API calls use `paperfetch_report` unless `basename` is supplied:

```julia
paths = write_reports(reports, "paperfetch_out"; basename="references")
```

## Markdown Report Layout

Each entry section starts with the original BibTeX key. Keys are preserved as
written, including underscores and punctuation.

Each entry then has a general-flags table for entry-level review signals:

- whether source metadata was found;
- whether providers returned errors;
- whether required fields are present;
- whether any field comparisons were possible;
- whether PDF candidates were discovered;
- the confidence score.

Field-level details are shown in a separate comparison table. The `Flag` column
summarizes each field as green, amber, red, or ignored. This avoids repeating a
full checklist while keeping the signal close to the field value being reviewed.

## Required And Supplementary Fields

Required fields depend on the BibTeX entry type. For example:

- `@article` expects `author`, `title`, `journal`, and `year`;
- `@inproceedings` expects `author`, `title`, `booktitle`, and `year`;
- `@book` accepts either `author` or `editor`, plus `title`, `publisher`, and
  `year`;
- `@inbook` and `@incollection` accept either `author` or `editor` and compare
  their container title as `booktitle`.

Supplementary fields such as `doi`, `url`, `pages`, `volume`, `number`, `isbn`,
and `edition` still appear in comparisons when present or when source metadata
reports them, but their absence is usually marked amber rather than red.

Common bibliography-manager fields such as `abstract`, `keywords`, `file`,
`timestamp`, and similar local metadata are treated as ignored for reference-list
validation.

## Normalization

Comparison is intentionally tolerant but explicit. Titles are normalized before
comparison and before title-based search: braces, TeX-style quotes, common LaTeX
formatting commands, accents, punctuation, case, and whitespace are normalized.

Author and editor lists use the same name-normalization logic. Full names can
match initials, accents are normalized, and `et al.` is treated as a review flag
rather than an automatic conflict. Reordered creator lists are marked ambiguous
because author order is often meaningful.

DOIs are stricter. Bare DOI strings, `doi:` prefixes, `doi.org` URLs, and
`dx.doi.org` URLs are canonicalized to the same DOI, but a different DOI remains
a conflict.

URLs are compared after canonicalizing hosts and DOI resolver links. URLs found
inside `note` or `howpublished`, including LaTeX `\url{...}` macros, can be used
as a fallback for a missing `url` field.

## Fetch Manifests

`fetch` mode first performs the same check workflow and then attempts only
explicit PDF candidate URLs from source metadata:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  fetch references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_cache \
  --outdir paperfetch_out
```

Fetch mode writes:

- the normal Markdown and INC check reports;
- `manifest.md`, a human-readable table of fetch outcomes;
- `manifest.inc`, a spreadsheet/tooling manifest;
- downloaded PDF files when a candidate URL succeeds.

The manifest records the BibTeX key, a compact reference title, fetch status,
local file path, source URL, and a short diagnostic. Entries with no PDF
candidate are recorded as `skipped`; this is normal for websites, datasets,
books, landing-page-only records, and many paywalled articles.

Failed PDF candidates include diagnostics such as HTTP status, non-PDF content
types, likely landing/login/paywall pages, or missing remote files.
