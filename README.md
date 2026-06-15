# PaperFetch.jl

PaperFetch.jl helps validate and improve BibTeX bibliographies by checking
entries against source metadata and writing review reports. It does not edit
the input `.bib` file.

The package is designed for small and medium bibliography checks, typically
10-100 references, where traceable evidence and human review matter more than
bulk throughput.

## What It Does

- Parses BibTeX with BibParser.jl.
- Compares entries against source metadata from fixtures or optional APIs.
- Treats normalized bibliographic differences carefully, for example title
  case, page dash style, Unicode and LaTeX accents, and author formatting.
- Requires exact normalized matches for identifiers such as DOI.
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
julia --project=. src/cli.jl check examples/01_exact_article.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

Outputs:

- `paperfetch_out/paperfetch_report.md`
- `paperfetch_out/paperfetch_report.inc`

Live API mode is opt-in:

```bash
julia --project=. src/cli.jl check references.bib \
  --email your.email@example.edu \
  --use-apis \
  --outdir paperfetch_out
```

The API adapter currently queries Crossref, OpenAlex, and Unpaywall for entries
with DOIs. Provider APIs can change, so fixture-backed and cached workflows are
recommended for repeatable review.

## Fetch PDFs

Fetch mode first performs the bibliography check, then downloads only explicit
PDF candidate URLs found in source metadata:

```bash
julia --project=. src/cli.jl fetch examples/01_exact_article.bib \
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
julia --project=. src/cli.jl fetch references.bib \
  --email your.email@example.edu \
  --use-apis \
  --outdir paperfetch_out \
  --ezproxy 'https://proxy.example.edu/login?url={url}' \
  --cookie-file /path/to/cookies.txt
```

Treat cookie files as login tokens. Do not upload or share them.

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

## Security And Policy Notes

- Do not put usernames or passwords in command-line arguments.
- Keep cookie files local and private.
- Check library and publisher terms before downloading.
- Use small batches and polite API behavior.
- Retrieve only material you are entitled to access.

## Disclosure

This project has been built with help from AI coding agents. This rewrite was
implemented by Codex, an AI coding agent based on GPT-5, working in the local
repository with user-provided architecture and guardrail instructions. Other AI
agents may also have contributed to earlier starter code.
