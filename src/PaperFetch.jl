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

"""
    check_bibliography(path; providers=AbstractProvider[], fixture=nothing,
                       email="noreply@example.org", use_apis=false,
                       cache_dir=nothing, check=:warn)

Read a bibliography, collect source metadata, and return one `EntryReport` per
entry.

Provider selection order:
1. A `FixtureProvider` is added when `fixture` is set.
2. Explicitly supplied `providers` are appended.
3. An `ApiProvider` (Crossref, OpenAlex, Unpaywall, DataCite, arXiv) is added
   when `use_apis=true` and no other providers have been supplied yet.
4. If still empty, a `CandidateProvider` is used as a read-only fallback.

Set `cache_dir` to a directory path to cache API responses between runs.

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
        check::Symbol                           = :warn)
    entries = read_items(path; check)
    active  = AbstractProvider[]
    fixture === nothing || push!(active, records_from_json(fixture))
    append!(active, providers)
    if isempty(active) && use_apis
        push!(active, ApiProvider(email=email, cache_dir=cache_dir))
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
    compare_entry,
    check_bibliography,
    fetch_pdfs,
    write_reports,
    main

end
