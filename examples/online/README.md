# Online Field Test Examples

These examples use real DOI-backed open-access articles. They are intended for
manual online checks of Crossref, OpenAlex, Unpaywall, DataCite, Semantic
Scholar, PubMed, CORE, Figshare, and URL landing-page behavior as applicable to
the entries.

They are deliberately separate from the default examples because live API
behavior can change and network availability is not deterministic.

Run the manual online tests from the repository root:

```bash
PAPERFETCH_ONLINE=true \
PAPERFETCH_EMAIL=your.email@example.edu \
julia --project=. test/online/runtests.jl
```

Or run the CLI directly:

```bash
julia --project=. src/cli.jl check examples/online/field_tests.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_online_cache \
  --rate-limit-seconds 0.05 \
  --outdir paperfetch_online_out
```

Fetch mode can be tried separately:

```bash
julia --project=. src/cli.jl fetch examples/online/field_tests.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir .paperfetch_online_cache \
  --rate-limit-seconds 0.05 \
  --outdir paperfetch_online_out
```

The fetch command only downloads explicit PDF candidates returned by metadata
providers. If a provider changes its response or a PDF URL is temporarily
unavailable, inspect `manifest.md` and the generated reports before treating
that as a package bug.

CLI report filenames default to the input stem, so these commands write
`paperfetch_online_out/field_tests.md` and
`paperfetch_online_out/field_tests.inc` unless `--report-basename` is supplied.
