# Online Field Test Examples

These examples use real DOI-backed open-access articles. They are intended for
manual online checks of Crossref, OpenAlex, and Unpaywall behavior.

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
  --outdir paperfetch_online_out
```

Fetch mode can be tried separately:

```bash
julia --project=. src/cli.jl fetch examples/online/field_tests.bib \
  --email your.email@example.edu \
  --use-apis \
  --outdir paperfetch_online_out
```

The fetch command only downloads explicit PDF candidates returned by metadata
providers. If a provider changes its response or a PDF URL is temporarily
unavailable, inspect the generated reports before treating that as a package
bug.
