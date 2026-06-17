# PaperFetch.jl

PaperFetch.jl helps validate BibTeX bibliographies against source metadata.
It writes review reports and optional fetch manifests; it does not edit the
input `.bib` file.

The package is built for small and medium bibliography review tasks, usually
10-100 references. It favors traceable evidence, cautious normalization, and
human-readable output over bulk harvesting.

## Quickstart

Activate and instantiate the package from the repository root:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

Run an offline check against the included fixture metadata:

```bash
julia --project=. -e 'using PaperFetch; PaperFetch.main()' -- \
  check examples/01_exact_article.bib \
  --fixture examples/metadata_fixture.json \
  --outdir paperfetch_out
```

This writes:

- `paperfetch_out/paperfetch_report.md`
- `paperfetch_out/paperfetch_report.inc`

The Markdown report is for direct human review. The INC report is a CSV-like
table with metadata, suitable for spreadsheets and downstream tooling.

## Julia API Tutorial

```julia
using PaperFetch

reports = check_bibliography(
    "examples/01_exact_article.bib";
    fixture = "examples/metadata_fixture.json",
    check = :none,
)

first(reports).confidence
```

Write both report formats:

```julia
paths = write_reports(reports, "paperfetch_out")
paths[:markdown]
paths[:inc]
```

Fetch mode uses explicit PDF candidate URLs from source metadata:

```julia
results, manifest = fetch_pdfs(reports, "paperfetch_out")
```

Entries without PDF candidates are recorded as `skipped`, not as validation
failures.

## Design Commitments

- BibTeX input is parsed, never rewritten.
- DOI and similar identifiers use exact normalized comparison.
- Titles, authors, pages, journal names, and other bibliographic text are
  compared with documented normalization.
- URL normalization preserves path and query case while canonicalizing DOI
  resolver links and HTTP(S) hosts.
- Author order is treated as meaningful. Reordered author lists are marked for
  manual review rather than accepted silently.
- Network API use is opt-in.
- Default tests and examples are offline and deterministic.
