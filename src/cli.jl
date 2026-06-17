function parse_cli(args)
    settings = ArgParseSettings(
        description = "Validate bibliographies and fetch accessible PDFs without editing BibTeX input.",
    )
    @add_arg_table! settings begin
        "mode"
            help     = "check or fetch"
            required = true
        "input"
            help     = "BibTeX file or plain text DOI/URL list"
            required = true
        "--outdir"
            help    = "Output directory"
            default = "paperfetch_out"
        "--report-basename"
            help = "Basename for Markdown and INC reports; defaults to the input file stem"
        "--fixture"
            help = "JSON metadata fixture for deterministic/offline runs"
        "--email"
            help    = "Contact email for APIs"
            default = "noreply@example.org"
        "--use-apis"
            help   = "Query live scholarly APIs and URL landing pages"
            action = :store_true
        "--cache-dir"
            help = "Directory for caching API responses between runs"
        "--rate-limit-seconds"
            help    = "Minimum delay between uncached live API requests"
            default = "0.05"
        "--ignore-keys"
            help    = "Comma-separated BibTeX keys to skip during checking"
            default = "anon"
        "--cookie-file"
            help = "Optional local Netscape cookies.txt file for credential-assisted fetching"
        "--ezproxy"
            help = "Optional EZproxy template, e.g. https://proxy.example.edu/login?url={url}"
    end
    return parse_args(args, settings)
end

"""
    main(args=ARGS)

Command-line entry point.

# Example

```julia
PaperFetch.main(["check", "examples/01_exact_article.bib", "--fixture", "examples/metadata_fixture.json", "--outdir", mktempdir()])
```
"""
function main(args=ARGS)
    options = parse_cli(args)
    mode    = options["mode"]
    if mode ∉ ("check", "fetch")
        throw(ArgumentError("mode must be 'check' or 'fetch'"))
    end
    rate_limit_seconds = parse(Float64, options["rate-limit-seconds"])
    ignore_keys = let text = strip(options["ignore-keys"])
        isempty(text) ? Set{String}() : Set(strip.(split(text, ",")))
    end
    report_basename = something(options["report-basename"],
        first(splitext(basename(options["input"]))))

    reports = check_bibliography(options["input"];
        fixture            = options["fixture"],
        email              = options["email"],
        use_apis           = options["use-apis"],
        cache_dir          = options["cache-dir"],
        rate_limit_seconds = rate_limit_seconds,
        ignore_keys        = ignore_keys,
        check              = :warn)
    paths = write_reports(reports, options["outdir"]; basename=report_basename)
    println("Wrote: $(paths[:markdown])")
    println("Wrote: $(paths[:inc])")

    if mode == "fetch"
        _, manifest = fetch_pdfs(reports, options["outdir"];
            cookie_file = options["cookie-file"],
            ezproxy     = options["ezproxy"])
        println("Wrote: $(manifest)")
    end
    return nothing
end
