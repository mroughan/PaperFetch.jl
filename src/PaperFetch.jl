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

export BibEntry,
    SourceRecord,
    FieldComparison,
    EntryReport,
    FetchResult,
    read_bibtex,
    read_items,
    normalize_text,
    normalize_doi,
    compare_entry,
    check_bibliography,
    fetch_pdfs,
    write_reports,
    main

const DEFAULT_USER_AGENT = "PaperFetch.jl/0.2 (https://github.com/mroughan/PaperFetch.jl)"

"""
    BibEntry(key, type, fields)

Stable internal representation of one BibTeX entry.

`fields` stores lower-case BibTeX-style field names mapped to string values.
The input file is never edited; `BibEntry` is only an analysis view.

# Example

```julia
entry = BibEntry("smith2020", "article", Dict("doi" => "10.1000/example"))
entry.key
```
"""
struct BibEntry
    key::String
    type::String
    fields::Dict{String,String}
end

"""
    SourceRecord(; provider, id="", title=nothing, authors=String[], year=nothing, doi=nothing,
                   url=nothing, journal=nothing, pages=nothing, publisher=nothing, pdf_url=nothing,
                   raw=Dict{String,Any}())

Metadata about a work returned by an API, fixture, or landing-page adapter.

# Example

```julia
source = SourceRecord(provider="fixture", doi="10.1000/example", title="Example")
source.provider
```
"""
Base.@kwdef struct SourceRecord
    provider::String
    id::String = ""
    title::Union{Nothing,String} = nothing
    authors::Vector{String} = String[]
    year::Union{Nothing,String} = nothing
    doi::Union{Nothing,String} = nothing
    url::Union{Nothing,String} = nothing
    journal::Union{Nothing,String} = nothing
    pages::Union{Nothing,String} = nothing
    publisher::Union{Nothing,String} = nothing
    pdf_url::Union{Nothing,String} = nothing
    raw::Dict{String,Any} = Dict{String,Any}()
end

"""
    FieldComparison(field, status, input, source, note)

Result of comparing one bibliography field with source metadata.

`status` is one of `:exact`, `:normalized`, `:equivalent`, `:missing_input`,
`:missing_source`, `:conflict`, or `:ambiguous`.

# Example

```julia
cmp = FieldComparison("doi", :exact, "10.1000/x", "10.1000/x", "same DOI")
cmp.status
```
"""
struct FieldComparison
    field::String
    status::Symbol
    input::Union{Nothing,String}
    source::Union{Nothing,String}
    note::String
end

"""
    EntryReport(entry, sources, comparisons, confidence, notes, pdf_candidates)

Review result for a single bibliography entry.

# Example

```julia
entry = BibEntry("x", "misc", Dict("title" => "Example"))
report = EntryReport(entry, SourceRecord[], FieldComparison[], 0.0, ["no source"], String[])
report.entry.key
```
"""
struct EntryReport
    entry::BibEntry
    sources::Vector{SourceRecord}
    comparisons::Vector{FieldComparison}
    confidence::Float64
    notes::Vector{String}
    pdf_candidates::Vector{String}
end

"""
    FetchResult(key, status, file, source_url, final_url, note, sha256, bytes)

Manifest record for one PDF fetch attempt.

# Example

```julia
result = FetchResult("x", "skipped", nothing, nothing, nothing, "no PDF", nothing, 0)
result.status
```
"""
struct FetchResult
    key::String
    status::String
    file::Union{Nothing,String}
    source_url::Union{Nothing,String}
    final_url::Union{Nothing,String}
    note::String
    sha256::Union{Nothing,String}
    bytes::Int
end

abstract type AbstractProvider end

struct FixtureProvider <: AbstractProvider
    bykey::Dict{String,Vector{SourceRecord}}
    bydoi::Dict{String,Vector{SourceRecord}}
end

Base.@kwdef struct ApiProvider <: AbstractProvider
    email::String = "noreply@example.org"
    user_agent::String = DEFAULT_USER_AGENT
    get_json::Function = default_get_json
end

struct CandidateProvider <: AbstractProvider end

clean_field_name(name) = lowercase(strip(String(name)))

function nonempty(value)
    value === nothing && return nothing
    text = strip(String(value))
    return isempty(text) ? nothing : text
end

