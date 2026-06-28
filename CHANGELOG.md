# Changelog

## Unreleased

### Reports
- Added a documentation page explaining Markdown report flags, field comparison
  flags, entry-type-specific required fields, normalization behavior, and fetch
  manifests.
- Updated README installation instructions now that PaperFetch.jl is registered
  and installable with `Pkg.add("PaperFetch")`.
- Clarified early in the README and docs that a fixture is local JSON source
  metadata used for deterministic examples, tests, and offline review.
- Reworked Markdown reports to reduce redundant checklist text. Each entry now
  has a compact general-flags table for source discovery, provider errors,
  required fields, comparison availability, PDF candidates, and confidence.
  Field-level review flags now appear as a `Flag` column in the field
  comparison table alongside importance, status, BibTeX value, source value,
  and diagnostic note.
- `@inproceedings` and related proceedings/chapter entries now compare the
  container title as `booktitle`, not `journal`, in the default field
  comparison set.
- `@book` and related chapter entries with an `editor` but no `author` now
  compare the creator field as `editor`, rather than reporting a missing
  `author`.

### Validation transparency
- `check_bibliography` now emits a clear `@warn` when it falls back to
  `CandidateProvider` (no fixture, no explicit `providers`, `use_apis=false`),
  since that fallback only echoes each entry's own title/doi/url back as its
  "source" and cannot validate anything against an independent record.
- `compare_entry` now adds an explicit note to the `EntryReport` itself in
  that same situation, so the limitation is visible in the generated
  Markdown/INC report, not only in a log line a reader may not see.

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
- Improved book lookup when the input has no ISBN: title/creator search results
  from Open Library or Google Books can now supply discovered ISBNs, which are
  then used for ISBN-specific metadata lookups.
- Added URL metadata inspection for `url`, `note`, and `howpublished` links,
  including direct PDF URL detection and citation meta-tag extraction.
- Added GitHub repository `CITATION.cff` discovery for URL-backed software
  references, using title, authors, DOI, release year, and URL metadata when
  present.
- Added Semantic Scholar API adapter for DOI lookup and title/author fallback
  search.
- Added PubMed / NCBI E-utilities adapter for DOI, PMID, and title/author
  fallback search.
- Added CORE API adapter for DOI and title/author search, with open-access PDF
  candidate discovery when returned by CORE.
- Added Figshare API adapter for DOI and title/author search, including
  article-detail lookup for downloadable PDF files.
- Added `TO_CONSIDER.md` to track optional future APIs, structured
  landing-page sources, and why they might help.
- Added notes to `TO_CONSIDER.md` for conference landing pages with embedded
  BibTeX, such as CVF open-access proceedings pages, and for JSTOR as a
  landing-page/text-analysis support consideration rather than a current public
  metadata API provider.

### Caching
- Added `cache_dir` parameter to `ApiProvider` and `check_bibliography`;
  API responses are written to and read from a local directory to support
  repeat runs without re-querying providers.

### Bug fixes (round 4)
- Fixed `pubmed_search_ids`: NCBI returns `idlist:[]` (not an omitted field)
  for any search with zero hits, which is the common case for non-biomedical
  DOIs. JSON3 parses an empty JSON array with no element-type hint as eltype
  `Union{}`, so `String.(...)` over it produced a `Vector{Union{}}` instead of
  `Vector{String}`. That failed to dispatch on
  `pubmed_summary_records(::ApiProvider, ::Vector{String}; ...)`, so every
  non-biomedical lookup was silently converted into a spurious
  `pubmed-error`/`pubmed-search-error` source carrying a `MethodError`
  instead of cleanly reporting "no PubMed hit". Switched to an explicitly
  `String[...]`-typed comprehension so the empty case stays `Vector{String}`.
- Fixed misleading "year" reason in `compare_entry`'s discarded-candidate
  notes: the diagnostic listed "year" as a hard-mismatch reason whenever a
  publication-year gap existed at all, even a gap of 0 or 1 that does not
  meet the actual hard-mismatch threshold (`>=2`, or `>=3` for books). Added
  `year_hard_mismatch` and reused it both in `source_hard_mismatch` and in the
  note-building code so the explanation always matches the real cutoff.

### Bug fixes (round 3)
- Fixed `sources_for(::ApiProvider, ...)`: an identifier such as a DOI that
  resolved successfully but pointed at the wrong work (mistyped or swapped
  DOI) previously suppressed the title/author search fallback, because the
  fallback only ran when *no* usable source was found at all. Added
  `identifier_source_conflicts` (reusing the same hard-mismatch comparison as
  `compare_entry`) so the fallback also runs when every identifier-resolved
  source hard-mismatches the entry's title or author, letting the package find
  the correct work under a different DOI.
- Improved `compare_entry` diagnostics: discarded hard-mismatch candidates are
  now reported in `EntryReport.notes` even when a reliable replacement source
  is found, and an explicit note is added when the chosen best source was
  found via title/author search under a DOI different from the one in the
  bibliography, so the inconsistency stays visible to the reviewer.

### Bug fixes (round 2)
- Fixed `openlibrary_isbn_records`: author objects from the ISBN endpoint only
  carry a key path (`/authors/OL1A`), not an inline name. Authors are now only
  captured when the response includes an explicit `name` field, preventing
  key-path strings from being used as author names and always failing comparison.
- Fixed `normalize_pages` to collapse en-dashes (–) and em-dashes (—) to a
  single ASCII hyphen, in addition to runs of ASCII hyphens. Real BibTeX page
  ranges frequently contain Unicode dashes.
- Fixed `PMID_PATTERN`: bare 6–9 digit numbers in `note`, `url`, and
  `howpublished` fields were incorrectly extracted as PMIDs. The pattern now
  requires an explicit `pmid:` prefix when extracting from free-text fields;
  bare numbers are still accepted from a dedicated `pmid` field.
- Fixed `arxiv_records`: direct entry-level title extraction now collapses
  internal whitespace with `r"\s+" => " "`, matching the behaviour of
  `arxiv_search_records` and preventing multi-line XML titles from being
  returned with embedded newlines.
- Fixed `source_identity`: notes now show the raw source title (truncated to
  80 characters) instead of the normalized, punctuation-stripped form, making
  log entries such as "best source: fixture (title:…)" readable.
- Added docstring for `normalize_url`, consistent with all other normalization
  functions in `normalize.jl`.
- Fixed `comparison_rows` in `reports.jl`: entries with no field comparisons
  (no source found, all sources rejected, all provider errors) now produce a
  single summary row with `status = "no_comparison"` and `severity = "red"`.
  Previously these entries were silently absent from the INC report.

### Tests (round 2)
- Added `normalize_url and urls_in_text` testset: DOI URL canonicalization,
  scheme stripping, trailing slash/punctuation removal, `\url{}` wrapper
  extraction, multiple-URL detection.
- Added `field importance and comparison severity` testset: `:important`,
  `:supplementary`, and `:ignored` field classification for articles and books;
  `comparison_severity` for all status/importance combinations including
  `:conflict`, `:missing_input`, `:missing_source`, `:ambiguous`, and ignored
  fields.
- Added `PMID text extraction requires explicit prefix` testset verifying that
  bare numbers in notes are not extracted and that `pmid:` prefix and the
  `pmid` field are both correctly handled.
- Added assertion to `book and repository provider shapes` testset confirming
  that `openlibrary_isbn_records` returns empty authors when only key paths are
  present in the response.
- Added assertion to `reports` testset verifying that entries with no
  comparisons produce exactly one INC row with `status = "no_comparison"`.

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
