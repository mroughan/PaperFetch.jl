# PaperFetch.jl

[![CI](https://github.com/mroughan/PaperFetch.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/mroughan/PaperFetch.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/mroughan/PaperFetch.jl/branch/main/graph/badge.svg?token=kB2yzGMO9c)](https://codecov.io/gh/mroughan/PaperFetch.jl)
[![JET](https://github.com/mroughan/PaperFetch.jl/actions/workflows/jet.yml/badge.svg)](https://github.com/mroughan/PaperFetch.jl/actions/workflows/jet.yml)
[![Aqua](https://github.com/mroughan/PaperFetch.jl/actions/workflows/aqua.yml/badge.svg)](https://github.com/mroughan/PaperFetch.jl/actions/workflows/aqua.yml)
[![Documentation Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mroughan.github.io/PaperFetch.jl/stable)
[![Documentation Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://mroughan.github.io/PaperFetch.jl/dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PaperFetch.jl helps validate and improve BibTeX bibliographies by checking
entries against source metadata and writing review reports. It does not edit
the input `.bib` file.

The package is designed for small and medium bibliography checks, typically
10-100 references, where traceable evidence and human review matter more than
bulk throughput.

## What It Does

- Parses BibTeX with BibParser.jl.
- Extracts normalized identifiers (DOI, arXiv ID, ISBN, URL) from each entry.
- Compares entries against source metadata from fixtures or optional APIs
  (Crossref, OpenAlex, Unpaywall, DataCite, arXiv).
- Treats normalized bibliographic differences carefully, for example title
  case, page dash style, Unicode and LaTeX accents, and author formatting.
- Requires exact normalized matches for identifiers such as DOI.
- Caches API responses to a local directory for repeat runs.
- Writes a Markdown review report and an INC report using IncCSV.jl.
- Optionally downloads PDFs from explicit PDF candidate URLs and writes an INC
  manifest.

## Install

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

## Run The Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

The default tests are offline. They use the small examples and fixture metadata
in `examples/`.

## Check A Bibliography

Offline deterministic check using fixture metadata:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check examples/01_exact_article.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

Outputs:

- `paperfetch_out/paperfetch_report.md`
- `paperfetch_out/paperfetch_report.inc`

Live API mode is opt-in. Responses are cached in `--cache-dir` for repeat runs:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_cache \
  --outdir paperfetch_out
```

The API adapter queries Crossref, OpenAlex, Unpaywall, DataCite, and arXiv
for entries with matching identifiers.

## Fetch PDFs

Fetch mode first performs the bibliography check, then downloads only explicit
PDF candidate URLs found in source metadata:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  fetch examples/01_exact_article.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

Outputs include:

- `paperfetch_out/manifest.inc`
- downloaded `*.pdf` files when a candidate URL is available and reachable

Entries without PDF candidates are recorded as `skipped`, not treated as
validation failures.

## Controlled Local Credential Use

Credential-assisted fetching is opt-in and local-first. PaperFetch.jl never
asks for or stores passwords.

Supported inputs:

- an EZproxy URL template, for example
  `https://proxy.example.edu/login?url={url}`;
- a local browser-exported Netscape-format `cookies.txt` file.

Example:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  fetch references.bib \
  --email your.email@example.edu \
  --use-apis \
  --outdir paperfetch_out \
  --ezproxy 'https://proxy.example.edu/login?url={url}' \
  --cookie-file /path/to/cookies.txt
```

Treat cookie files as login tokens. Do not upload or share them.

## Julia API

```julia
using PaperFetch

# Offline check with a fixture file
reports = check_bibliography("references.bib";
    fixture = "examples/metadata_fixture.json")

# Live API check with caching
reports = check_bibliography("references.bib";
    email     = "you@example.edu",
    use_apis  = true,
    cache_dir = ".paperfetch_cache")

# Write reports
write_reports(reports, "paperfetch_out")

# Fetch PDFs
fetch_pdfs(reports, "paperfetch_out")
```

## Examples

The `examples/` directory contains small cases used by the test suite:

- exact article metadata;
- title case and page-range normalization;
- LaTeX accent normalization;
- missing DOI;
- conflicting DOI;
- online documentation;
- dataset reference;
- arXiv-style preprint;
- book chapter;
- online report without a PDF;
- plain DOI list input.

Manual online field-test examples live in `examples/online/`. They use real
DOI-backed open-access articles and are not run by default:

```bash
PAPERFETCH_ONLINE=true \
PAPERFETCH_EMAIL=your.email@example.edu \
julia --project=. test/online/runtests.jl
```

## Security And Policy Notes

- Do not put usernames or passwords in command-line arguments.
- Keep cookie files local and private.
- Check library and publisher terms before downloading.
- Use small batches and polite API behavior.
- Retrieve only material you are entitled to access.

## Disclosure

This project has been built with help from AI coding agents. The package
structure and initial implementation were created by AI agents including Codex
(GPT-5) and Claude (claude-sonnet-4-6, Anthropic). Other AI agents may also
have contributed to the code. All AI contributions were made under user
supervision with user-provided architecture and guardrail instructions.