function putfield!(fields::Dict{String,String}, name::AbstractString, value)
    text = nonempty(value)
    text === nothing && return fields
    fields[clean_field_name(name)] = text
    return fields
end

function bib_name(name)
    parts = String[]
    for field in (:first, :middle, :particle, :last, :junior)
        value = nonempty(getfield(name, field))
        value === nothing || push!(parts, value)
    end
    return join(parts, " ")
end

function bib_authors(names)
    values = String[]
    for name in names
        text = bib_name(name)
        isempty(text) || push!(values, text)
    end
    return join(values, " and ")
end

function entry_to_bibentry(entry)
    fields = Dict{String,String}()
    putfield!(fields, "title", entry.title)
    putfield!(fields, "author", bib_authors(entry.authors))
    putfield!(fields, "editor", bib_authors(entry.editors))
    putfield!(fields, "year", entry.date.year)
    putfield!(fields, "month", entry.date.month)
    putfield!(fields, "day", entry.date.day)
    putfield!(fields, "doi", entry.access.doi)
    putfield!(fields, "url", entry.access.url)
    putfield!(fields, "howpublished", entry.access.howpublished)
    putfield!(fields, "booktitle", entry.booktitle)
    putfield!(fields, "note", entry.note)
    putfield!(fields, "journal", entry.in.journal)
    putfield!(fields, "pages", entry.in.pages)
    putfield!(fields, "publisher", entry.in.publisher)
    putfield!(fields, "volume", entry.in.volume)
    putfield!(fields, "number", entry.in.number)
    putfield!(fields, "isbn", entry.in.isbn)
    putfield!(fields, "issn", entry.in.issn)
    putfield!(fields, "institution", entry.in.institution)
    putfield!(fields, "organization", entry.in.organization)
    putfield!(fields, "school", entry.in.school)
    putfield!(fields, "series", entry.in.series)
    putfield!(fields, "edition", entry.in.edition)
    putfield!(fields, "address", entry.in.address)
    putfield!(fields, "chapter", entry.in.chapter)
    putfield!(fields, "eprint", entry.eprint.eprint)
    putfield!(fields, "archiveprefix", entry.eprint.archive_prefix)
    putfield!(fields, "primaryclass", entry.eprint.primary_class)
    for (name, value) in entry.fields
        putfield!(fields, name, value)
    end
    if haskey(fields, "doi")
        fields["doi"] = normalize_doi(fields["doi"])
    end
    return BibEntry(String(entry.id), lowercase(String(entry.type)), fields)
end

"""
    read_bibtex(path; check=:warn)

Read a BibTeX file into `BibEntry` values using BibParser.jl.

# Example

```julia
entries = read_bibtex("examples/01_exact_article.bib"; check=:none)
length(entries) >= 1
```
"""
function read_bibtex(path::AbstractString; check=:warn)
    parsed = BibParser.parse_file(String(path); check)
    entries = BibEntry[]
    for entry in values(parsed)
        push!(entries, entry_to_bibentry(entry))
    end
    return entries
end

"""
    read_items(path; check=:warn)

Read bibliography input. BibTeX files are parsed with BibParser; plain text
files are interpreted as one DOI or URL per non-comment line.

# Example

```julia
items = read_items("examples/02_plain_dois.txt"; check=:none)
length(items) == 2
```
"""
function read_items(path::AbstractString; check=:warn)
    text = read(path, String)
    if occursin(r"@\w+\s*[\{\(]"i, text)
        return read_bibtex(path; check)
    end

    entries = BibEntry[]
    for (i, line) in enumerate(split(text, '\n'))
        item = strip(line)
        isempty(item) && continue
        startswith(item, "#") && continue
        fields = Dict{String,String}()
        if occursin(r"(?i)\b10\.\d{4,9}/", item)
            fields["doi"] = normalize_doi(item)
        elseif startswith(lowercase(item), "http://") || startswith(lowercase(item), "https://")
            fields["url"] = item
        else
            fields["title"] = item
        end
        push!(entries, BibEntry("item$(i)", "misc", fields))
    end
    return entries
end

"""
    normalize_doi(value)

Normalize a DOI to a lower-case bare DOI string.

# Example

```julia
normalize_doi("https://doi.org/10.1000/ABC") == "10.1000/abc"
```
"""
function normalize_doi(value::AbstractString)
    doi = strip(value)
    doi = replace(doi, r"(?i)^https?://(?:dx\.)?doi\.org/" => "")
    doi = replace(doi, r"(?i)^doi\s*:\s*" => "")
    doi = strip(doi)
    doi = replace(doi, r"\s+" => "")
    return lowercase(doi)
