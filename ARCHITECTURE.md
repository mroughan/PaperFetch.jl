# Architecture

PaperFetch.jl is intended to help validate and improve bibliographies by
checking references against the best available source metadata and, where
appropriate, retrieving accessible copies of referenced documents.

The primary input is a BibTeX file. The primary output is not a modified BibTeX
file, but a set of reports that a human or a separate AI-assisted editing step
can use to improve the bibliography.

The package is expected to be used on small to medium literature-review
bibliographies, typically 10-100 references. That scale shapes most design
choices: correctness, traceability, politeness, and explainability are more
important than maximal throughput.

## Goals

1. Validate BibTeX records against authoritative or semi-authoritative source
   metadata.
2. Report mismatches, ambiguities, missing fields, and likely corrections in a
   form that is easy for a person to review.
3. Download open-access PDFs when a reliable source identifies one.
4. Support controlled local credential workflows for papers the user is
   entitled to access through a library or institution.
5. Preserve provenance for every claim the tool makes: which API, page, DOI,
   URL, or file led to the observation.
6. Handle real-world bibliography messiness without treating every textual
   difference as an error.

## Non-Goals

PaperFetch.jl should not:

- Edit, rewrite, or reformat the input `.bib` file.
- Store usernames, passwords, library credentials, or long-lived session
  secrets.
- Bypass access controls or automate access outside the user's legitimate
  entitlements.
- Scrape publisher pages when a stable metadata API or standards-based endpoint
  is available.
- Attempt high-volume harvesting, mirroring, or bulk publisher downloading.
- Assume that every bibliography item is a journal article or has a PDF.
- Treat BibTeX field strings as needing byte-for-byte equality with source
  metadata.

## Key Philosophy

The package should behave like a careful research assistant, not an automatic
bibliography editor.

It should gather evidence, normalize what can be normalized, explain what it
found, and leave final editorial decisions to the user or to a later tool that
is explicitly tasked with editing. A reference may be substantially correct
even when its title casing, author initials, page ranges, journal abbreviation,
publisher spelling, or escaped characters differ from the source metadata.

The central question is therefore not "is this entry identical?" but "does this
entry appear to refer to the same work, and what should the reviewer inspect?"

## Core Workflows

### 1. Check

The check workflow reads a BibTeX file, resolves each entry to candidate source
records, compares the entry against those records, and writes a report.

The report should include:

- Input key and entry type.
- Fields present in the BibTeX entry.
- Candidate identifiers such as DOI, ISBN, URL, arXiv ID, PubMed ID, or landing
  page URL.
- Source metadata found from APIs or standards-based endpoints.
- Field-by-field comparison results.
- Confidence that the source metadata refers to the same work.
- Human-readable notes explaining mismatches and ambiguities.
- Machine-readable structured output suitable for a future AI repair step.

### 2. Fetch Open-Access PDFs

The open-access fetch workflow extends checking by finding and downloading PDFs
that are openly available. Candidate PDF URLs should come from metadata
providers whenever possible, such as Unpaywall, OpenAlex, Crossref links, arXiv,
PubMed Central, DOAJ, or publisher-provided metadata.

Downloaded files should be recorded in a manifest with:

- BibTeX key.
- Source identifier and URL.
- Final URL after redirects.
- Access route, for example `unpaywall`, `openalex`, `crossref`, or `arxiv`.
- File path.
- File size.
- Hash.
- Timestamp.
- Any warnings about content type, filename, or metadata uncertainty.

### 3. Fetch With Local Credentials

The credential-assisted workflow is for documents the user is entitled to
access through a library, institution, or publisher account. The package should
only use credentials indirectly, for example through:

- An EZproxy URL template supplied by the user.
- A locally exported browser `cookies.txt` file.
- A future local browser automation mode where the user logs in manually.

The package must not ask for passwords. Cookie files and session tokens should
be treated as bearer secrets. Reports should avoid leaking credential-bearing
URLs where possible, and should warn when such URLs may appear in output.

## Data Model

The implementation should separate input records, source records, comparisons,
and fetch attempts.

Suggested internal concepts:

- `BibEntry`: the parsed BibTeX entry, including key, type, raw fields, and
  source location in the input file if available.
- `WorkIdentifier`: normalized identifiers extracted from the entry, such as
  DOI, ISBN, URL, arXiv ID, PubMed ID, or OpenAlex ID.
- `SourceRecord`: metadata returned by a provider or discovered from a landing
  page.
- `CandidateSource`: a possible authority for the entry, with provenance and
  confidence.
- `FieldComparison`: the result of comparing one BibTeX field to one or more
  source values.
- `FetchAttempt`: an attempted retrieval of a PDF or landing page.
- `Report`: the accumulated review result for each bibliography entry.

These objects should be plain Julia data structures with predictable
serialization to JSON, TSV, and Markdown.

## BibTeX Parsing

BibTeX is complicated enough that ad hoc parsing should be avoided for the
stable package. The package should use BibParser.jl, or another real BibTeX
parser if project needs change, to preserve entry structure and correctly
handle nested braces, escaped characters, macros, comments, multiline fields,
and non-article entry types.

Parsing should preserve enough raw information to explain findings, but later
logic should operate on normalized field values. The parser layer should not
decide whether a reference is correct; it should only extract the input
faithfully.

## Metadata Sources

PaperFetch.jl should prefer APIs and standardized metadata mechanisms over
page scraping.

Initial source priorities:

