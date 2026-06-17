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
const ADS_ARXIV_PATTERN = r"(?i)arxiv(\d{4})(\d{5})"
const PMID_PATTERN = r"(?i)\b(?:pmid\s*:\s*)?(\d{6,9})\b"

function dois_in_text(value::AbstractString)
    dois = String[]
    for match in eachmatch(DOI_PATTERN, value)
        capture = match.captures[1]
        capture === nothing && continue
        doi = normalize_doi(capture)
        doi = replace(doi, r"[.)]+$" => "")
        isempty(doi) || doi in dois || push!(dois, doi)
    end
    return dois
end

function urls_in_text(value::AbstractString)
    urls = String[]
    for match in eachmatch(URL_PATTERN, value)
        capture = match.captures[1]
        capture === nothing && continue
        url = replace(strip(capture), r"[.)]+$" => "")
        isempty(url) || url in urls || push!(urls, url)
    end
    return urls
end

function arxiv_ids_in_text(value::AbstractString)
    ids = String[]
    for match in eachmatch(ARXIV_PATTERN, value)
        capture = match.captures[1]
        capture === nothing && continue
        id = strip(capture)
        isempty(id) || id in ids || push!(ids, id)
    end
    for match in eachmatch(ADS_ARXIV_PATTERN, value)
        first_part, second_part = match.captures[1], match.captures[2]
        (first_part === nothing || second_part === nothing) && continue
        id = first_part * "." * second_part
        id in ids || push!(ids, id)
    end
    return ids
end

function pmids_in_text(value::AbstractString)
    ids = String[]
    for match in eachmatch(PMID_PATTERN, value)
        capture = match.captures[1]
        capture === nothing && continue
        id = strip(capture)
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

    for field in ("url", "note", "howpublished", "adsurl", "eprint")
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

    pmid = get(entry.fields, "pmid", nothing)
    pmid !== nothing && add!(:pmid, pmid)

    for field in ("url", "note", "howpublished")
        value = get(entry.fields, field, nothing)
        value === nothing && continue
        for recovered in pmids_in_text(value)
            add!(:pmid, recovered)
        end
    end

    for field in ("url", "note", "howpublished")
        value = get(entry.fields, field, nothing)
        value === nothing && continue
        for recovered in urls_in_text(value)
            add!(:url, recovered)
        end
    end

    return ids
end