end

const LATEX_ACCENTS = Dict(
    "\\'a" => "a", "\\'e" => "e", "\\'i" => "i", "\\'o" => "o", "\\'u" => "u",
    "\\`a" => "a", "\\`e" => "e", "\\`i" => "i", "\\`o" => "o", "\\`u" => "u",
    "\\\"a" => "a", "\\\"e" => "e", "\\\"i" => "i", "\\\"o" => "o", "\\\"u" => "u",
    "\\~n" => "n", "\\c c" => "c", "\\aa" => "a", "\\ae" => "ae", "\\oe" => "oe",
)

function strip_latex(value::AbstractString)
    text = lowercase(value)
    text = replace(text, r"\{\\([`'\"^~=.uvHtcdb])\s*\{?([a-z])\}?\}" => s"\2")
    text = replace(text, r"\\([`'\"^~=.uvHtcdb])\s*\{?([a-z])\}?" => s"\2")
    for (src, dst) in LATEX_ACCENTS
        text = replace(text, src => dst)
    end
    text = replace(text, r"[{}]" => "")
    text = replace(text, r"\\[a-zA-Z]+" => "")
    return text
end

"""
    normalize_text(value)

Normalize bibliographic text for tolerant comparison.

The normalization removes common BibTeX braces and LaTeX accent commands,
applies Unicode normalization, lowercases, and collapses punctuation and
whitespace.

# Example

```julia
normalize_text("{Caf\\'e} Data") == "cafe data"
```
"""
function normalize_text(value::AbstractString)
    text = Unicode.normalize(strip_latex(value), stripmark=true, decompose=true)
    text = lowercase(text)
    text = replace(text, r"&" => " and ")
    text = replace(text, r"[^a-z0-9]+" => " ")
    text = replace(strip(text), r"\s+" => " ")
    return text
end

normalize_pages(value::AbstractString) = replace(strip(value), r"\s+" => "", r"-+" => "-")
function normalize_year(value::AbstractString)
    matched = match(r"\d{4}", value)
    return matched === nothing ? "" : matched.match
end

function normalize_authors(value::AbstractString)
    parts = split(value, r"\s+(?:and|&)\s+"i)
    clean = normalize_text.(parts)
    sort!(filter!(!isempty, clean))
    return join(clean, ";")
end

function value_from_source(source::SourceRecord, field::AbstractString)
    field == "title" && return source.title
    field == "doi" && return source.doi
    field == "url" && return source.url
    field == "journal" && return source.journal
    field == "pages" && return source.pages
    field == "publisher" && return source.publisher
    field == "year" && return source.year
    field == "author" && return isempty(source.authors) ? nothing : join(source.authors, " and ")
    return nothing
end

function compare_value(field::String, input::Union{Nothing,String}, source::Union{Nothing,String})
    input = nonempty(input)
    source = nonempty(source)
    input === nothing && source === nothing && return FieldComparison(field, :ambiguous, nothing, nothing, "no value available")
    input === nothing && return FieldComparison(field, :missing_input, nothing, source, "field is missing from BibTeX")
    source === nothing && return FieldComparison(field, :missing_source, input, nothing, "source metadata has no comparable value")

    if field == "doi"
        left = normalize_doi(input)
        right = normalize_doi(source)
        status = left == right ? :exact : :conflict
        note = left == right ? "normalized DOI is identical" : "DOI identifiers differ"
        return FieldComparison(field, status, input, source, note)
    elseif field == "pages"
        left = normalize_pages(input)
        right = normalize_pages(source)
        status = left == right ? (input == source ? :exact : :normalized) : :conflict
        note = left == right ? "page range matches after dash normalization" : "page ranges differ"
        return FieldComparison(field, status, input, source, note)
    elseif field == "year"
        left = normalize_year(input)
        right = normalize_year(source)
        status = !isempty(left) && left == right ? (input == source ? :exact : :normalized) : :conflict
        note = status in (:exact, :normalized) ? "year matches" : "years differ"
        return FieldComparison(field, status, input, source, note)
    elseif field == "author"
        left = normalize_authors(input)
        right = normalize_authors(source)
        status = left == right ? (input == source ? :exact : :equivalent) : :ambiguous
        note = left == right ? "authors are equivalent after name normalization" : "author strings require review"
        return FieldComparison(field, status, input, source, note)
    else
        left = normalize_text(input)
        right = normalize_text(source)
        status = if input == source
            :exact
        elseif left == right
            :normalized
        elseif occursin(left, right) || occursin(right, left)
            :equivalent
        else
            :conflict
        end
        note = status == :conflict ? "normalized text differs" : "text matches after accepted normalization"
        return FieldComparison(field, status, input, source, note)
    end
