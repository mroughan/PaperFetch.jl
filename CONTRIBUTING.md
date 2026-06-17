# Contributing To PaperFetch.jl

Thank you for helping improve PaperFetch.jl. The package is intended to make
bibliography checking more reliable without taking control away from the person
who owns the bibliography: it reads input, checks source metadata, and writes
reports, but it does not edit `.bib` files.

## Development Setup

From the repository root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Run the default test suite:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Build the documentation locally:

```bash
julia --project=docs -e '
  using Pkg
  Pkg.develop(PackageSpec(path=pwd()))
  Pkg.instantiate()
'
julia --project=docs docs/make.jl
```

The default tests are offline and deterministic. They should not require
network access, library credentials, browser cookies, or provider availability.

## Optional Online Field Tests

Online tests are intentionally separate because API responses and network
availability change over time:

```bash
PAPERFETCH_ONLINE=true \
PAPERFETCH_EMAIL=your.email@example.edu \
julia --project=. test/online/runtests.jl
```

Use a real contact email when exercising public scholarly APIs. Do not commit
API caches produced by online runs unless the file is explicitly designed as a
small deterministic fixture.

## Quality Checks

The GitHub workflows run the normal tests, documentation build, JET, and Aqua.
Before opening a substantial pull request, please run:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=docs docs/make.jl
```

For JET and Aqua locally, use temporary environments so quality tools do not
become package dependencies:

```bash
julia -e '
  using Pkg
  Pkg.activate(; temp=true)
  Pkg.develop(PackageSpec(path=pwd()))
  Pkg.add("JET")
  using JET, PaperFetch
  report = JET.report_package(PaperFetch; target_modules=(PaperFetch,))
  if !isempty(JET.get_reports(report))
      display(report)
      exit(1)
  end
'
```

```bash
julia -e '
  using Pkg
  Pkg.activate(; temp=true)
  Pkg.develop(PackageSpec(path=pwd()))
  Pkg.add("Aqua")
  using Aqua, PaperFetch
  Aqua.test_all(PaperFetch; ambiguities=false)
'
```

## Design Principles

- Do not mutate the input bibliography. Produce reports that a person, script,
  or separate AI-assisted editing task can use.
- Prefer source APIs over scraping whenever a suitable API exists.
- Treat metadata comparison as evidence, not authority. BibTeX can be correct
  without being byte-for-byte identical to provider metadata.
- Keep DOI, arXiv, PMID, ISBN, and URL extraction tolerant of common misplaced
  fields such as `note` and `howpublished`.
- Keep offline tests fast, stable, and representative of real bibliography
  mistakes.
- Treat online fetching and credential-assisted downloading as opt-in behavior.

## Adding Providers Or Lookup Logic

Provider code should:

- return `SourceRecord` values rather than editing entries directly;
- catch provider failures and return `*-error` records with useful diagnostics;
- use polite request headers and the configured contact email where APIs support
  it;
- support cacheable deterministic responses through `ApiProvider`;
- have offline tests using mocked JSON/XML/HTML responses.

When provider metadata disagrees with the bibliography, prefer a clear report
status over silent correction. Hard conflicts in title, author, identifiers, or
large year differences should be visible to the user.

## Adding Normalization

Normalization should be conservative and documented by tests. Good candidates
include:

- harmless BibTeX or LaTeX presentation differences;
- DOI URL variants such as `doi.org` and `dx.doi.org`;
- author initials versus full given names;
- Unicode accents versus LaTeX accent macros;
- page dash variants and case differences.

Do not normalize away meaningful bibliographic distinctions such as different
DOIs, different author surnames, or different editions of a book.

## Test Data And Generated Files

Small fixtures in `examples/` are welcome when they explain a behavior and are
used by tests or docs. Generated files should normally stay out of git,
including:

- `paperfetch_out/`
- `paperfetch_online_out/`
- `.paperfetch_cache/`
- `downloads/`
- `docs/build/`
- coverage files such as `*.cov` and `*.mem`

Never commit browser cookies, EZproxy URLs containing secrets, institutional
credentials, private PDFs, or private bibliography files.

## Documentation

Public API changes should include Julia docstrings and, when useful, a docs page
update. The docs are built with Documenter.jl:

```bash
julia --project=docs docs/make.jl
```

Keep examples copy-pasteable from the repository root.

## Pull Request Checklist

Before opening a pull request:

- run the default test suite;
- run the documentation build if docs or docstrings changed;
- add focused tests for new normalization, provider, fetch, or report behavior;
- keep unrelated formatting and generated-output churn out of the diff;
- update `CHANGELOG.md` for user-visible behavior changes;
- explain whether the change affects offline checks, online API checks, PDF
  fetching, or report output.
