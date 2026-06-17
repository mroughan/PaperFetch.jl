"""
    WorkIdentifier(kind, value)

A normalized identifier extracted from a bibliography entry.

`kind` is one of `:doi`, `:isbn`, `:url`, `:arxiv`, `:pmid`, or `:openalex`.
`value` is the normalized identifier string.

# Example

```julia
id = WorkIdentifier(:doi, "10.1000/example")
id.kind == :doi
```
"""
struct WorkIdentifier
    kind::Symbol
    value::String
end

const DOI_PATTERN = r"(?i)(?:https?://(?:dx\.)?doi\.org/|doi\s*:\s*|\\url\s*\{\s*)?(10\.\d{4,9}/[^\s\}\]\"<>;,]+)"
const URL_PATTERN = r"(?i)(?:\\url\s*\{\s*)?(https?://[^\s\}\]\"<>]+)"
const ARXIV_PATTERN = r"(?i)(?:arxiv\s*[:/]\s*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?)"

function dois_in_text(value::AbstractString)
    dois = String[]
    for match in eachmatch(DOI_PATTERN, value)
        doi = normalize_doi(match.captures[1])
        doi = replace(doi, r"[.)]+$" => "")
        isempty(doi) || doi in dois || push!(dois, doi)
    end
    return dois
end

function urls_in_text(value::AbstractString)
    urls = String[]
    for match in eachmatch(URL_PATTERN, value)
        url = replace(strip(match.captures[1]), r"[.)]+$" => "")
        isempty(url) || url in urls || push!(urls, url)
    end
    return urls
end

function arxiv_ids_in_text(value::AbstractString)
    ids = String[]
    for match in eachmatch(ARXIV_PATTERN, value)
        id = strip(match.captures[1])
        isempty(id) || id in ids || push!(ids, id)
    end
    return ids
end

"""
    extract_identifiers(entry)

Extract normalized `WorkIdentifier` values from a `BibEntry`.

Checks for DOI, arXiv eprint (when `archiveprefix` is `arXiv`), ISBN, and URL
fields in that priority order. DOI-like strings are also recovered from common
wrong fields such as `note`, `url`, and `howpublished`.

# Example

```julia
entry = BibEntry("x", "article", Dict("doi" => "10.1000/example"))
ids = extract_identifiers(entry)
ids[1].kind == :doi
```
"""
function extract_identifiers(entry::BibEntry)
    ids = WorkIdentifier[]

    seen = Set{Tuple{Symbol,String}}()
    function add!(kind::Symbol, value::AbstractString)
        clean = kind == :doi ? normalize_doi(value) : strip(String(value))
        key = (kind, clean)
        if !isempty(clean) && key ∉ seen
            push!(seen, key)
            push!(ids, WorkIdentifier(kind, clean))
        end
    end

    doi = get(entry.fields, "doi", nothing)
    doi !== nothing && add!(:doi, doi)

    for field in ("url", "note", "howpublished", "eprint", "archiveprefix")
        value = get(entry.fields, field, nothing)
        value === nothing && continue
        for recovered in dois_in_text(value)
            add!(:doi, recovered)
        end
    end

    for field in ("url", "note", "howpublished")
        value = get(entry.fields, field, nothing)
        value === nothing && continue
        for recovered in arxiv_ids_in_text(value)
            add!(:arxiv, recovered)
        end
    end

    eprint = get(entry.fields, "eprint", nothing)
    archiveprefix = get(entry.fields, "archiveprefix", nothing)
    if eprint !== nothing && archiveprefix !== nothing &&
            lowercase(strip(archiveprefix)) == "arxiv"
        add!(:arxiv, eprint)
    end

    isbn = get(entry.fields, "isbn", nothing)
    isbn !== nothing && add!(:isbn, isbn)

    for field in ("url", "note", "howpublished")
        value = get(entry.fields, field, nothing)
        value === nothing && continue
        for recovered in urls_in_text(value)
            add!(:url, recovered)
        end
    end

    return ids
end
