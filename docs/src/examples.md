# Examples

The `examples/` directory contains small files that are also used by the test
suite. They are intended to show the main cases PaperFetch.jl should handle.

## Exact Article

```bash
julia --project=. src/cli.jl check examples/01_exact_article.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

This example should produce high confidence with exact field matches.

## Normalized Bibliography Differences

These examples demonstrate differences that can be acceptable even when strings
are not byte-for-byte identical:

- `examples/02_title_case_article.bib`: title case and page dash normalization.
- `examples/03_latex_accents.bib`: LaTeX accent and Unicode normalization.

Run one with:

```bash
julia --project=. src/cli.jl check examples/03_latex_accents.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

## Review Warnings

These examples intentionally produce warnings or lower-confidence comparisons:

- `examples/04_missing_doi.bib`: source metadata has a DOI missing from BibTeX.
- `examples/05_conflicting_doi.bib`: BibTeX DOI conflicts with source metadata.

Identifier conflicts should be treated seriously. Unlike titles or author
formatting, DOI differences are not treated as harmless normalization issues.

## Non-Paper References

Not every bibliography item is a journal article or has a PDF:

- `examples/06_web_reference.bib`: online documentation.
- `examples/07_dataset_reference.bib`: dataset reference.
- `examples/08_arxiv_preprint.bib`: arXiv-style preprint.
- `examples/09_book_chapter.bib`: book chapter.
- `examples/10_online_report.bib`: online report without a PDF.

PaperFetch.jl records the absence of a PDF candidate as a fetch status, not as
a bibliography error.

## Plain DOI Lists

Plain text input is also accepted:

```bash
julia --project=. src/cli.jl check examples/11_plain_dois.txt \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

Each non-comment line is interpreted as a DOI, URL, or title-like item.

## Live API Mode

Live API mode is opt-in:

```bash
julia --project=. src/cli.jl check references.bib \
  --email your.email@example.edu \
  --use-apis \
  --outdir paperfetch_out
```

The current live adapter queries Crossref, OpenAlex, and Unpaywall for
DOI-backed entries. API behavior can change, so fixture-backed checks remain
the preferred path for deterministic tests and repeated review.

## Manual Online Field Tests

Real DOI-backed field-test examples live in `examples/online/field_tests.bib`.
They are separate from the default test suite because network availability and
provider responses are not deterministic.

Run them manually with:

```bash
PAPERFETCH_ONLINE=true \
PAPERFETCH_EMAIL=your.email@example.edu \
julia --project=. test/online/runtests.jl
```

The online runner checks that each example returns at least one non-error
source, has an exact normalized DOI match, writes reports, and finds at least
one PDF candidate across the set.
