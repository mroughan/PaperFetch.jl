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
        "--fixture"
            help = "JSON metadata fixture for deterministic/offline runs"
        "--email"
            help    = "Contact email for APIs"
            default = "noreply@example.org"
        "--use-apis"
            help   = "Query Crossref, OpenAlex, Unpaywall, DataCite, and arXiv"
            action = :store_true
        "--cache-dir"
            help = "Directory for caching API responses between runs"
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
        println(stderr, "Error: mode must be 'check' or 'fetch'")
        exit(1)
    end

    reports = check_bibliography(options["input"];
        fixture   = options["fixture"],
        email     = options["email"],
        use_apis  = options["use-apis"],
        cache_dir = options["cache-dir"],
        check     = :warn)
    paths = write_reports(reports, options["outdir"])
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
