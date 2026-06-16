# Changelog

## Unreleased

### Architecture
- Split monolithic `src/PaperFetch.jl` into focused include files:
  `normalize.jl`, `bib.jl`, `identifiers.jl`, `providers.jl`, `compare.jl`,
  `reports.jl`, `fetch.jl`, `cli.jl`.
- Added `WorkIdentifier` struct to represent normalized DOI, arXiv ID, ISBN,
  and URL identifiers extracted from a `BibEntry`.
- Added `CandidateSource` struct pairing a `SourceRecord` with the
  `WorkIdentifier` used to find it.
- Added `extract_identifiers` to drive provider queries from typed identifiers
  rather than raw field strings.

### New providers
- Added DataCite API adapter for dataset and software DOIs.
- Added arXiv API adapter (Atom XML) for preprints with `eprint`/`archivePrefix`
  fields.

### Caching
- Added `cache_dir` parameter to `ApiProvider` and `check_bibliography`;
  API responses are written to and read from a local directory to support
  repeat runs without re-querying providers.

### Bug fixes
- Fixed `openalex_records`: `url` field now records the landing-page URL,
  not a copy of the DOI string.
- Fixed `read_bibtex`: entries are now sorted by key for stable, reproducible
  report ordering.
- Fixed `read_items`: plain-text item keys are now `item1`, `item2`, …
  based on item count, not raw line index (blank lines and comments no longer
  shift keys).
- Fixed `compare_value` for `author` field: mismatching author strings now
  produce `:conflict` instead of `:ambiguous`.
- Fixed `comparison_score`: `:missing_source` weight reduced from 0.45 to
  0.15; absence of source metadata is not evidence of correctness.
- Fixed `slugify`: removed redundant `min(lastindex, maxlen)` guard.
- Fixed dead `downloaded || nothing` no-op in `fetch_pdfs`.
- Fixed `read_cookie_file`: now strips the `#HttpOnly_` prefix used by some
  browser cookie exporters.
- Fixed `src/cli.jl`: replaced the `include`-based stub with the actual CLI
  implementation.
- Fixed `DEFAULT_USER_AGENT`: version string now read from `pkgversion` rather
  than hard-coded.
- Fixed `Project.toml` authors field (was placeholder text from earlier AI
  tooling).
- Fixed docstring in `read_items` to reference the correct example file.
- Fixed `check_bibliography` provider API: `providers` now defaults to
  `AbstractProvider[]` rather than `nothing`; logic is cleaner and clearer.
- Fixed `cli.jl` to expose `--cache-dir` option and pass it to `ApiProvider`.

### Tests
- Added `normalization helpers` testset covering `normalize_pages`,
  `normalize_year`, `normalize_authors`, `comparison_score`, and the
  `:missing_source` weight fix.
- Added `compare_value author mismatch` testset.
- Added `WorkIdentifier extraction` testset covering DOI, arXiv, ISBN, and
  URL extraction.
- Added `cookie and proxy helpers` testset covering `read_cookie_file`
  (including `#HttpOnly_` prefix), `cookie_for_url`, and `proxied_url`.
- Fixed `fake_get` mock in fetch tests to accept current HTTP.jl timeout
  keywords.

### CI/CD
- Added `.github/workflows/ci.yml`: tests on Julia 1.11 and nightly
  with Codecov coverage upload.
- Added `.github/workflows/quality.yml`: JET and Aqua checks on latest Julia
  only, separate from main CI.
- Added `.github/workflows/documenter.yml`: Documenter.jl documentation build
  and deployment on push to `main` or tag.
- Added badges (CI, Codecov, Quality, Documentation stable/dev, License) to
  README.

## 0.2.0 (previous)

- Reimplemented the package around typed bibliography, source metadata,
  comparison, report, and fetch result records.
- Added BibParser.jl-based BibTeX parsing.
- Added fixture-backed source metadata checks for deterministic offline tests.
- Added tolerant field comparison for titles, authors, years, pages, publisher
  names, URLs, and exact normalized DOI checks.
- Added Markdown and INC report writers.
- Added PDF fetching from explicit candidate URLs with an INC manifest.
- Added 10 small BibTeX examples, one plain DOI-list example, and metadata
  fixtures.
- Added an offline test suite covering normalization, parsing, comparison,
  reports, fetch manifests, and the CLI.
- Added reference provenance notes and local copies of key implementation
  reference material.
- Added Documenter.jl documentation with Home, Examples, and API Reference
  pages generated from package docstrings.
- Added manually triggered online field tests using real DOI-backed
  open-access examples.
- Fixed Documenter API coverage for newly exported identifier types and
  functions.
- Fixed provider error records so failed API calls no longer score as
  successful DOI matches.
- Fixed provider DOI URL construction to preserve DOI path slashes for metadata
  APIs.
- Replaced deprecated HTTP timeout keywords with `read_idle_timeout`.
- Added cache provenance sidecars for API response caches.
- Added DOI recovery from misplaced fields such as `note`, `url`, and
  `howpublished`.
- Added normalization and comparison tests for multiple authors, accented
  author names, `et al.` author lists, DOI URL forms, misplaced DOIs, and
  likely spelling errors in author names and titles.
