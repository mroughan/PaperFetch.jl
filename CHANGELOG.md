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
- Added a conservative source-resolution layer before field comparison. Source
  records are now scored as candidates using identity evidence such as DOI,
  title/creator, title/year, title/container, and URL matches. Weak title-only
  hits and low-confidence candidates are discarded with explanatory notes
  instead of being treated as source metadata. When a journal article and arXiv
  preprint both match with equal confidence, the journal article is preferred
  and the report records that choice.
- Added progress reporting for check and fetch workflows. The CLI reports
  entry-by-entry progress to `stderr` by default, `--quiet` suppresses it, and
  the Julia API exposes an optional `progress_io` stream for callers that want
  progress messages.
- Polished progress reporting: the "Finished fetching PDFs" message now
  includes the reference count, matching "Finished checking N entries" for
  symmetry. CLI integration tests now pass `--quiet` to keep test logs clean,
  since progress message content is already covered by a dedicated
  `progress reporting` testset using an `IOBuffer`.

### Bug fixes (round 3)
- Refactored the `CITATION.cff` author parser to avoid a closure over a
  reassigned dictionary. This keeps the parser behaviour unchanged while making
  the possible value types explicit enough for JET on current Julia.
- Fixed `cff_authors` (CITATION.cff parsing): any author field other than
  `given-names`/`family-names`/`name` (e.g. `orcid`, `affiliation`) caused the
  parser to stop reading the authors list entirely, silently dropping every
  author after the first one with such a field. End-of-authors-section
  detection is now based on YAML indentation (an unindented line starts a new
  top-level CFF key) instead of the field name, so extra per-author fields no
  longer truncate the list.
- Added `cff_author_entries`, which parses each author's ORCID alongside their
  name. `cff_record` now stores any captured ORCIDs in `SourceRecord.raw["orcids"]`
  (keyed by author name) for provenance, since there is no BibTeX field to
  compare an ORCID against.

### Tests (round 3)
- Added `cff_author_entries` testset covering: an `orcid` field between two
  authors (the bug above), a trailing `affiliation` field, a top-level key
  ending the authors section, single-field `name:` authors, and content with
  no authors section.
- Updated the CITATION.cff fixture in `URL metadata and direct PDF lookup` to
  include an `orcid` field on the first author, asserting both authors are
  still captured and the ORCID lands in `raw["orcids"]`.
- Updated `progress reporting` testset to assert the exact symmetric
  "Finished fetching PDFs for N references" wording.

### Bug fixes (round 4)
- Fixed `url_records` (`url-metadata`/`url-pdf` sources) echoing the fetched
  URL back as the source's `url` field. `url_records` is only ever called on
  a URL already extracted from the entry itself, so that string is never
  independent information — comparing it against the entry's `url` field
  always reported an "exact" match even when the landing page (e.g. IEEE
  Xplore for a DOI resolver link) exposed no other citation metadata at all.
  Combined with the source-resolution scoring bug below, this let a
  metadata-free landing-page fetch outrank Crossref, OpenAlex, and Unpaywall
  records that had independently confirmed the DOI, title, author, and other
  fields, and triggered a misleading "doi does not match this entry's
  title/author" note. `url_records` no longer sets `url` on the records it
  returns (the fetched address is still kept in `id` for identification), and
  no longer echoes the entry's own `title` field back for direct-PDF sources.
- Fixed `source_resolution_score`: comparisons with no source value
  (`:missing_source`) are excluded from both the score's numerator and
  denominator rather than counted as an imperfect match, so a candidate with
  only one comparable field could score a perfect 1.0 on that field alone and
  outrank a candidate that substantively verified many fields but wasn't a
  perfect match on every one (e.g. a normalized rather than exact page-range
  match). `compare_entry` now prefers the candidate with the most
  independently-verified fields (`comparison_richness`) among candidates
  within `SOURCE_RESOLUTION_TIE_MARGIN` (0.05) of the top score, and records
  the tie-break in the report's notes when it changes the outcome.
