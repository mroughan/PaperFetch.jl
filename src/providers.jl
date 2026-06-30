"""
    SourceRecord(; provider, id="", title=nothing, authors=String[], year=nothing, doi=nothing,
                   url=nothing, journal=nothing, pages=nothing, publisher=nothing, pdf_url=nothing,
                   raw=Dict{String,Any}())

Metadata about a work returned by an API, fixture, or landing-page adapter.

`authors` stores the creator list returned by the provider. For edited books
and book chapters this may be compared with a BibTeX `editor` field when the
entry has no `author` field.

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
    CandidateSource(record, identifier)

A possible authority for a bibliography entry, recording which
`WorkIdentifier` was used to find it.

# Example

```julia
r = SourceRecord(provider="test", id="x")
id = WorkIdentifier(:doi, "10.1000/x")
cs = CandidateSource(r, id)
cs.identifier.kind == :doi
```
"""
struct CandidateSource
    record::SourceRecord
    identifier::WorkIdentifier
end

abstract type AbstractProvider end

struct FixtureProvider <: AbstractProvider
    bykey::Dict{String,Vector{SourceRecord}}
    bydoi::Dict{String,Vector{SourceRecord}}
end

Base.@kwdef mutable struct ApiProvider <: AbstractProvider
    email::String = "noreply@example.org"
    user_agent::String = DEFAULT_USER_AGENT
    get_json::Function = default_get_json
    get_text::Function = default_get_text
    cache_dir::Union{Nothing,String} = nothing
    rate_limit_seconds::Float64 = 0.0
    last_request_ns::Base.RefValue{UInt64} = Ref(UInt64(0))
end

struct CandidateProvider <: AbstractProvider end

function default_get_json(url::AbstractString; headers=Pair{String,String}[])
    response = HTTP.get(String(url), headers; redirect=true, status_exception=false, read_idle_timeout=30)
    if !(200 <= response.status < 300)
        error("HTTP $(response.status) for $(url)")
    end
    return JSON3.read(String(response.body))
end

function default_get_text(url::AbstractString; headers=Pair{String,String}[])
    response = HTTP.get(String(url), headers; redirect=true, status_exception=false, read_idle_timeout=30)
    if !(200 <= response.status < 300)
        error("HTTP $(response.status) for $(url)")
    end
    return String(response.body)
end

function cache_key(url::AbstractString, headers)
    parts = [String(url)]
    for header in sort!(collect(headers); by=h -> lowercase(String(first(h))))
        push!(parts, lowercase(String(first(header))) * ": " * String(last(header)))
    end
    return bytes2hex(sha256(join(parts, "\n")))
end

function atomic_write(path::AbstractString, data)
    dir = dirname(path)
    mkpath(dir)
    tmp, io = mktemp(dir)
    try
        write(io, data)
        close(io)
        mv(tmp, path; force=true)
    catch
        isopen(io) && close(io)
        isfile(tmp) && rm(tmp; force=true)
        rethrow()
    end
    return path
end

function throttle!(provider::ApiProvider)
    interval = provider.rate_limit_seconds
    interval <= 0 && return nothing
    last = provider.last_request_ns[]
    if last != 0
        elapsed = (time_ns() - last) / 1.0e9
        delay = interval - elapsed
        delay > 0 && sleep(delay)
    end
    provider.last_request_ns[] = time_ns()
    return nothing
end

function provider_get_json(provider::ApiProvider, url::String; headers=Pair{String,String}[])
    cache_dir = provider.cache_dir
    if cache_dir === nothing
        throttle!(provider)
        return provider.get_json(url; headers)
    end
    key = cache_key(url, headers)
    path = joinpath(cache_dir, key * ".json")
    metapath = joinpath(cache_dir, key * ".meta.json")
    if isfile(path)
        return JSON3.read(read(path, String))
    end
    throttle!(provider)
    result = provider.get_json(url; headers)
    atomic_write(path, JSON3.write(result))
    atomic_write(metapath, JSON3.write(Dict(
        "url" => url,
        "headers" => Dict(String(first(h)) => String(last(h)) for h in headers),
        "cached_at" => string(Dates.now()),
        "format" => "json",
    )))
    return result
end

function provider_get_text(provider::ApiProvider, url::String; headers=Pair{String,String}[])
    cache_dir = provider.cache_dir
    if cache_dir === nothing
        throttle!(provider)
        return provider.get_text(url; headers)
    end
    key = cache_key(url, headers)
    path = joinpath(cache_dir, key * ".txt")
    metapath = joinpath(cache_dir, key * ".meta.json")
    if isfile(path)
        return read(path, String)
    end
    throttle!(provider)
    result = provider.get_text(url; headers)
    atomic_write(path, result)
    atomic_write(metapath, JSON3.write(Dict(
        "url" => url,
        "headers" => Dict(String(first(h)) => String(last(h)) for h in headers),
        "cached_at" => string(Dates.now()),
        "format" => "text",
    )))
    return result
end

function optional_string(row, field::Symbol)
    hasproperty(row, field) || return nothing
    value = getproperty(row, field)
    value === nothing && return nothing
    text = strip(String(value))
    return isempty(text) ? nothing : text
end

