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
- Added title/author fallback searches for DOI-less entries using Crossref,
  OpenAlex, and arXiv.
- Added book lookup paths through Open Library and Google Books, including ISBN
  lookup where an ISBN is present.
- Added URL metadata inspection for `url`, `note`, and `howpublished` links,
  including direct PDF URL detection and citation meta-tag extraction.
- Added Semantic Scholar API adapter for DOI lookup and title/author fallback
  search.
- Added PubMed / NCBI E-utilities adapter for DOI, PMID, and title/author
  fallback search.
- Added CORE API adapter for DOI and title/author search, with open-access PDF
  candidate discovery when returned by CORE.
- Added Figshare API adapter for DOI and title/author search, including
  article-detail lookup for downloadable PDF files.
- Added `TO_CONSIDER.md` to track optional future APIs and why they might help.

### Caching
- Added `cache_dir` parameter to `ApiProvider` and `check_bibliography`;
  API responses are written to and read from a local directory to support
  repeat runs without re-querying providers.

### Bug fixes
- Improved LaTeX title normalization for search and comparison: braces,
  TeX-style quotation marks, smart quotes, and formatting macros such as
  `\raggedright` are normalized away before matching/searching.
- Improved title/author search queries to use normalized title words plus all
  available author surnames instead of only the first raw author string.
- Added ADS-style arXiv identifier recovery, e.g. `2016arXiv160803413M` now
  yields `1608.03413`.
- Improved author matching for surname plus initials, so full names and
  initialized names can match after normalization.
- Hardened source selection: candidates with title/author hard conflicts, or
  large year gaps for books, are discarded rather than selected as low-confidence
  matches.
- `check_bibliography` now skips BibTeX key `anon`, which is treated as an
  anonymized-review artifact rather than a real reference.
- Fixed DOI extraction from LaTeX `\url{...}` wrappers in misplaced fields
  such as `note`.
- Added PMID extraction from `pmid`, `note`, `url`, and `howpublished` fields.
- Fixed `sources_for(::ApiProvider, ...)` so entries with a DOI hidden in
  `note` or `url` still use the DOI-backed API path.
- Fixed Open Library ISBN records to store ISBN provenance in `raw` rather than
  passing a non-existent `isbn` field to `SourceRecord`.
- Fixed title/author fallback query construction for entries with empty author
  lists.
- Fixed report generation to preserve actual BibTeX keys, including underscores,
  in Markdown and INC output.
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
- Expanded offline coverage for `providers.jl`: cache hit paths, provider error
  branches, Open Library ISBN/search records, Google Books records, and
  repository metadata shapes are now covered with mocked responses.
- Expanded offline coverage for `cli.jl`: CLI option parsing, check mode, fetch
  mode manifest generation, and invalid-mode exit behavior are now tested.
- Added provider tests for DOI-less article fallback search, book search,
  URL metadata extraction, direct PDF URL detection, and arXiv/URL/DOI recovery
  from non-standard fields.
- Added provider tests for Semantic Scholar, PubMed, CORE, Figshare, and PMID
  extraction using mocked API responses.
- Added regression tests from `surreals.bib`-style failures: LaTeX title
  normalization, ADS arXiv IDs, surname/initial author matching, hard mismatch
  source rejection, book year mismatch rejection, and skipping `anon`.
- Added report tests for checklist symbols, field importance/severity columns,
  ignored fields such as `abstract`, and exact key preservation.
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
- Added separate `.github/workflows/jet.yml` and `.github/workflows/aqua.yml`
  checks on latest stable Julia only.
- Added `.github/workflows/documenter.yml`: Documenter.jl documentation build
  and deployment on push to `main` or tag.
- Added badges (CI, Codecov, JET, Aqua, Documentation stable/dev, License) to
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
