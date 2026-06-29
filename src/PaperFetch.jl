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

function progress_message(progress_io::Union{Nothing,IO}, message::AbstractString)
    progress_io === nothing && return nothing
    println(progress_io, message)
    flush(progress_io)
    return nothing
end

"""
    check_bibliography(path; providers=AbstractProvider[], fixture=nothing,
                       email="noreply@example.org", use_apis=false,
                       cache_dir=nothing, rate_limit_seconds=0.05,
                       ignore_keys=Set(["anon"]), check=:warn,
                       progress_io=nothing)

Read a bibliography, collect source metadata, and return one `EntryReport` per
entry.

The input file is not edited. Reports preserve the original BibTeX keys and are
intended to guide a human or a separate editing step.

Provider selection order:
1. A `FixtureProvider` is added when `fixture` is set.
2. Explicitly supplied `providers` are appended.
3. An `ApiProvider` is added when `use_apis=true`. It can query Crossref,
   OpenAlex, Unpaywall, DataCite, arXiv, Semantic Scholar, PubMed, CORE,
   Figshare, Open Library, Google Books, and URL landing pages as appropriate.
   For books without an ISBN, title/creator search results can supply an ISBN
   that is then used for ISBN-specific Open Library and Google Books lookups.
   GitHub repository URLs can use `CITATION.cff` as structured software
   citation metadata when such a file is available.
4. If still empty, a `CandidateProvider` is used as a read-only fallback that
   only echoes each entry's own title/doi/url back as its "source". This
   cannot detect an incorrect doi, title, or author. A `@warn` is emitted when
   this fallback is used, and affected `EntryReport`s carry a matching note.

Set `cache_dir` to a directory path to cache API responses between runs.
Set `rate_limit_seconds` to the minimum delay between uncached live API
requests made by the default `ApiProvider`. Set `ignore_keys=nothing` to keep
all entries, including review artifacts such as `anon`.
Set `progress_io` to an `IO` stream such as `stderr` to print entry-by-entry
progress; leave it as `nothing` for quiet programmatic use.

Identifier recovery is deliberately forgiving: DOI, arXiv, PMID, ISBN, and URL
values can be extracted from standard fields and common misplaced fields such as
`note` and `howpublished`. Later comparison remains explicit about conflicts.

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
        check::Symbol                           = :warn,
        progress_io::Union{Nothing,IO}          = nothing)
    progress_message(progress_io, "Reading bibliography: $(path)")
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
    if isempty(active)
        @warn "check_bibliography is running fully offline: no fixture, no explicit " *
              "providers, and use_apis=false. Entries will only be compared against " *
              "their own bibliography fields and cannot be validated against any " *
              "independent source metadata. Pass fixture=<path> for a deterministic " *
              "offline run, or use_apis=true to query live scholarly APIs."
        push!(active, CandidateProvider())
    end
    total = length(entries)
    progress_message(progress_io, "Checking $(total) entr$(total == 1 ? "y" : "ies")")
    reports = EntryReport[]
    for (i, entry) in enumerate(entries)
        progress_message(progress_io, "[$(i)/$(total)] $(entry.key): resolving source metadata")
        sources = provider_sources(active, entry)
        progress_message(progress_io, "[$(i)/$(total)] $(entry.key): comparing $(length(sources)) source candidate$(length(sources) == 1 ? "" : "s")")
        push!(reports, compare_entry(entry, sources))
    end
    progress_message(progress_io, "Finished checking $(total) entr$(total == 1 ? "y" : "ies")")
    return reports
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
