# PaperFetch.jl

[![CI](https://github.com/mroughan/PaperFetch.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/mroughan/PaperFetch.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/mroughan/PaperFetch.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/mroughan/PaperFetch.jl)
[![JET](https://github.com/mroughan/PaperFetch.jl/actions/workflows/jet.yml/badge.svg)](https://github.com/mroughan/PaperFetch.jl/actions/workflows/jet.yml)
[![Aqua](https://github.com/mroughan/PaperFetch.jl/actions/workflows/aqua.yml/badge.svg)](https://github.com/mroughan/PaperFetch.jl/actions/workflows/aqua.yml)
[![Documentation](https://github.com/mroughan/PaperFetch.jl/actions/workflows/documenter.yml/badge.svg)](https://github.com/mroughan/PaperFetch.jl/actions/workflows/documenter.yml)
[![Documentation Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mroughan.github.io/PaperFetch.jl/stable)
[![Documentation Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mroughan.github.io/PaperFetch.jl/dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

PaperFetch.jl helps validate BibTeX bibliographies by checking entries against
source metadata and writing human-readable review reports. It is designed for
small and medium bibliography checks, usually 10-100 references, where traceable
evidence matters more than bulk harvesting.

PaperFetch.jl does not edit your `.bib` file. It reports what looks correct,
what looks suspicious, and what source metadata it found so that a person, script,
or separate AI-assisted editing task can improve the bibliography deliberately.

## What PaperFetch Does

- Parses BibTeX with BibParser.jl, plus simple plain-text DOI/URL lists.
- Extracts identifiers from normal and misplaced fields, including DOI, arXiv,
  PMID, ISBN, and URL values found in fields such as `note` and `howpublished`.
- Looks up metadata from deterministic fixtures or optional online providers:
  Crossref, OpenAlex, Unpaywall, DataCite, arXiv, Semantic Scholar, PubMed,
  CORE, Figshare, Open Library, Google Books, and URL landing-page metadata.
- Compares bibliography fields with cautious normalization for title case,
  page ranges, Unicode/LaTeX accents, DOI URL variants, author initials, and
  similar harmless differences. URL paths and queries keep their case, and
  reordered author lists are flagged for review rather than silently accepted.
- Writes Markdown and INC reports; INC is a spreadsheet-friendly CSV-like format
  handled by IncCSV.jl.
- Optionally downloads PDFs from explicit PDF candidate URLs and writes a fetch
  manifest.

## What PaperFetch Does Not Do

- It does not rewrite or auto-correct the input BibTeX file.
- It does not ask for, store, or manage library passwords.
- It does not scrape publisher pages when a suitable API or landing-page metadata
  route is available.
- It does not treat every provider disagreement as truth. Reports are evidence
  for review, not automatic authority.

## Installation

PaperFetch.jl currently targets Julia 1.11 or newer. Until the package is
registered, install it from the repository:

```julia
using Pkg
Pkg.add(url="https://github.com/mroughan/PaperFetch.jl")
```

For development from a local checkout:

```bash
git clone https://github.com/mroughan/PaperFetch.jl.git
cd PaperFetch.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Quickstart

Run a deterministic offline check with the included example fixture:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check examples/01_exact_article.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

This writes:

- `paperfetch_out/paperfetch_report.md`
- `paperfetch_out/paperfetch_report.inc`

The Markdown report is meant for direct reading. The INC report is meant for
spreadsheets and downstream tooling.

## Live API Checks

Live provider lookup is opt-in:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_cache \
  --rate-limit-seconds 0.05 \
  --outdir paperfetch_out
```

Use a real contact email for scholarly APIs. `--cache-dir` keeps repeat runs
faster and gentler on providers. `--rate-limit-seconds` is a light per-run
throttle between uncached live requests; increase it if a provider asks you to
slow down.

## Fetch PDFs

Fetch mode first checks the bibliography, then downloads only explicit PDF
candidate URLs discovered in source metadata:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  fetch references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_cache \
  --rate-limit-seconds 0.05 \
  --outdir paperfetch_out
```

Outputs include:

- `paperfetch_out/paperfetch_report.md`
- `paperfetch_out/paperfetch_report.inc`
- `paperfetch_out/manifest.inc`
- downloaded `*.pdf` files when candidate URLs are available and reachable

Entries without PDF candidates are recorded as `skipped`, not as validation
failures.

## Credential-Assisted Fetching

Credential-assisted fetching is local and opt-in. PaperFetch.jl never asks for
your username or password.

Supported runtime inputs:

- an EZproxy URL template, for example
  `https://proxy.example.edu/login?url={url}`;
- a local browser-exported Netscape-format `cookies.txt` file.

Example:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  fetch references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_cache \
  --rate-limit-seconds 0.05 \
  --ezproxy 'https://proxy.example.edu/login?url={url}' \
  --cookie-file /path/to/cookies.txt \
  --outdir paperfetch_out
```

Treat cookie files as login tokens. Do not commit, upload, email, or share them.
Check your library and publisher terms before downloading.

## Julia API

```julia
using PaperFetch

reports = check_bibliography("references.bib";
    email              = "you@example.edu",
    use_apis           = true,
    cache_dir          = ".paperfetch_cache",
    rate_limit_seconds = 0.05,
)

paths = write_reports(reports, "paperfetch_out")
paths[:markdown]
paths[:inc]

results, manifest = fetch_pdfs(reports, "paperfetch_out")
```

For deterministic offline runs, pass a fixture instead of live APIs:

```julia
reports = check_bibliography("examples/01_exact_article.bib";
    fixture = "examples/metadata_fixture.json",
    check = :none,
)
```

`check_bibliography` skips the key `anon` by default because that key is often
used for anonymized review placeholders. Pass `ignore_keys=nothing` to keep every
entry, or provide a custom set/list of keys to skip.

## Examples And Tests

The `examples/` directory contains small cases used by the test suite, covering
exact metadata, normalized text differences, missing/conflicting DOI fields,
web references, datasets, arXiv preprints, book chapters, online reports, and
plain DOI lists.

Run the default offline tests:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Manual online field tests live in `examples/online/` and are not run by default:

```bash
PAPERFETCH_ONLINE=true \
PAPERFETCH_EMAIL=your.email@example.edu \
julia --project=. test/online/runtests.jl
```

## Documentation

The documentation includes a quickstart, examples, API reference, and notes on
live providers, caching, rate limiting, and building a stand-alone executable:

https://mroughan.github.io/PaperFetch.jl/dev

Build docs locally with:

```bash
julia --project=docs -e '
  using Pkg
  Pkg.develop(PackageSpec(path=pwd()))
  Pkg.instantiate()
'
julia --project=docs docs/make.jl
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, test expectations,
provider guidelines, and pull request notes.

## Security

See [SECURITY.md](SECURITY.md). In short:

- do not put usernames or passwords in command-line arguments;
- keep cookie files local and private;
- do not commit API caches, downloaded PDFs, or private bibliographies;
- retrieve only material you are entitled to access.

## Citation

If PaperFetch.jl helps your work, please cite it using the metadata in
[CITATION.cff](CITATION.cff).

## AI Disclosure

This project has been built with help from AI coding agents. The package
structure and implementation were developed under user supervision with
user-provided architecture and guardrail instructions.