1. DOI resolution and Crossref metadata for DOI-backed scholarly works.
2. OpenAlex for work-level metadata, open-access status, and related IDs.
3. Unpaywall for open-access locations and best OA PDF candidates.
4. DataCite for datasets, reports, software, and non-Crossref DOI records.
5. arXiv, PubMed, PubMed Central, Semantic Scholar, DOAJ, or publisher-specific
   APIs where identifiers or source context justify them.
6. HTML metadata from landing pages using standards such as Highwire Press
   tags, Dublin Core, schema.org JSON-LD, Open Graph, citation meta tags, and
   COinS.

Publisher-specific scraping should be a last resort. If an adapter is needed,
it should be isolated, tested, rate-limited, and documented with the reason it
exists.

## Matching and Comparison

Bibliographic validation must be tolerant but explicit.

The comparison layer should distinguish:

- Exact match.
- Normalized match.
- Equivalent or likely equivalent value.
- Missing in BibTeX.
- Missing in source metadata.
- Conflicting value.
- Ambiguous result requiring review.

Normalization should account for:

- Unicode normalization and LaTeX accent equivalents. 
- TeX escapes and BibTeX braces.
- Case and title-case differences.
- Punctuation and whitespace.
- Journal abbreviations versus full journal titles.
- Author initials, particles, suffixes, and ordering.
- Page range forms, such as `123-130` versus `123--130`.
- DOI URL forms versus bare DOI strings.
- Dates represented as year/month/day versus publication date parts.

The package should report confidence rather than force binary pass/fail labels.
For example, a title and DOI match with minor author formatting differences is
probably a high-confidence match with warnings, not a failure.

But some fields such as identifiers like DOI should be an exact match. 

## Non-Paper References

Some bibliography entries refer to websites, documentation, datasets, standards,
software, videos, legal materials, or online information rather than published
papers. These entries may have no DOI and no PDF.

The package should handle these as first-class cases. For online references it
can check URL reachability, redirects, page title, access date hints, content
type, and available embedded metadata. It should not mark the absence of a PDF
as an error unless the entry type or source metadata strongly implies that a PDF
should exist.

## Reporting

Reports are the main product of the package.

The stable reporting set should include:

- A human-readable Markdown report for review.
- An INCspec file (see IncCSV.jl).

Reports should be deterministic where practical. They should include timestamps
for network-dependent checks, but avoid noisy ordering or formatting changes
that make diffs hard to review.

Reports should include enough context for another AI or script to propose
BibTeX edits, but they should not apply those edits themselves.

## Rate Limiting and Cost

The expected bibliography size is 10-100 entries, so simple polite behavior is
usually sufficient:

- Use contact email parameters or user-agent mailto fields where APIs request
  them.
- Cache API responses and resolved landing-page metadata for repeat runs.
- Use modest concurrency, or default to sequential requests until concurrency
  is explicitly added with rate limits.
- Respect API response headers and documented limits.
- Retry transient failures with bounded exponential backoff.
- Avoid repeatedly downloading large files when a hash or existing manifest
  entry shows the file has already been fetched.

Any future AI-assisted interpretation should be optional, bounded, and based on
the structured report rather than raw uncontrolled page content.

## Security and Credentials

The security model is local-first.

PaperFetch.jl should:

- Never request or store passwords.
- Avoid writing cookies or session tokens to logs.
- Treat cookie files as sensitive local inputs.
- Make credential-assisted fetching opt-in.
- Clearly separate open-access fetching from credential-assisted fetching.
- Warn users before producing shareable reports that may contain proxied or
  institution-specific URLs.

The package should retrieve only material the user has a right to access and
should respect publisher and library terms.

## Error Handling

Network and metadata failures are normal, not exceptional, at the bibliography
level. One bad entry should not stop the full run.

Each entry report should record:

- Provider queried.
- Request outcome.
- HTTP status when available.
- Parse or metadata error when available.
- Whether the result is retryable.
- Whether the user should inspect manually.

Only configuration errors, unreadable input files, invalid output locations, or
unsafe credential handling should usually abort a run.

## Package Structure

A stable implementation should evolve toward modules with narrow
responsibilities:

- `Bib`: parsing and normalized access to BibTeX entries.
- `Identifiers`: DOI, URL, ISBN, arXiv, PubMed, and related extraction.
- `Providers`: API clients and source metadata adapters.
- `Normalize`: text, name, title, date, journal, page, and identifier
  normalization.
- `Compare`: field-level and record-level validation logic.
- `Fetch`: PDF and landing-page retrieval.
- `Credentials`: EZproxy, local cookies, and future local browser session
  integration.
- `Reports`: Markdown, INC, and manifest writers.
- `CLI`: command-line interface and argument validation.

The public API should remain small and stable, while provider adapters and
normalization rules can grow behind it.

## Testing Strategy

Tests should favor small, realistic fixtures over broad mocks.

Important test areas:

- BibTeX parsing edge cases.
- DOI, URL, and identifier normalization.
- Title, author, date, journal, and page comparison.
- Provider response parsing from saved fixtures.
- Report generation stability.
- Fetch manifest behavior.
- Credential handling boundaries.

Network tests should be optional or quarantined. The default test suite should
run offline using recorded provider responses and small sample files.

## Evolution From Prototype

The current code is a useful prototype for exploring candidate URLs, probing
access, and downloading PDFs. The main architectural changes needed for a
stable package are:

- Replace lightweight BibTeX extraction with BibParser.jl.
- Split parsing, providers, comparison, fetching, and reporting into separate
  modules.
- Introduce structured result types instead of passing mostly strings and
  tuples.
- Add source metadata comparison, not only source probing.
- Add deterministic Markdown and JSON reports.
- Add caching, rate limiting, retries, and offline tests.

The package should grow by making each observation more explainable, not by
making automated edits more aggressive.