function records_from_json(path::AbstractString)
    obj = JSON3.read(read(path, String))
    bykey = Dict{String,Vector{SourceRecord}}()
    bydoi = Dict{String,Vector{SourceRecord}}()
    rows = hasproperty(obj, :records) ? obj.records : obj
    rows === nothing && return FixtureProvider(bykey, bydoi)
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

function sources_for(provider::FixtureProvider, entry::BibEntry)
    sources = copy(get(provider.bykey, entry.key, SourceRecord[]))
    for identifier in extract_identifiers(entry)
        identifier.kind == :doi || continue
        for rec in get(provider.bydoi, normalize_doi(identifier.value), SourceRecord[])
            rec in sources || push!(sources, rec)
        end
    end
    return sources
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

function sources_for(provider::ApiProvider, entry::BibEntry)
    ids = extract_identifiers(entry)
    sources = SourceRecord[]
    seen = Set{String}()
    for id in ids
        if id.kind == :doi
            for rec in crossref_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in openalex_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in unpaywall_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in datacite_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in semantic_scholar_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in pubmed_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in core_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in figshare_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
        elseif id.kind == :arxiv
            for rec in arxiv_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
        elseif id.kind == :pmid
            for rec in pubmed_pmid_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
        elseif id.kind == :isbn
            for rec in openlibrary_isbn_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in google_books_records(provider, "isbn:" * id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
        elseif id.kind == :url
            for rec in url_records(provider, id.value, entry)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
        end
    end
    usable = filter(!source_is_error, sources)
    # An identifier such as a DOI can resolve successfully yet point at the
    # wrong work (e.g. a mistyped or swapped DOI). When every usable record
    # found via explicit identifiers hard-mismatches the entry's title or
    # author, fall back to a title/author search so a correctly-identified
    # source with a different identifier can still be found and reported.
    identifier_lookup_unreliable = !isempty(usable) &&
        all(rec -> identifier_source_conflicts(entry, rec), usable)
    if isempty(usable) || identifier_lookup_unreliable
        for rec in title_search_records(provider, entry)
            key = rec.provider * ":" * source_identity(rec)
            key in seen || (push!(seen, key); push!(sources, rec))
        end
    end
    if entry.type in ("book", "inbook", "booklet", "manual", "proceedings") &&
            !any(id -> id.kind == :isbn, ids)
        for isbn in discovered_isbns(sources)
            for rec in openlibrary_isbn_records(provider, isbn)
                key = rec.provider * ":" * isbn
                key in seen || (push!(seen, key); push!(sources, rec))
            end
            for rec in google_books_records(provider, "isbn:" * isbn)
                key = rec.provider * ":" * isbn
                key in seen || (push!(seen, key); push!(sources, rec))
            end
        end
    end
    return sources
end

function discovered_isbns(sources::Vector{SourceRecord})
    isbns = String[]
    for source in sources
        raw_isbn = get(source.raw, "isbn", nothing)
        raw_isbn === nothing && continue
        values = raw_isbn isa AbstractVector ? raw_isbn : [raw_isbn]
        for value in values
            clean = replace(String(value), r"[^0-9Xx]" => "")
            isempty(clean) || clean in isbns || push!(isbns, clean)
        end
    end
    return isbns
end

"""
    identifier_source_conflicts(entry, source)

Return `true` when `source` (typically found by resolving an explicit
identifier such as a DOI) has a title or author that hard-mismatches `entry`,
or a publication year far enough away to indicate a different edition.

This reuses the same field comparisons as [`compare_entry`](@ref) so the
"does this look like the same work" judgement is made consistently whether the
mismatch is caught at provider-selection time or at report time.
"""
function identifier_source_conflicts(entry::BibEntry, source::SourceRecord)
    comparisons = FieldComparison[]
    for field in ("title", "author")
        input_value  = value_from_entry(entry, field)
        source_value = value_from_source(source, field)
        input_value === nothing && source_value === nothing && continue
        push!(comparisons, compare_value(field, input_value, source_value))
    end
    return source_hard_mismatch(entry, source, comparisons)
end

function deduplicate_sources(sources::Vector{SourceRecord})
    unique_sources = SourceRecord[]
    seen = Set{String}()
    for source in sources
        key = source.provider * ":" * source_identity(source)
        key in seen && continue
        push!(seen, key)
        push!(unique_sources, source)
    end
    return unique_sources
end

function provider_sources(providers, entry)
    sources = SourceRecord[]
    for provider in providers
        append!(sources, sources_for(provider, entry))
    end
    return deduplicate_sources(sources)
end

# ─── API adapters ────────────────────────────────────────────────────────────

doi_api_path(doi::AbstractString) = replace(escapeuri(normalize_doi(doi)), "%2F" => "/", "%2f" => "/")

function crossref_records(provider::ApiProvider, doi::AbstractString)
    url = "https://api.crossref.org/works/$(doi_api_path(doi))"
    headers = ["User-Agent" => "$(provider.user_agent) (mailto:$(provider.email))"]
    try
        obj = provider_get_json(provider, url; headers)
        msg = obj.message
        authors = String[]
        if hasproperty(msg, :author)
            for author in msg.author
                given = optional_string(author, :given)
                family = optional_string(author, :family)
                parts = filter(!isempty, [something(given, ""), something(family, "")])
                isempty(parts) || push!(authors, join(parts, " "))
            end
        end
        year = nothing
        for date_field in (Symbol("published-print"), Symbol("published-online"), :issued)
            if hasproperty(msg, date_field)
                parts = getproperty(msg, date_field)[Symbol("date-parts")]
                if isempty(parts) || isempty(parts[1])
                    continue
                end
                year = string(parts[1][1])
                break
            end
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
        source_doi = optional_string(msg, :DOI)
        source_url = hasproperty(msg, :URL) ? optional_string(msg, :URL) : nothing
        return [SourceRecord(provider="crossref", id=normalize_doi(doi), title=title,
            authors=authors, year=year, doi=source_doi, url=source_url,
            journal=journal, pages=optional_string(msg, :page),
            publisher=optional_string(msg, :publisher), pdf_url=pdf_url)]
    catch err
        return [SourceRecord(provider="crossref-error", id=normalize_doi(doi),
            doi=normalize_doi(doi), raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function openalex_records(provider::ApiProvider, doi::AbstractString)
    url = "https://api.openalex.org/works/doi:$(doi_api_path(doi))?mailto=$(escapeuri(provider.email))"
    try
        obj = provider_get_json(provider, url)
        authors = String[]
        if hasproperty(obj, :authorships)
            for authorship in obj.authorships
                hasproperty(authorship, :author) && push!(authors, String(get(authorship.author, Symbol("display_name"), "")))
            end
        end
        pdf_url = nothing
        landing_url = nothing
        if hasproperty(obj, :primary_location) && obj.primary_location !== nothing
            pdf_url = optional_string(obj.primary_location, :pdf_url)
            landing_url = optional_string(obj.primary_location, :landing_page_url)
        end
        if pdf_url === nothing && hasproperty(obj, :open_access) && obj.open_access !== nothing
            pdf_url = optional_string(obj.open_access, :oa_url)
        end
        source_doi = optional_string(obj, :doi)
        if landing_url === nothing && source_doi !== nothing
            landing_url = "https://doi.org/" * normalize_doi(source_doi)
        end
        return [SourceRecord(provider="openalex", id=String(get(obj, :id, "")),
            title=optional_string(obj, :title), authors=authors,
            year=hasproperty(obj, :publication_year) ? string(obj.publication_year) : nothing,
            doi=source_doi, url=landing_url, pdf_url=pdf_url)]
    catch err
        return [SourceRecord(provider="openalex-error", id=normalize_doi(doi),
            doi=normalize_doi(doi), raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function unpaywall_records(provider::ApiProvider, doi::AbstractString)
    url = "https://api.unpaywall.org/v2/$(doi_api_path(doi))?email=$(escapeuri(provider.email))"
    try
        obj = provider_get_json(provider, url)
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

function datacite_records(provider::ApiProvider, doi::AbstractString)
    clean = normalize_doi(doi)
    url = "https://api.datacite.org/dois/$(doi_api_path(clean))"
    try
        obj = provider_get_json(provider, url)
        attrs = obj.data.attributes
        authors = String[]
        if hasproperty(attrs, :creators)
            for creator in attrs.creators
                name = get(creator, :name, nothing)
                name !== nothing && push!(authors, String(name))
            end
        end
        year = hasproperty(attrs, :publicationYear) && attrs.publicationYear !== nothing ?
            string(attrs.publicationYear) : nothing
        title = nothing
        if hasproperty(attrs, :titles) && !isempty(attrs.titles)
            title = optional_string(first(attrs.titles), :title)
        end
        return [SourceRecord(provider="datacite", id=clean, title=title, authors=authors,
            year=year, doi=clean, publisher=optional_string(attrs, :publisher))]
    catch err
        return [SourceRecord(provider="datacite-error", id=clean, doi=clean,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function arxiv_year_from_xml(content::AbstractString)
    for tag in ("updated", "published")
        m = match(Regex("<$(tag)>(\\d{4})"), content)
        capture = m === nothing ? nothing : m.captures[1]
        capture !== nothing && return String(capture)
    end
    return nothing
end

function arxiv_records(provider::ApiProvider, arxiv_id::AbstractString)
    base_id = replace(strip(arxiv_id), r"v\d+$" => "")
    url = "https://export.arxiv.org/api/query?id_list=$(escapeuri(base_id))"
    headers = ["User-Agent" => provider.user_agent]
    try
        body = provider_get_text(provider, url; headers)
        # Extract entry-level title (skip the feed <title> by anchoring to <entry>)
        title = let m = match(r"<entry>.*?<title[^>]*>(.*?)</title>"s, body)
            capture = m === nothing ? nothing : m.captures[1]
            capture === nothing ? nothing : replace(strip(capture), r"\s+" => " ")
        end
        authors = [strip(m.match) for m in eachmatch(r"(?<=<name>)[^<]+", body)]
        year = arxiv_year_from_xml(body)
        raw_doi = let m = match(r"<arxiv:doi[^>]*>([^<]+)</arxiv:doi>", body)
            capture = m === nothing ? nothing : m.captures[1]
            capture === nothing ? nothing : normalize_doi(capture)
        end
        pdf_url = "https://arxiv.org/pdf/$(base_id)"
        abs_url = "https://arxiv.org/abs/$(base_id)"
        return [SourceRecord(provider="arxiv", id=base_id, title=title, authors=authors,
            year=year, doi=raw_doi, url=abs_url, pdf_url=pdf_url)]
    catch err
        return [SourceRecord(provider="arxiv-error", id=strip(arxiv_id),
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function title_author_query(entry::BibEntry)
    title = get(entry.fields, "title", nothing)
    title === nothing && return nothing
    clean_title = normalize_text(title)
    isempty(clean_title) && return nothing
    creator = get(entry.fields, "author", get(entry.fields, "editor", ""))
    surnames = author_surnames(creator)
    query = isempty(surnames) ? clean_title : clean_title * " " * join(surnames, " ")
    return strip(query)
end

function title_query(entry::BibEntry)
    title = get(entry.fields, "title", nothing)
    title === nothing && return nothing
    clean = normalize_text(title)
    return isempty(clean) ? nothing : clean
end

function title_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    sources = SourceRecord[]
    if entry.type in ("book", "inbook", "booklet", "manual", "proceedings")
        append!(sources, openlibrary_search_records(provider, entry))
        append!(sources, google_books_records(provider, query))
    else
        append!(sources, crossref_search_records(provider, entry))
        append!(sources, openalex_search_records(provider, entry))
        append!(sources, arxiv_search_records(provider, entry))
        append!(sources, semantic_scholar_search_records(provider, entry))
        append!(sources, pubmed_search_records(provider, entry))
        append!(sources, core_search_records(provider, entry))
        append!(sources, figshare_search_records(provider, entry))
    end
    return sources
end

function crossref_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    url = "https://api.crossref.org/works?query.bibliographic=$(escapeuri(query))&rows=3"
    headers = ["User-Agent" => "$(provider.user_agent) (mailto:$(provider.email))"]
    try
        obj = provider_get_json(provider, url; headers)
        items = obj.message.items
        records = SourceRecord[]
        for item in items
            title = hasproperty(item, :title) && !isempty(item.title) ? String(item.title[1]) : nothing
            title === nothing && continue
            authors = String[]
            if hasproperty(item, :author)
                for author in item.author
                    given = optional_string(author, :given)
                    family = optional_string(author, :family)
                    parts = filter(!isempty, [something(given, ""), something(family, "")])
                    isempty(parts) || push!(authors, join(parts, " "))
                end
            end
            journal = hasproperty(item, Symbol("container-title")) && !isempty(getproperty(item, Symbol("container-title"))) ?
                String(getproperty(item, Symbol("container-title"))[1]) : nothing
            push!(records, SourceRecord(provider="crossref-search", id=String(get(item, :DOI, "")),
                title=title, authors=authors, doi=optional_string(item, :DOI),
                url=optional_string(item, :URL), journal=journal,
                pages=optional_string(item, :page), publisher=optional_string(item, :publisher)))
        end
        return records
    catch err
        return [SourceRecord(provider="crossref-search-error", id=query,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function openalex_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    url = "https://api.openalex.org/works?search=$(escapeuri(query))&per-page=3&mailto=$(escapeuri(provider.email))"
    try
        obj = provider_get_json(provider, url)
        records = SourceRecord[]
        for item in obj.results
            authors = String[]
            if hasproperty(item, :authorships)
                for authorship in item.authorships
                    hasproperty(authorship, :author) && push!(authors, String(get(authorship.author, Symbol("display_name"), "")))
                end
            end
            pdf_url = nothing
            landing_url = nothing
            if hasproperty(item, :primary_location) && item.primary_location !== nothing
                pdf_url = optional_string(item.primary_location, :pdf_url)
                landing_url = optional_string(item.primary_location, :landing_page_url)
            end
            push!(records, SourceRecord(provider="openalex-search", id=String(get(item, :id, "")),
                title=optional_string(item, :title), authors=authors,
                year=hasproperty(item, :publication_year) ? string(item.publication_year) : nothing,
                doi=optional_string(item, :doi), url=landing_url, pdf_url=pdf_url))
        end
        return records
    catch err
        return [SourceRecord(provider="openalex-search-error", id=query,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function arxiv_search_records(provider::ApiProvider, entry::BibEntry)
    title = title_query(entry)
    title === nothing && return SourceRecord[]
    url = "https://export.arxiv.org/api/query?search_query=ti:$(escapeuri(title))&start=0&max_results=3"
    try
        body = provider_get_text(provider, url; headers=["User-Agent" => provider.user_agent])
        records = SourceRecord[]
        for m in eachmatch(r"<entry>(.*?)</entry>"s, body)
            chunk = m.captures[1]
            chunk === nothing && continue
            id_match = match(r"<id>https?://arxiv\.org/abs/([^<]+)</id>", chunk)
            id_capture = id_match === nothing ? nothing : id_match.captures[1]
            id = id_capture === nothing ? "" : strip(id_capture)
            title_match = match(r"<title[^>]*>(.*?)</title>"s, chunk)
            title_capture = title_match === nothing ? nothing : title_match.captures[1]
            title2 = title_capture === nothing ? nothing : replace(strip(title_capture), r"\s+" => " ")
            authors = [strip(x.match) for x in eachmatch(r"(?<=<name>)[^<]+", chunk)]
            year = arxiv_year_from_xml(chunk)
            isempty(id) && continue
            push!(records, SourceRecord(provider="arxiv-search", id=id, title=title2,
                authors=authors, year=year, url="https://arxiv.org/abs/$(id)",
                pdf_url="https://arxiv.org/pdf/$(id)"))
        end
        return records
    catch err
        return [SourceRecord(provider="arxiv-search-error", id=title,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function semantic_scholar_record_from_item(item; provider_name::String)
    authors = String[]
    if hasproperty(item, :authors)
        for author in item.authors
            name = optional_string(author, :name)
            name === nothing || push!(authors, name)
        end
    end
    doi = nothing
    if hasproperty(item, :externalIds) && item.externalIds !== nothing
        doi = optional_string(item.externalIds, :DOI)
    end
    pdf_url = nothing
    if hasproperty(item, :openAccessPdf) && item.openAccessPdf !== nothing
        pdf_url = optional_string(item.openAccessPdf, :url)
    end
    venue = optional_string(item, :venue)
    journal = venue
    if hasproperty(item, :journal) && item.journal !== nothing
        journal = optional_string(item.journal, :name)
    end
    return SourceRecord(provider=provider_name,
        id=String(get(item, :paperId, "")),
        title=optional_string(item, :title),
        authors=authors,
        year=hasproperty(item, :year) && item.year !== nothing ? string(item.year) : nothing,
        doi=doi,
        url=optional_string(item, :url),
        journal=journal,
        pdf_url=pdf_url)
end

function semantic_scholar_records(provider::ApiProvider, doi::AbstractString)
    fields = "paperId,title,authors,year,externalIds,url,venue,journal,openAccessPdf"
    url = "https://api.semanticscholar.org/graph/v1/paper/DOI:$(escapeuri(normalize_doi(doi)))?fields=$(fields)"
    try
        obj = provider_get_json(provider, url; headers=["User-Agent" => provider.user_agent])
        return [semantic_scholar_record_from_item(obj; provider_name="semantic-scholar")]
    catch err
        return [SourceRecord(provider="semantic-scholar-error", id=normalize_doi(doi),
            doi=normalize_doi(doi), raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function semantic_scholar_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    fields = "paperId,title,authors,year,externalIds,url,venue,journal,openAccessPdf"
    url = "https://api.semanticscholar.org/graph/v1/paper/search?query=$(escapeuri(query))&limit=3&fields=$(fields)"
    try
        obj = provider_get_json(provider, url; headers=["User-Agent" => provider.user_agent])
        hasproperty(obj, :data) || return SourceRecord[]
        return [semantic_scholar_record_from_item(item; provider_name="semantic-scholar-search")
            for item in obj.data]
    catch err
        return [SourceRecord(provider="semantic-scholar-search-error", id=query,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function pubmed_summary_records(provider::ApiProvider, ids::Vector{String}; provider_name::String)
    isempty(ids) && return SourceRecord[]
    url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=$(escapeuri(join(ids, ",")))&retmode=json&tool=PaperFetch&email=$(escapeuri(provider.email))"
    obj = provider_get_json(provider, url; headers=["User-Agent" => provider.user_agent])
    hasproperty(obj, :result) || return SourceRecord[]
    records = SourceRecord[]
    for id in ids
        sid = Symbol(id)
        hasproperty(obj.result, sid) || continue
        item = getproperty(obj.result, sid)
        authors = String[]
        if hasproperty(item, :authors)
            for author in item.authors
                name = optional_string(author, :name)
                name === nothing || push!(authors, name)
            end
        end
        doi = nothing
        if hasproperty(item, :articleids)
            for articleid in item.articleids
                idtype = lowercase(String(get(articleid, :idtype, "")))
                idtype == "doi" && (doi = optional_string(articleid, :value))
            end
        end
        journal = optional_string(item, :fulljournalname)
        journal === nothing && (journal = optional_string(item, :source))
        push!(records, SourceRecord(provider=provider_name,
            id=id,
            title=optional_string(item, :title),
            authors=authors,
            year=optional_string(item, :pubdate),
            doi=doi,
            url="https://pubmed.ncbi.nlm.nih.gov/$(id)/",
            journal=journal,
            pages=optional_string(item, :pages),
            raw=Dict{String,Any}("pmid" => id)))
    end
    return records
end

function pubmed_search_ids(provider::ApiProvider, term::AbstractString)
    url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=$(escapeuri(term))&retmode=json&retmax=3&tool=PaperFetch&email=$(escapeuri(provider.email))"
    obj = provider_get_json(provider, url; headers=["User-Agent" => provider.user_agent])
    if hasproperty(obj, :esearchresult) && hasproperty(obj.esearchresult, :idlist)
        # `String.(...)` on a JSON3 array with zero elements infers eltype
        # `Union{}` (not `String`), which then fails to dispatch on
        # `pubmed_summary_records(::ApiProvider, ::Vector{String}; ...)`. An
        # explicitly-typed comprehension keeps the result `Vector{String}`
        # even when empty, which is the common case for non-biomedical works.
        return String[String(id) for id in obj.esearchresult.idlist]
    end
    return String[]
end

function pubmed_records(provider::ApiProvider, doi::AbstractString)
    clean = normalize_doi(doi)
    try
        ids = pubmed_search_ids(provider, clean * "[AID]")
        return pubmed_summary_records(provider, ids; provider_name="pubmed")
    catch err
        return [SourceRecord(provider="pubmed-error", id=clean, doi=clean,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function pubmed_pmid_records(provider::ApiProvider, pmid::AbstractString)
    clean = replace(strip(pmid), r"[^0-9]" => "")
    isempty(clean) && return SourceRecord[]
    try
        return pubmed_summary_records(provider, [clean]; provider_name="pubmed")
    catch err
        return [SourceRecord(provider="pubmed-error", id=clean,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function pubmed_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    try
        ids = pubmed_search_ids(provider, query)
        return pubmed_summary_records(provider, ids; provider_name="pubmed-search")
    catch err
        return [SourceRecord(provider="pubmed-search-error", id=query,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function core_record_from_item(item; provider_name::String)
    authors = String[]
    if hasproperty(item, :authors)
        for author in item.authors
            if author isa AbstractString
                push!(authors, String(author))
            else
                name = optional_string(author, :name)
                name === nothing || push!(authors, name)
            end
        end
    end
    doi = optional_string(item, :doi)
    if doi === nothing && hasproperty(item, :identifiers)
        for identifier in item.identifiers
            text = String(identifier)
            for found in dois_in_text(text)
                doi = found
                break
            end
            doi === nothing || break
        end
    end
    pdf_url = optional_string(item, :downloadUrl)
    pdf_url === nothing && (pdf_url = optional_string(item, :fullTextLink))
    landing = nothing
    if hasproperty(item, :sourceFulltextUrls) && !isempty(item.sourceFulltextUrls)
        landing = String(first(item.sourceFulltextUrls))
    end
    return SourceRecord(provider=provider_name,
        id=string(get(item, :id, "")),
        title=optional_string(item, :title),
        authors=authors,
        year=hasproperty(item, :yearPublished) && item.yearPublished !== nothing ? string(item.yearPublished) : nothing,
        doi=doi,
        url=landing,
        publisher=optional_string(item, :publisher),
        pdf_url=pdf_url)
end

function core_search(provider::ApiProvider, query::AbstractString; provider_name::String)
    url = "https://api.core.ac.uk/v3/search/works?q=$(escapeuri(query))&limit=3"
    obj = provider_get_json(provider, url; headers=["User-Agent" => provider.user_agent])
    hasproperty(obj, :results) || return SourceRecord[]
    return [core_record_from_item(item; provider_name) for item in obj.results]
end

function core_records(provider::ApiProvider, doi::AbstractString)
    clean = normalize_doi(doi)
    try
        return core_search(provider, "doi:\"" * clean * "\""; provider_name="core")
    catch err
        return [SourceRecord(provider="core-error", id=clean, doi=clean,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function core_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    try
        return core_search(provider, query; provider_name="core-search")
    catch err
        return [SourceRecord(provider="core-search-error", id=query,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function figshare_article_record(provider::ApiProvider, article; provider_name::String)
    id = string(get(article, :id, ""))
    detail = article
    if !isempty(id) && !hasproperty(article, :authors)
        detail_url = "https://api.figshare.com/v2/articles/$(escapeuri(id))"
        detail = provider_get_json(provider, detail_url; headers=["User-Agent" => provider.user_agent])
    end
    authors = String[]
    if hasproperty(detail, :authors)
        for author in detail.authors
            name = optional_string(author, :full_name)
            name === nothing && (name = optional_string(author, :name))
            name === nothing || push!(authors, name)
        end
    end
    doi = optional_string(detail, :doi)
    pdf_url = nothing
    if hasproperty(detail, :files)
        for file in detail.files
            download_url = optional_string(file, :download_url)
            download_url !== nothing || continue
            name = lowercase(String(get(file, :name, "")))
            if endswith(name, ".pdf") || occursin("pdf", lowercase(String(get(file, :mime_type, ""))))
                pdf_url = download_url
                break
            end
        end
    end
    return SourceRecord(provider=provider_name,
        id=id,
        title=optional_string(detail, :title),
        authors=authors,
        year=optional_string(detail, :published_date),
        doi=doi,
        url=optional_string(detail, :url_public_html),
        publisher="figshare",
        pdf_url=pdf_url)
end

function figshare_search(provider::ApiProvider, query::AbstractString; provider_name::String)
    url = "https://api.figshare.com/v2/articles/search?search_for=$(escapeuri(query))&limit=3"
    obj = provider_get_json(provider, url; headers=["User-Agent" => provider.user_agent])
    records = SourceRecord[]
    for article in obj
        push!(records, figshare_article_record(provider, article; provider_name))
    end
    return records
end

function figshare_records(provider::ApiProvider, doi::AbstractString)
    clean = normalize_doi(doi)
    try
        return figshare_search(provider, clean; provider_name="figshare")
    catch err
        return [SourceRecord(provider="figshare-error", id=clean, doi=clean,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function figshare_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    try
        return figshare_search(provider, query; provider_name="figshare-search")
    catch err
        return [SourceRecord(provider="figshare-search-error", id=query,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function openlibrary_isbn_records(provider::ApiProvider, isbn::AbstractString)
    clean = replace(isbn, r"[^0-9Xx]" => "")
    isempty(clean) && return SourceRecord[]
    url = "https://openlibrary.org/isbn/$(escapeuri(clean)).json"
    try
        obj = provider_get_json(provider, url)
        authors = String[]
        if hasproperty(obj, :authors)
            for author in obj.authors
                # ISBN records return {"key": "/authors/OL1A"} with no inline name.
                # Only capture a name if the record explicitly provides one.
                name = optional_string(author, :name)
                name !== nothing && push!(authors, name)
            end
        end
        return [SourceRecord(provider="openlibrary", id=clean,
            title=optional_string(obj, :title), authors=authors,
            year=optional_string(obj, :publish_date),
            publisher=hasproperty(obj, :publishers) && !isempty(obj.publishers) ? String(obj.publishers[1]) : nothing,
            url="https://openlibrary.org/isbn/$(clean)",
            raw=Dict{String,Any}("isbn" => clean))]
    catch err
        return [SourceRecord(provider="openlibrary-error", id=clean,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function openlibrary_search_records(provider::ApiProvider, entry::BibEntry)
    query = title_author_query(entry)
    query === nothing && return SourceRecord[]
    url = "https://openlibrary.org/search.json?q=$(escapeuri(query))&limit=3"
    try
        obj = provider_get_json(provider, url)
        records = SourceRecord[]
        for doc in obj.docs
            authors = hasproperty(doc, :author_name) ? String.(doc.author_name) : String[]
            isbn = hasproperty(doc, :isbn) && !isempty(doc.isbn) ? String(doc.isbn[1]) : ""
            publisher = hasproperty(doc, :publisher) && !isempty(doc.publisher) ? String(doc.publisher[1]) : nothing
            year = hasproperty(doc, :first_publish_year) ? string(doc.first_publish_year) : nothing
            push!(records, SourceRecord(provider="openlibrary-search", id=String(get(doc, :key, "")),
                title=optional_string(doc, :title), authors=authors, year=year,
                publisher=publisher, url="https://openlibrary.org" * String(get(doc, :key, "")),
                raw=Dict{String,Any}("isbn" => isbn)))
        end
        return records
    catch err
        return [SourceRecord(provider="openlibrary-search-error", id=query,
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function google_books_records(provider::ApiProvider, query::AbstractString)
    url = "https://www.googleapis.com/books/v1/volumes?q=$(escapeuri(query))&maxResults=3"
    try
        obj = provider_get_json(provider, url)
        hasproperty(obj, :items) || return SourceRecord[]
        records = SourceRecord[]
        for item in obj.items
            info = item.volumeInfo
            authors = hasproperty(info, :authors) ? String.(info.authors) : String[]
            publisher = optional_string(info, :publisher)
            year = optional_string(info, :publishedDate)
            isbns = String[]
            if hasproperty(info, :industryIdentifiers)
                for identifier in info.industryIdentifiers
                    value = optional_string(identifier, :identifier)
                    value === nothing && continue
                    clean = replace(value, r"[^0-9Xx]" => "")
                    isempty(clean) || clean in isbns || push!(isbns, clean)
                end
            end
            push!(records, SourceRecord(provider="google-books", id=String(get(item, :id, "")),
                title=optional_string(info, :title), authors=authors, year=year,
                publisher=publisher, url=optional_string(info, :infoLink),
                raw=Dict{String,Any}("isbn" => isbns)))
        end
        return records
    catch err
        return [SourceRecord(provider="google-books-error", id=String(query),
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end

function html_meta(content::AbstractString, names::Vector{String})
    for name in names
        rx = Regex("<meta[^>]+(?:name|property)=[\"']" * name * "[\"'][^>]+content=[\"']([^\"']+)[\"']", "is")
        m = match(rx, content)
        if m !== nothing
            capture = m[1]
            capture !== nothing && return strip(capture)
        end
        rx2 = Regex("<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:name|property)=[\"']" * name * "[\"']", "is")
        m = match(rx2, content)
        if m !== nothing
            capture = m[1]
            capture !== nothing && return strip(capture)
        end
    end
    return nothing
end

function github_citation_cff_urls(url::AbstractString)
    m = match(r"^https?://github\.com/([^/\s]+)/([^/\s#?]+)"i, String(url))
    m === nothing && return String[]
    owner, repo = m.captures[1], replace(m.captures[2], r"\.git$" => "")
    (owner === nothing || repo === nothing) && return String[]
    return [
        "https://raw.githubusercontent.com/$(owner)/$(repo)/main/CITATION.cff",
        "https://raw.githubusercontent.com/$(owner)/$(repo)/master/CITATION.cff",
    ]
end

function cff_scalar(content::AbstractString, field::AbstractString)
    rx = Regex("(?m)^\\s*" * field * "\\s*:\\s*(.+?)\\s*\$")
    m = match(rx, content)
    m === nothing && return nothing
    value = strip(something(m.captures[1], ""))
    value = replace(value, r"^['\"]|['\"]$" => "")
    return isempty(value) ? nothing : value
end

"""
    cff_author_entries(content)

Parse the `authors:` list of a CITATION.cff file into `(name, orcid)` pairs.

The end of the authors section is detected by indentation (an unindented line
starts a new top-level CFF key), not by field name. This means author fields
that aren't part of the name (such as `orcid` or `affiliation`) are skipped
without prematurely truncating the author list — a YAML list item is only
required to provide `given-names`/`family-names` or `name`.

# Example

```julia
content = "authors:\\n  - family-names: Doe\\n    given-names: Jane\\n"
PaperFetch.cff_author_entries(content)[1].name == "Jane Doe"
```
"""
function flush_cff_author!(entries::Vector{NamedTuple{(:name, :orcid), Tuple{String,Union{Nothing,String}}}},
        current::Dict{String,String})
    isempty(current) && return nothing
    given = get(current, "given-names", "")
    family = get(current, "family-names", get(current, "name", ""))
    name = strip(join(filter(!isempty, String[given, family]), " "))
    if !isempty(name)
        orcid = get(current, "orcid", nothing)
        push!(entries, (name=name, orcid=(orcid === nothing || isempty(orcid)) ? nothing : orcid))
    end
    return nothing
end

function cff_author_entries(content::AbstractString)
    entries = NamedTuple{(:name, :orcid), Tuple{String,Union{Nothing,String}}}[]
    current = Dict{String,String}()
    in_authors = false
    for line in split(content, '\n')
        stripped = strip(line)
        if occursin(r"^authors\s*:\s*$", stripped)
            in_authors = true
            continue
        end
        in_authors || continue
        isempty(stripped) && continue
        # An unindented line starts a new top-level CFF key, which ends the
        # authors section: author entries and their fields are always indented.
        if !isempty(line) && !isspace(first(line))
            flush_cff_author!(entries, current)
            current = Dict{String,String}()
            break
        end
        if startswith(stripped, "-")
            flush_cff_author!(entries, current)
            current = Dict{String,String}()
        end
        m = match(r"^-?\s*([A-Za-z-]+)\s*:\s*(.+?)\s*$", stripped)
        m === nothing && continue
        key = something(m.captures[1], "")
        key in ("given-names", "family-names", "name", "orcid") || continue
        value = replace(strip(something(m.captures[2], "")), r"^['\"]|['\"]$" => "")
        current[key] = value
    end
    flush_cff_author!(entries, current)
    return entries
end

cff_authors(content::AbstractString) = [entry.name for entry in cff_author_entries(content)]

function cff_record(provider::ApiProvider, repo_url::AbstractString)
    for cff_url in github_citation_cff_urls(repo_url)
        content = try
            provider_get_text(provider, cff_url; headers=["User-Agent" => provider.user_agent])
        catch
            continue
        end
        title = cff_scalar(content, "title")
        doi = cff_scalar(content, "doi")
        released = cff_scalar(content, "date-released")
        cff_url_field = cff_scalar(content, "url")
        entries = cff_author_entries(content)
        authors = [entry.name for entry in entries]
        if title !== nothing || doi !== nothing || !isempty(authors)
            year = released === nothing ? nothing : normalize_year(released)
            raw = Dict{String,Any}("citation_url" => cff_url)
            orcids = Dict(entry.name => entry.orcid for entry in entries if entry.orcid !== nothing)
            isempty(orcids) || (raw["orcids"] = orcids)
            return SourceRecord(provider="citation-cff", id=String(cff_url),
                title=title, authors=authors, year=year,
                doi=doi === nothing ? nothing : normalize_doi(doi),
                url=something(cff_url_field, String(repo_url)),
                raw=raw)
        end
    end
    return nothing
end

function url_records(provider::ApiProvider, url::AbstractString, entry::BibEntry)
    try
        body = provider_get_text(provider, String(url); headers=["User-Agent" => provider.user_agent])
        if startswith(body, "%PDF")
            return [SourceRecord(provider="url-pdf", id=String(url), title=get(entry.fields, "title", nothing),
                url=String(url), pdf_url=String(url), raw=Dict{String,Any}("content" => "pdf"))]
        end
        cff = cff_record(provider, url)
        cff === nothing || return [cff]
        title = html_meta(body, ["citation_title", "dc.title", "DC.title", "og:title"])
        doi = html_meta(body, ["citation_doi", "dc.identifier", "DC.identifier"])
        pdf = html_meta(body, ["citation_pdf_url"])
        authors = String[]
        for m in eachmatch(r"<meta[^>]+name=[\"']citation_author[\"'][^>]+content=[\"']([^\"']+)[\"']"is, body)
            author = m[1]
            author === nothing || push!(authors, strip(author))
        end
        return [SourceRecord(provider="url-metadata", id=String(url), title=title,
            authors=authors, doi=doi === nothing ? nothing : normalize_doi(doi),
            url=String(url), pdf_url=pdf, raw=Dict{String,Any}("content" => "html"))]
    catch err
        return [SourceRecord(provider="url-error", id=String(url),
            raw=Dict{String,Any}("error" => sprint(showerror, err)))]
    end
end
