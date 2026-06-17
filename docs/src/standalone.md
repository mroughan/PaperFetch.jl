# Stand-Alone Executable

PaperFetch.jl is primarily a Julia package and command-line tool, but it can be
bundled as a stand-alone application with
[PackageCompiler.jl](https://julialang.github.io/PackageCompiler.jl/stable/apps.html).
PackageCompiler apps are directories containing an executable plus the Julia
runtime, sysimage, packages, and artifacts needed by that executable.

The build is platform-specific. Build Linux binaries on Linux, macOS binaries on
macOS, and Windows binaries on Windows.

## Recommended Approach

Use a small wrapper package for the executable. This keeps PaperFetch.jl's library
API clean and gives PackageCompiler the `julia_main()::Cint` entry point it
expects.

From a directory outside the PaperFetch.jl repository:

```bash
julia -e 'using Pkg; Pkg.generate("PaperFetchApp")'
```

Edit `PaperFetchApp/Project.toml` so it depends on the local PaperFetch checkout:

```toml
[deps]
PaperFetch = "5ac78112-2af7-4d90-b07d-b58f2e7736b1"
```

Instantiate the wrapper project and develop PaperFetch into it:

```bash
julia --project=PaperFetchApp -e '
using Pkg
Pkg.develop(PackageSpec(path="/path/to/PaperFetch.jl"))
Pkg.instantiate()
'
```

Replace `PaperFetchApp/src/PaperFetchApp.jl` with:

```julia
module PaperFetchApp

import PaperFetch

function julia_main()::Cint
    try
        PaperFetch.main(ARGS)
        return 0
    catch err
        showerror(stderr, err)
        println(stderr)
        return 1
    end
end

end
```

Then build the app:

```bash
julia --project=PaperFetchApp -e '
using Pkg
Pkg.add("PackageCompiler")
using PackageCompiler
create_app("PaperFetchApp", "PaperFetchCompiled";
    executables = ["paperfetch" => "julia_main"],
)
'
```

The executable will be:

```bash
PaperFetchCompiled/bin/paperfetch
```

Run it like the normal command-line tool:

```bash
PaperFetchCompiled/bin/paperfetch check references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir paperfetch_cache \
  --rate-limit-seconds 0.05 \
  --outdir paperfetch_out
```

Fetch mode works the same way:

```bash
PaperFetchCompiled/bin/paperfetch fetch references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir paperfetch_cache \
  --rate-limit-seconds 0.05 \
  --cookie-file cookies.txt \
  --ezproxy 'https://proxy.example.edu/login?url={url}' \
  --outdir paperfetch_out
```

## Smoke Test Before Distribution

Before sharing the app, run a deterministic offline check:

```bash
PaperFetchCompiled/bin/paperfetch check \
  /path/to/PaperFetch.jl/examples/01_exact_article.bib \
  --fixture /path/to/PaperFetch.jl/examples/metadata_fixture.json \
  --outdir /tmp/paperfetch_smoke
```

Confirm that the app writes:

- `/tmp/paperfetch_smoke/paperfetch_report.md`
- `/tmp/paperfetch_smoke/paperfetch_report.inc`

Then run a small live check if the app is intended to use network APIs:

```bash
PaperFetchCompiled/bin/paperfetch check references.bib \
  --email your.email@example.edu \
  --use-apis \
  --cache-dir /tmp/paperfetch_cache \
  --rate-limit-seconds 0.05 \
  --outdir /tmp/paperfetch_live
```

## Precompilation Workload

PackageCompiler can use a workload script to compile common paths ahead of time.
For PaperFetch.jl, a useful first workload is an offline check plus report
generation:

```julia
using PaperFetch

repo = "/path/to/PaperFetch.jl"
reports = check_bibliography(
    joinpath(repo, "examples", "01_exact_article.bib");
    fixture = joinpath(repo, "examples", "metadata_fixture.json"),
    check = :none,
)
write_reports(reports, mktempdir())
```

Save that as `precompile_paperfetch.jl`, then pass it to `create_app`:

```julia
create_app("PaperFetchApp", "PaperFetchCompiled";
    executables = ["paperfetch" => "julia_main"],
    precompile_execution_file = "precompile_paperfetch.jl",
)
```

Do not put credentials, private bibliography paths, or private PDFs in a
precompile workload. Treat it as build input that may leave traces in build logs
or compiled artifacts.

## Distribution Notes

The compiled app directory is the distributable artifact. Archive the whole
directory rather than copying only the executable:

```bash
tar -czf PaperFetchCompiled-linux-x86_64.tar.gz PaperFetchCompiled
```

Important operational details:

- Build separately for each operating system and CPU family you want to support.
- Do not bundle cookie files, library credentials, API keys, private cache
  directories, or downloaded PDFs.
- Ask users to provide `--email`, `--cookie-file`, `--ezproxy`, `--cache-dir`,
  `--rate-limit-seconds`, and `--ignore-keys` at runtime when those settings
  matter for their institution or bibliography.
- Test with `--use-apis` on the target network if the app is expected to query
  Crossref, OpenAlex, Unpaywall, DataCite, arXiv, Semantic Scholar, PubMed,
  CORE, Figshare, Open Library, Google Books, or URL landing pages.
- Keep a deterministic fixture-backed smoke test in release notes so users can
  distinguish packaging failures from network/API failures.

## Alternative: Add `julia_main` To PaperFetch.jl

It is also possible to add the PackageCompiler entry point directly to
PaperFetch.jl:

```julia
function julia_main()::Cint
    try
        main(ARGS)
        return 0
    catch err
        showerror(stderr, err)
        println(stderr)
        return 1
    end
end
```

Then build from the package repository:

```julia
using PackageCompiler
create_app(".", "PaperFetchCompiled";
    executables = ["paperfetch" => "julia_main"],
)
```

The wrapper-package approach is usually cleaner because it keeps packaging
decisions separate from the library and test code.