- Fixed `compare_entry` discarding all PDF candidates whenever an entry had
  no *reliable* source, even if a less-reliable (or otherwise-discarded)
  source still reported a real `pdf_url`. `EntryReport.pdf_candidates` is now
  collected from every usable source regardless of whether it was reliable
  enough to confirm the entry's identity, so `fetch_pdfs` (and the new
  full-text verification below) can still try a PDF whose bibliographic
  metadata could not otherwise be confirmed.

### PDF full-text verification (last resort)
- Added `verify_pdf_text` to `check_bibliography` (on by default when
  `use_apis=true`): when no metadata provider found a reliable source for an
  entry, but a PDF candidate URL is known, downloads that one PDF and checks
  its extracted text for the entry's title, author, and year. This is a
  deliberate, narrowly-scoped exception to normally never downloading files
  just to check a bibliography — it only runs as a last resort for entries
  that would otherwise be reported unresolved.
- Text is extracted via `pdftotext` (poppler-utils) first, since most PDFs
  are born-digital; only if that yields fewer than `PDF_TEXT_MIN_CHARS` (40)
  characters — a scanned/image-only PDF — does it fall back to OCR
  (`pdftoppm` + `tesseract`) on the first `PDF_OCR_MAX_PAGES` (3) pages. Both
  tools are optional: `pdftotext_available()`/`ocr_tools_available()` check
  `Sys.which`, and verification is silently skipped if they are missing.
- Only fields actually found in the extracted text are populated on the
  resulting `pdf-text`/`pdf-ocr` `SourceRecord` (via `pdf_text_confirmation`);
  fields not found stay unconfirmed. This lets the result flow through the
  same `compare_entry` scoring and "insufficient identity evidence" discard
  logic as every other provider, rather than needing a special case, and
  keeps it clearly attributed as weaker, last-resort evidence rather than an
  authoritative metadata match.
- A failed download (e.g. paywalled or unreachable PDF) is recorded as a
  `pdf-text-error` source, surfaced as a provider-error note like every other
  adapter's error record, rather than raising.
- Added the `--no-verify-pdf-text` CLI flag (mirrors `verify_pdf_text=false`
  in the Julia API) to disable this behavior, since it is the one case where
  `check` downloads a file rather than only querying metadata.

### Docs (round 4)
- README: documented the Internet Archive provider, the richer-metadata
  tie-break, and added "Full-Text PDF Verification (Last Resort)" and
  "External Tools (Optional)" sections covering the new `pdftotext`/
  `pdftoppm`/`tesseract` dependencies, how to install them, that they are
  silently skipped when absent, and that a PackageCompiler-built stand-alone
  executable does not bundle them. Added a Security section bullet noting
  `check --use-apis` can now download and parse a PDF.
- `docs/src/index.md`: added the tie-break and full-text-verification
  behaviors to Design Commitments.
- `docs/src/examples.md` and `docs/src/standalone.md`: added Internet Archive
  to the live-provider lists; noted the full-text verification exception to
  "no downloads during check" and the external-tool dependency for
  stand-alone builds.
- `docs/src/reports.md`: added "Scoring And Near-Ties" (explaining why a
  near-empty source no longer outranks a richer one, and the note format when
  it changes the outcome) and "Full-Text PDF Verification" sections under
  Source Resolution.
- `SECURITY.md`: added a "Full-Text PDF Verification" section explaining what
  is downloaded, that it happens anonymously with no credentials, that it
  runs third-party tools (poppler, tesseract) PaperFetch.jl does not audit,
  and how to disable it.
- `CONTRIBUTING.md`: added an "Optional System Tools" section (install
  commands for poppler-utils/tesseract-ocr/imagemagick, and why tests skip
  gracefully without them) and two "Adding Providers Or Lookup Logic"
  guidelines: never echo a field's own input/query value back as if it were
  independently-verified evidence, and watch for Solr/Elasticsearch-style
  scalar-vs-array field shapes.
