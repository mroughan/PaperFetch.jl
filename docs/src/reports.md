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

## Source Resolution

Provider records are treated as candidates until they pass PaperFetch.jl's
source-resolution step. This step is deliberately conservative:

- hard title, creator, or year mismatches are rejected;
- a candidate must have identity evidence, such as matching DOI, matching title
  and creator, matching title and year, matching title and container, or a
  matching URL;
- a close-but-not-identical title can be accepted when creator and year evidence
  are strong, but the title remains marked for manual review;
- the source-resolution confidence must pass a minimum threshold;
- fields present in the source but absent from the BibTeX entry are still
  reported as missing input, but they do not by themselves make the candidate a
  worse identity match.

This means a title-only search hit may be shown as discarded rather than used as
the source of truth. When two candidates are equally plausible and one is a
journal article while the other is an arXiv preprint of the same work,
PaperFetch.jl prefers the journal article and records that decision in the entry
notes.

### Scoring And Near-Ties

A candidate's score only reflects the fields it actually reports: a field the
source did not supply is excluded from the score entirely rather than
counted against it. This means a source that supplies very little
information can score a perfect match on the one or two fields it does
report — for example, a landing page whose only usable field happens to
equal the entry's own `url` — while a source such as Crossref or OpenAlex,
which independently confirmed many fields but was not a perfect match on
every one of them (say, a normalized rather than byte-identical page range),
scores slightly lower.

To stop a near-empty record from winning purely by having less to disagree
about, PaperFetch.jl prefers whichever candidate within a small score margin
of the top score independently verified the most fields. When this changes
which source is selected, the entry notes record it explicitly, for example:

```
preferred crossref (0.984, 7 verified fields) over url-metadata (1.0, 1
verified field), which scored marginally higher but with less
independently-verified metadata
```

### Full-Text PDF Verification

As a last resort, when no provider can confirm an entry, but a PDF candidate
URL is known, `check` (with `--use-apis`, unless `--no-verify-pdf-text` is
set) downloads that one PDF and checks its extracted text for the entry's
title, author, and year. Only fields actually found in the text are
reported, so a partial match is discarded by the same "insufficient identity
evidence" rule as any other candidate; a full match appears in the notes as a
`pdf-text` (or `pdf-ocr`, if OCR was needed for a scanned PDF) source, clearly
attributed as weaker, last-resort evidence. See
[Full-Text PDF Verification](https://github.com/mroughan/PaperFetch.jl/blob/main/README.md#full-text-pdf-verification-last-resort)
in the README for the optional `pdftotext`/`tesseract` tools this uses.

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
