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

Base.@kwdef struct ApiProvider <: AbstractProvider
    email::String = "noreply@example.org"
    user_agent::String = DEFAULT_USER_AGENT
    get_json::Function = default_get_json
    get_text::Function = default_get_text
    cache_dir::Union{Nothing,String} = nothing
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

function provider_get_json(provider::ApiProvider, url::String; headers=Pair{String,String}[])
    provider.cache_dir === nothing && return provider.get_json(url; headers)
    key = bytes2hex(sha256(url))
    path = joinpath(provider.cache_dir, key * ".json")
    metapath = joinpath(provider.cache_dir, key * ".meta.json")
    if isfile(path)
        return JSON3.read(read(path, String))
    end
    result = provider.get_json(url; headers)
    mkpath(provider.cache_dir)
    write(path, JSON3.write(result))
    write(metapath, JSON3.write(Dict(
        "url" => url,
        "cached_at" => string(Dates.now()),
        "format" => "json",
    )))
    return result
end

function provider_get_text(provider::ApiProvider, url::String; headers=Pair{String,String}[])
    provider.cache_dir === nothing && return provider.get_text(url; headers)
    key = bytes2hex(sha256(url))
    path = joinpath(provider.cache_dir, key * ".xml")
    metapath = joinpath(provider.cache_dir, key * ".meta.json")
    if isfile(path)
        return read(path, String)
    end
    result = provider.get_text(url; headers)
    mkpath(provider.cache_dir)
    write(path, result)
    write(metapath, JSON3.write(Dict(
        "url" => url,
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
        elseif id.kind == :arxiv
            for rec in arxiv_records(provider, id.value)
                key = rec.provider * ":" * id.value
                key in seen || (push!(seen, key); push!(sources, rec))
            end
        end
    end
    return sources
end

function provider_sources(providers, entry)
    sources = SourceRecord[]
    for provider in providers
        append!(sources, sources_for(provider, entry))
    end
    return sources
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
                given = String(get(author, :given, ""))
                family = String(get(author, :family, ""))
                push!(authors, strip(join(filter(!isempty, [given, family]), " ")))
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

function arxiv_records(provider::ApiProvider, arxiv_id::AbstractString)
    base_id = replace(strip(arxiv_id), r"v\d+$" => "")
    url = "https://export.arxiv.org/api/query?id_list=$(escapeuri(base_id))"
    headers = ["User-Agent" => provider.user_agent]
    try
        body = provider_get_text(provider, url; headers)
        # Extract entry-level title (skip the feed <title> by anchoring to <entry>)
        title = let m = match(r"<entry>.*?<title[^>]*>(.*?)</title>"s, body)
            m !== nothing ? strip(m[1]) : nothing
        end
        authors = [strip(m.match) for m in eachmatch(r"(?<=<name>)[^<]+", body)]
        year = let m = match(r"<published>(\d{4})", body); m !== nothing ? m[1] : nothing end
        raw_doi = let m = match(r"<arxiv:doi[^>]*>([^<]+)</arxiv:doi>", body)
            m !== nothing ? normalize_doi(m[1]) : nothing
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