end

function comparison_score(comparisons)
    isempty(comparisons) && return 0.0
    weights = Dict(:exact => 1.0, :normalized => 0.92, :equivalent => 0.75,
        :missing_source => 0.45, :missing_input => 0.2, :ambiguous => 0.35, :conflict => 0.0)
    total = 0.0
    for cmp in comparisons
        total += get(weights, cmp.status, 0.0)
    end
    return round(total / length(comparisons); digits=3)
end

function source_identity(source::SourceRecord)
    source.doi !== nothing && return "doi:" * normalize_doi(source.doi)
    !isempty(source.id) && return source.provider * ":" * source.id
    source.url !== nothing && return "url:" * source.url
    source.title !== nothing && return "title:" * normalize_text(source.title)
    return source.provider
end

"""
    compare_entry(entry, sources; fields=["doi", "title", "author", "year", "journal", "pages", "publisher", "url"])

Compare one `BibEntry` with candidate source records and return an `EntryReport`.

# Example

```julia
entry = BibEntry("x", "article", Dict("doi" => "10.1000/x", "title" => "A"))
source = SourceRecord(provider="fixture", doi="10.1000/x", title="A")
compare_entry(entry, [source]).confidence == 1.0
```
"""
function compare_entry(entry::BibEntry, sources::Vector{SourceRecord};
        fields = ["doi", "title", "author", "year", "journal", "pages", "publisher", "url"])
    if isempty(sources)
        return EntryReport(entry, SourceRecord[], FieldComparison[], 0.0,
            ["no source metadata found"], String[])
    end

    best_source = first(sources)
    best_comparisons = FieldComparison[]
    best_score = -1.0
    for source in sources
        comparisons = FieldComparison[]
        for field in fields
            input_value = get(entry.fields, field, nothing)
            source_value = value_from_source(source, field)
            input_value === nothing && source_value === nothing && continue
            push!(comparisons, compare_value(field, input_value, source_value))
        end
        score = comparison_score(comparisons)
        if score > best_score
            best_score = score
            best_source = source
            best_comparisons = comparisons
        end
    end

    notes = String["best source: $(best_source.provider) ($(source_identity(best_source)))"]
    for cmp in best_comparisons
        cmp.status in (:conflict, :ambiguous, :missing_input) && push!(notes, "$(cmp.field): $(cmp.note)")
    end
    pdfs = unique(filter(!isnothing, [source.pdf_url for source in sources]))
    return EntryReport(entry, sources, best_comparisons, max(best_score, 0.0), notes, String.(pdfs))
end

function records_from_json(path::AbstractString)
    obj = JSON3.read(read(path, String))
    bykey = Dict{String,Vector{SourceRecord}}()
    bydoi = Dict{String,Vector{SourceRecord}}()
    rows = hasproperty(obj, :records) ? obj.records : obj
    for row in rows
        authors = hasproperty(row, :authors) ? String.(row.authors) : String[]
        record = SourceRecord(
            provider=String(get(row, :provider, "fixture")),
            id=String(get(row, :id, "")),
            title=optional_string(row, :title),
            authors=authors,
            year=optional_string(row, :year),
            doi=optional_string(row, :doi),
            url=optional_string(row, :url),
            journal=optional_string(row, :journal),
            pages=optional_string(row, :pages),
            publisher=optional_string(row, :publisher),
            pdf_url=optional_string(row, :pdf_url),
            raw=Dict{String,Any}())
        key = optional_string(row, :key)
        if key !== nothing
            push!(get!(bykey, key, SourceRecord[]), record)
        end
        if record.doi !== nothing
            push!(get!(bydoi, normalize_doi(record.doi), SourceRecord[]), record)
        end
    end
    return FixtureProvider(bykey, bydoi)
end

