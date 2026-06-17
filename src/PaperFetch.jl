module PaperFetch

using ArgParse
using BibParser
using Dates
using HTTP
using IncCSV
using JSON3
using SHA
using Unicode
using URIs

const DEFAULT_USER_AGENT =
    "PaperFetch.jl/$(pkgversion(@__MODULE__)) (https://github.com/mroughan/PaperFetch.jl)"

include("normalize.jl")
include("bib.jl")
include("identifiers.jl")
include("providers.jl")
include("compare.jl")
include("reports.jl")
include("fetch.jl")
include("cli.jl")

function ignored_key_set(ignore_keys)
    ignore_keys === nothing && return nothing
    ignore_keys isa AbstractString && return Set([String(ignore_keys)])
    return Set(String.(collect(ignore_keys)))
end

"""
    check_bibliography(path; providers=AbstractProvider[], fixture=nothing,
                       email="noreply@example.org", use_apis=false,
                       cache_dir=nothing, rate_limit_seconds=0.05,
                       ignore_keys=Set(["anon"]), check=:warn)

Read a bibliography, collect source metadata, and return one `EntryReport` per
entry.

Provider selection order:
1. A `FixtureProvider` is added when `fixture` is set.
2. Explicitly supplied `providers` are appended.
3. An `ApiProvider` is added when `use_apis=true`. It can query Crossref,
   OpenAlex, Unpaywall, DataCite, arXiv, Semantic Scholar, PubMed, CORE,
   Figshare, Open Library, Google Books, and URL landing pages as appropriate.
4. If still empty, a `CandidateProvider` is used as a read-only fallback.

Set `cache_dir` to a directory path to cache API responses between runs.
Set `rate_limit_seconds` to the minimum delay between uncached live API
requests made by the default `ApiProvider`. Set `ignore_keys=nothing` to keep
all entries, including review artifacts such as `anon`.

# Example

```julia
reports = check_bibliography("examples/01_exact_article.bib";
    fixture="examples/metadata_fixture.json", check=:none)
length(reports) == 1
```
"""
function check_bibliography(path::AbstractString;
        providers::Vector{<:AbstractProvider}  = AbstractProvider[],
        fixture::Union{Nothing,String}          = nothing,
        email::String                           = "noreply@example.org",
        use_apis::Bool                          = false,
        cache_dir::Union{Nothing,String}        = nothing,
        rate_limit_seconds::Real                = 0.05,
        ignore_keys                             = Set(["anon"]),
        check::Symbol                           = :warn)
    entries = read_items(path; check)
    if ignore_keys !== nothing
        ignored = ignored_key_set(ignore_keys)
        filter!(entry -> !(entry.key in ignored), entries)
    end
    active  = AbstractProvider[]
    fixture === nothing || push!(active, records_from_json(fixture))
    append!(active, providers)
    if use_apis
        push!(active, ApiProvider(email=email, cache_dir=cache_dir,
            rate_limit_seconds=Float64(rate_limit_seconds)))
    end
    isempty(active) && push!(active, CandidateProvider())
    return [compare_entry(entry, provider_sources(active, entry)) for entry in entries]
end

export BibEntry,
    WorkIdentifier,
    CandidateSource,
    SourceRecord,
    FieldComparison,
    EntryReport,
    FetchResult,
    read_bibtex,
    read_items,
    extract_identifiers,
    normalize_text,
    normalize_doi,
    normalize_url,
    compare_entry,
    check_bibliography,
    fetch_pdfs,
    write_reports,
    main

end
