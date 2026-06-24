# Live Providers

PaperFetch.jl runs offline unless live lookup is explicitly enabled. Offline
checks use fixture metadata or the bibliography itself as the candidate source.
Live checks use public scholarly APIs and landing-page metadata to gather
candidate records for comparison.

A fixture is a local JSON file containing known source metadata. Fixtures are
used for examples, tests, and repeatable offline reviews where you want to test
comparison/reporting behavior without depending on current network or provider
responses.

## Enabling Live Lookup

From the command line:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_cache \
  --outdir paperfetch_out
```

From Julia:

```julia
using PaperFetch

reports = check_bibliography(
    "references.bib";
    email = "your.email@example.edu",
    use_apis = true,
    cache_dir = ".paperfetch_cache",
)
```

Use a real contact email. Several scholarly APIs either require or strongly
prefer an email or informative user agent for responsible use.

## Provider Scope

PaperFetch.jl chooses lookup routes from the identifiers and entry type it can
see:

- DOI-backed entries can use Crossref, OpenAlex, Unpaywall, DataCite, Semantic
  Scholar, PubMed, CORE, and Figshare. DOI strings can be recovered from the
  `doi` field, DOI resolver URLs, and common misplaced fields such as `note`,
  `url`, and `howpublished`.
- arXiv identifiers use the arXiv API.
- PMID values use PubMed.
- ISBN-backed books can use Open Library and Google Books.
- Entries with only a title, or entries whose identifier resolves to an
  obviously different work, can use title-and-author fallback search.
- URL-backed entries can check the URL and read common citation metadata from
  the landing page. URLs can be taken from `url`, `note`, or `howpublished`,
  including LaTeX `\url{...}` macros.

Provider results are candidates, not automatic truth. The report records
agreement, conflicts, missing fields, and provider errors so a person can decide
what should be fixed in the original BibTeX.

Book-like entries are handled with their expected fields. Proceedings and
chapter entries compare `booktitle` rather than `journal`; edited books can
compare `editor` as the creator when no `author` field is present. A large year
gap for a book is treated as evidence that a provider may have returned a
different edition.

## Caching And Rate Limiting

`--cache-dir` stores API and landing-page responses by request URL and headers.
Cache hits are reused without another network request. Writes are atomic, so an
interrupted run should not leave half-written cache files.

`--rate-limit-seconds` sets the minimum delay between uncached live requests made
by the default API provider:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check references.bib \
  --use-apis \
  --email your.email@example.edu \
  --cache-dir .paperfetch_cache \
  --rate-limit-seconds 0.05 \
  --outdir paperfetch_out
```

The default is intentionally light because a normal PaperFetch.jl run checks
roughly 10-100 references and spreads requests across several APIs. Increase the
delay if a provider asks you to slow down, if you are running repeated field
tests, or if your network path is sensitive.

## Ignored Keys

By default, `check_bibliography` skips the BibTeX key `anon`, which is commonly
used for anonymized review artifacts rather than real references. Override this
from the command line with a comma-separated list:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check references.bib \
  --ignore-keys anon,draft_placeholder \
  --outdir paperfetch_out
```

From Julia, pass `ignore_keys=nothing` to keep every entry:

```julia
reports = check_bibliography("references.bib"; ignore_keys=nothing)
```

## Operational Notes

- Keep cache directories local when checking private bibliographies.
- Do not commit downloaded PDFs, cookie files, API caches, or private `.bib`
  files.
- Treat provider errors as evidence about the lookup attempt, not necessarily
  evidence that the bibliography entry is wrong.
- Prefer fixture-backed tests for deterministic CI and use manual online field
  tests to inspect current provider behavior.