function optional_string(row, field::Symbol)
    hasproperty(row, field) || return nothing
    value = getproperty(row, field)
    value === nothing && return nothing
    text = strip(String(value))
    return isempty(text) ? nothing : text
end

function sources_for(provider::FixtureProvider, entry::BibEntry)
    sources = copy(get(provider.bykey, entry.key, SourceRecord[]))
    doi = get(entry.fields, "doi", nothing)
    if doi !== nothing
        append!(sources, get(provider.bydoi, normalize_doi(doi), SourceRecord[]))
    end
    return unique(sources)
end

function sources_for(::CandidateProvider, entry::BibEntry)
    sources = SourceRecord[]
    title = get(entry.fields, "title", nothing)
    doi = get(entry.fields, "doi", nothing)
    url = get(entry.fields, "url", nothing)
    if doi !== nothing || url !== nothing || title !== nothing
        push!(sources, SourceRecord(provider="input", id=entry.key, title=title, doi=doi, url=url))
    end
    return sources
end

function default_get_json(url::AbstractString; headers=Pair{String,String}[])
    response = HTTP.get(String(url), headers; redirect=true, status_exception=false, readtimeout=30)
    if !(200 <= response.status < 300)
        error("HTTP $(response.status) for $(url)")
    end
    return JSON3.read(String(response.body))
end

function sources_for(provider::ApiProvider, entry::BibEntry)
    doi = get(entry.fields, "doi", nothing)
    doi === nothing && return SourceRecord[]
    sources = SourceRecord[]
    append!(sources, crossref_records(provider, doi))
    append!(sources, openalex_records(provider, doi))
    append!(sources, unpaywall_records(provider, doi))
    return sources
end