- `TO_CONSIDER.md`: updated the "already has adapters for" list to include
  Internet Archive and full-text PDF verification.

### Tests (round 4)
- Added `DOI-echo URLs do not inflate source ranking`, covering: a DOI
  resolver landing page with no citation metadata, an ordinary (non-DOI)
  landing-page URL, and a direct-PDF fetch via a DOI resolver link — none of
  which may echo `url`, and the direct-PDF case must not claim the entry's
  own `title` either.
- Added `richer metadata wins a near-tied source-resolution score`, an
  end-to-end regression for the Brent (1973) *IEEE Transactions on Computers*
  entry that originally surfaced this pair of bugs.
- Extended `source selection rejects hard mismatches` with a case where a
  single-field "exact" match (score 1.0) competes against a multi-field
  near-exact match (score < 1.0); the richer source must still win.
- Added `pdf_text_confirmation matches only what the extracted text
  confirms`, covering full confirmation, partial (nothing found) results, and
  that both flow correctly through `compare_entry`.
- Added `extract_pdf_text reads a born-digital PDF's text layer` and
  `extract_pdf_text falls back to OCR for a scanned PDF`, each skipped with an
  `@info` message when the required command-line tools (`pdftotext`, or
  `pdftoppm`/`tesseract`/ImageMagick's `convert`) are not installed.
- Added `check_bibliography verifies an otherwise-unresolved entry via PDF
  text`, an end-to-end test with a mocked download confirming an entry whose
  only candidate was a metadata-free direct-PDF link, and that the same entry
  stays unresolved with `verify_pdf_text=false`.
- Extended `book and repository provider shapes` with Internet Archive
  coverage: multi-valued vs. single-valued `creator`/`isbn` shapes, an
  integer `year`, a result missing `identifier` (must be skipped), and that
  book-type `title_search_records` includes an `internet-archive` result.
  Extended `provider cache and error branches` with the
  `internet-archive-error` case.
- `check_bibliography` now emits a clear `@warn` when it falls back to
  `CandidateProvider` (no fixture, no explicit `providers`, `use_apis=false`),
  since that fallback only echoes each entry's own title/doi/url back as its
  "source" and cannot validate anything against an independent record.
- `compare_entry` now adds an explicit note to the `EntryReport` itself in
  that same situation, so the limitation is visible in the generated
  Markdown/INC report, not only in a log line a reader may not see.

### New providers (round 4)
- Added an Internet Archive `advancedsearch.php` adapter
  (`internet_archive_search_records`) to the book/title-search path alongside
  Open Library and Google Books. Internet Archive often has older or
  public-domain books the other two do not, and its `pdf_url` guess (the
  conventional `{identifier}.pdf` filename within the item) sometimes yields
  a directly downloadable scanned PDF, which neither Open Library nor Google
  Books' search results otherwise provide.
- Handles Internet Archive's Solr-backed field shapes, where a multi-valued
  field (e.g. `creator`, `isbn`) comes back as a JSON array but a
  single-valued one comes back as a bare scalar for the very same field name
  (`string_or_list`), and where `year` is a bare integer rather than a
  string.
- A guessed `pdf_url` that turns out not to exist, or is access-restricted
  (e.g. a lending-library title), simply fails like any other unavailable PDF
  candidate — it is not treated as an error.

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
- Added patent metadata APIs to `TO_CONSIDER.md`, including The Lens,
  PatentsView, USPTO Open Data, EPO OPS, and WIPO PATENTSCOPE.

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
- Added `.github/workflows/codecov.yml` as a dedicated Codecov workflow. It runs
  coverage once on Julia 1.11, uploads with an explicit repository slug, and
  uses `fail_ci_if_error=false`. Codecov repository activation still has to be
  handled in Codecov/GitHub, but coverage upload is now visible as its own
  workflow.
- Added `.github/workflows/ci.yml`: tests on Julia 1.11 and nightly.
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