function crossref_records(provider::ApiProvider, doi::AbstractString)
    url = "https://api.crossref.org/works/$(escapeuri(normalize_doi(doi)))"
    headers = ["User-Agent" => "PaperFetch.jl/0.2 (mailto:$(provider.email))"]
    try
        obj = provider.get_json(url; headers)
        msg = obj.message
        authors = String[]
        if hasproperty(msg, :author)
            for author in msg.author
                given = String(get(author, :given, ""))
                family = String(get(author, :family, ""))
                push!(authors, strip(join([given, family], " ")))
            end
        end
        year = nothing
        if hasproperty(msg, Symbol("published-print"))
            parts = getproperty(msg, Symbol("published-print"))[Symbol("date-parts")]
            year = string(parts[1][1])
        elseif hasproperty(msg, Symbol("published-online"))
            parts = getproperty(msg, Symbol("published-online"))[Symbol("date-parts")]
            year = string(parts[1][1])
        end
        title = hasproperty(msg, :title) && !isempty(msg.title) ? String(msg.title[1]) : nothing
        journal = hasproperty(msg, Symbol("container-title")) && !isempty(getproperty(msg, Symbol("container-title"))) ?
            String(getproperty(msg, Symbol("container-title"))[1]) : nothing
        pdf_url = nothing
        if hasproperty(msg, :link)
            for link in msg.link
                ctype = lowercase(String(get(link, Symbol("content-type"), "")))
                if occursin("pdf", ctype)
                    pdf_url = String(get(link, :URL, ""))
                    break
                end
            end
        end
        return [SourceRecord(provider="crossref", id=normalize_doi(doi), title=title, authors=authors,
            year=year, doi=optional_string(msg, :DOI), url=optional_string(msg, :URL),
            journal=journal, pages=optional_string(msg, :page),
            publisher=optional_string(msg, :publisher), pdf_url=pdf_url)]
    catch err
        return [SourceRecord(provider="crossref-error", id=normalize_doi(doi),
            doi=normalize_doi(doi), raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function openalex_records(provider::ApiProvider, doi::AbstractString)
    url = "https://api.openalex.org/works/doi:$(escapeuri(normalize_doi(doi)))?mailto=$(escapeuri(provider.email))"
    try
        obj = provider.get_json(url)
        authors = String[]
        if hasproperty(obj, :authorships)
            for authorship in obj.authorships
                hasproperty(authorship, :author) && push!(authors, String(get(authorship.author, Symbol("display_name"), "")))
            end
        end
        pdf_url = nothing
        if hasproperty(obj, :primary_location) && obj.primary_location !== nothing
            pdf_url = optional_string(obj.primary_location, :pdf_url)
        end
        if pdf_url === nothing && hasproperty(obj, :open_access) && obj.open_access !== nothing
            pdf_url = optional_string(obj.open_access, :oa_url)
        end
        return [SourceRecord(provider="openalex", id=String(get(obj, :id, "")),
            title=optional_string(obj, :title), authors=authors,
            year=hasproperty(obj, :publication_year) ? string(obj.publication_year) : nothing,
            doi=optional_string(obj, :doi), url=optional_string(obj, :doi), pdf_url=pdf_url)]
    catch err
        return [SourceRecord(provider="openalex-error", id=normalize_doi(doi),
            doi=normalize_doi(doi), raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function unpaywall_records(provider::ApiProvider, doi::AbstractString)
    url = "https://api.unpaywall.org/v2/$(escapeuri(normalize_doi(doi)))?email=$(escapeuri(provider.email))"
    try
        obj = provider.get_json(url)
        pdf_url = nothing
        landing = nothing
        if hasproperty(obj, :best_oa_location) && obj.best_oa_location !== nothing
            pdf_url = optional_string(obj.best_oa_location, :url_for_pdf)
            landing = optional_string(obj.best_oa_location, :url)
        end
        return [SourceRecord(provider="unpaywall", id=normalize_doi(doi),
            title=optional_string(obj, :title), doi=optional_string(obj, :doi),
            url=landing, pdf_url=pdf_url)]
    catch err
        return [SourceRecord(provider="unpaywall-error", id=normalize_doi(doi),
            doi=normalize_doi(doi), raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function provider_sources(providers, entry)
    sources = SourceRecord[]
    for provider in providers
        append!(sources, sources_for(provider, entry))
    end
    return unique(sources)
end

"""
    check_bibliography(path; providers=[CandidateProvider()], fixture=nothing, check=:warn)

Read a bibliography, collect source metadata, and return one `EntryReport` per
entry.

Set `fixture` to a JSON fixture file for offline deterministic checks.

# Example

```julia
reports = check_bibliography("examples/01_exact_article.bib";
    fixture="examples/metadata_fixture.json", check=:none)
length(reports) == 1
```
"""
function check_bibliography(path::AbstractString; providers=nothing, fixture=nothing,
        email::String="noreply@example.org", use_apis::Bool=false, check=:warn)
    entries = read_items(path; check)
    active = AbstractProvider[]
    fixture === nothing || push!(active, records_from_json(fixture))
    if providers !== nothing
        append!(active, providers)
    elseif use_apis
        push!(active, ApiProvider(email=email))
    end
    isempty(active) && push!(active, CandidateProvider())
    return [compare_entry(entry, provider_sources(active, entry)) for entry in entries]
end

function markdown_escape(value)
    value === nothing && return ""
    return replace(String(value), "|" => "\\|", "\n" => " ")
end

function write_markdown(path::AbstractString, reports::Vector{EntryReport})
    open(path, "w") do io
        println(io, "# PaperFetch Report\n")
        println(io, "Generated: $(Dates.now())\n")
        for report in reports
            println(io, "## $(report.entry.key)\n")
            println(io, "- Type: `$(report.entry.type)`")
            println(io, "- Confidence: $(report.confidence)")
            for note in report.notes
                println(io, "- Note: $(note)")
            end
            println(io, "\n| Field | Status | BibTeX | Source | Note |")
            println(io, "| --- | --- | --- | --- | --- |")
            for cmp in report.comparisons
                println(io, "| $(cmp.field) | $(cmp.status) | $(markdown_escape(cmp.input)) | $(markdown_escape(cmp.source)) | $(markdown_escape(cmp.note)) |")
            end
            if !isempty(report.pdf_candidates)
                println(io, "\nPDF candidates:")
                for url in report.pdf_candidates
                    println(io, "- $(url)")
                end
            end
            println(io)
        end
    end
    return path
end

function comparison_rows(reports::Vector{EntryReport})
    rows = NamedTuple[]
    for report in reports
        for cmp in report.comparisons
            push!(rows, (
                key=report.entry.key,
                type=report.entry.type,
                confidence=report.confidence,
                field=cmp.field,
                status=String(cmp.status),
                bibtex=something(cmp.input, ""),
                source=something(cmp.source, ""),
                note=cmp.note,
                providers=join([s.provider for s in report.sources], ";"),
            ))
        end
    end
    return rows
end

function write_inc(path::AbstractString, reports::Vector{EntryReport})
    rows = comparison_rows(reports)
    metadata = Dict(
        "title" => "PaperFetch bibliography validation report",
        "generated" => string(Dates.now()),
        "tool" => "PaperFetch.jl",
        "columns" => Dict(
            "key" => "BibTeX entry key",
            "type" => "BibTeX entry type",
            "confidence" => "Record-level confidence score from 0 to 1",
            "field" => "Compared field",
            "status" => "Comparison status",
            "bibtex" => "Input BibTeX value",
            "source" => "Source metadata value",
            "note" => "Human-readable comparison note",
            "providers" => "Source metadata providers consulted",
        ),
    )
    IncCSV.writeinc(path, rows; metadata)
    return path
end

"""
    write_reports(reports, outdir; basename="paperfetch_report")

Write Markdown and INC reports for `reports`.

# Example

```julia
entry = BibEntry("x", "misc", Dict("title" => "Example"))
report = EntryReport(entry, SourceRecord[], FieldComparison[], 0.0, String[], String[])
paths = write_reports([report], mktempdir())
haskey(paths, :markdown) && haskey(paths, :inc)
```
"""
function write_reports(reports::Vector{EntryReport}, outdir::AbstractString; basename::AbstractString="paperfetch_report")
    mkpath(outdir)
    md = write_markdown(joinpath(outdir, string(basename, ".md")), reports)
    inc = write_inc(joinpath(outdir, string(basename, ".inc")), reports)
    return Dict(:markdown => md, :inc => inc)
end

function read_cookie_file(path::Union{Nothing,String})
    path === nothing && return Dict{String,String}()
    cookies = Dict{String,String}()
    for line in eachline(path)
        startswith(line, "#") && continue
        parts = split(line, '\t')
        length(parts) < 7 && continue
        domain, name, value = parts[1], parts[6], parts[7]
        cookies[domain] = string(get(cookies, domain, ""), isempty(get(cookies, domain, "")) ? "" : "; ", name, "=", value)
    end
    return cookies
end

function cookie_for_url(cookies::Dict{String,String}, url::String)
    host = try
        URIs.URI(url).host
    catch
        nothing
    end
    host === nothing && return nothing
    values = String[]
    for (domain, cookie) in cookies
        cleaned = replace(domain, r"^\." => "")
        if host == cleaned || endswith(host, "." * cleaned)
            push!(values, cookie)
        end
    end
    return isempty(values) ? nothing : join(values, "; ")
end

function proxied_url(url::String, ezproxy::Union{Nothing,String})
    ezproxy === nothing && return url
    template = strip(ezproxy)
    isempty(template) && return url
    return occursin("{url}", template) ? replace(template, "{url}" => escapeuri(url)) : template * escapeuri(url)
end

function slugify(value::AbstractString; maxlen::Int=96)
    text = replace(normalize_text(value), r"[^a-z0-9]+" => "-")
    text = replace(text, r"^-+|-+$" => "")
    isempty(text) && return "untitled"
    return first(text, min(lastindex(text), maxlen))
end

function download_pdf(url::String, dest::String; cookies=Dict{String,String}(),
        ezproxy=nothing, timeout::Int=60, http_get=HTTP.get)
    actual = proxied_url(url, ezproxy)
    headers = ["User-Agent" => DEFAULT_USER_AGENT]
    cookie = cookie_for_url(cookies, actual)
    cookie === nothing || push!(headers, "Cookie" => cookie)
    response = http_get(actual, headers; redirect=true, readtimeout=timeout, status_exception=false)
    body = Vector{UInt8}(response.body)
    ctype = lowercase(String(HTTP.header(response, "Content-Type", "")))
    looks_pdf = occursin("pdf", ctype) || (length(body) >= 4 && body[1:4] == UInt8['%', 'P', 'D', 'F'])
    if !(200 <= response.status < 300)
        return false, actual, "HTTP $(response.status)", nothing, 0
    elseif !looks_pdf
        return false, actual, "not a PDF; content-type=$(ctype)", nothing, length(body)
    end
    write(dest, body)
    return true, actual, "downloaded", bytes2hex(sha256(body)), length(body)
end

function write_manifest(path::AbstractString, results::Vector{FetchResult})
    rows = [(
        key=r.key,
        status=r.status,
        file=something(r.file, ""),
        source_url=something(r.source_url, ""),
        final_url=something(r.final_url, ""),
        note=r.note,
        sha256=something(r.sha256, ""),
        bytes=r.bytes,
    ) for r in results]
    metadata = Dict(
        "title" => "PaperFetch PDF fetch manifest",
        "generated" => string(Dates.now()),
        "tool" => "PaperFetch.jl",
        "columns" => Dict(
            "key" => "BibTeX entry key",
            "status" => "downloaded, skipped, or failed",
            "file" => "Local PDF path when downloaded",
            "source_url" => "Candidate PDF URL",
            "final_url" => "URL after proxy template and redirects when known",
            "note" => "Fetch note",
            "sha256" => "SHA-256 hash of downloaded bytes",
            "bytes" => "Downloaded byte count",
        ),
    )
    IncCSV.writeinc(path, rows; metadata)
    return path
end

"""
    fetch_pdfs(reports, outdir; cookie_file=nothing, ezproxy=nothing)

Download PDF candidates from reports and write an INC manifest.

Only explicit PDF candidate URLs are attempted. Missing PDFs are recorded as
`skipped`, not as validation failures.

# Example

```julia
entry = BibEntry("x", "misc", Dict("title" => "No PDF"))
report = EntryReport(entry, SourceRecord[], FieldComparison[], 0.0, String[], String[])
results, manifest = fetch_pdfs([report], mktempdir())
results[1].status == "skipped"
```
"""
function fetch_pdfs(reports::Vector{EntryReport}, outdir::AbstractString;
        cookie_file::Union{Nothing,String}=nothing, ezproxy::Union{Nothing,String}=nothing,
        http_get=HTTP.get)
    mkpath(outdir)
    cookies = read_cookie_file(cookie_file)
    results = FetchResult[]
    for report in reports
        if isempty(report.pdf_candidates)
            push!(results, FetchResult(report.entry.key, "skipped", nothing, nothing, nothing,
                "no PDF candidate", nothing, 0))
            continue
        end
        downloaded = false
        basename = slugify(get(report.entry.fields, "title", report.entry.key))
        for (i, url) in enumerate(report.pdf_candidates)
            dest = joinpath(outdir, i == 1 ? "$(basename).pdf" : "$(basename)-$(i).pdf")
            ok, final_url, note, digest, bytes = download_pdf(url, dest; cookies, ezproxy, http_get)
            if ok
                push!(results, FetchResult(report.entry.key, "downloaded", dest, url, final_url, note, digest, bytes))
                downloaded = true
                break
            else
                push!(results, FetchResult(report.entry.key, "failed", nothing, url, final_url, note, digest, bytes))
            end
        end
        downloaded || nothing
    end
    manifest = write_manifest(joinpath(outdir, "manifest.inc"), results)
    return results, manifest
end

function parse_cli(args)
    settings = ArgParseSettings(description="Validate bibliographies and fetch accessible PDFs without editing BibTeX input.")
    @add_arg_table! settings begin
        "mode"
            help = "check or fetch"
            required = true
        "input"
            help = "BibTeX file or plain text DOI/URL list"
            required = true
        "--outdir"
            help = "Output directory"
            default = "paperfetch_out"
        "--fixture"
            help = "JSON metadata fixture for deterministic/offline runs"
        "--email"
            help = "Contact email for APIs"
            default = "noreply@example.org"
        "--use-apis"
            help = "Query Crossref, OpenAlex, and Unpaywall"
            action = :store_true
        "--cookie-file"
            help = "Optional local Netscape cookies.txt file for credential-assisted fetching"
        "--ezproxy"
            help = "Optional EZproxy template, for example https://proxy.example.edu/login?url={url}"
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
    mode = options["mode"]
    reports = check_bibliography(options["input"];
        fixture=options["fixture"], email=options["email"], use_apis=options["use-apis"], check=:warn)
    paths = write_reports(reports, options["outdir"])
    println("Wrote: $(paths[:markdown])")
    println("Wrote: $(paths[:inc])")
    if mode == "fetch"
        _, manifest = fetch_pdfs(reports, options["outdir"];
            cookie_file=options["cookie-file"], ezproxy=options["ezproxy"])
        println("Wrote: $(manifest)")
    elseif mode != "check"
        error("mode must be 'check' or 'fetch'")
    end
    return nothing
end

end
