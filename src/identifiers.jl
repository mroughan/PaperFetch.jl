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

"""
    extract_identifiers(entry)

Extract normalized `WorkIdentifier` values from a `BibEntry`.

Checks for DOI, arXiv eprint (when `archiveprefix` is `arXiv`), ISBN, and URL
fields in that priority order.

# Example

```julia
entry = BibEntry("x", "article", Dict("doi" => "10.1000/example"))
ids = extract_identifiers(entry)
ids[1].kind == :doi
```
"""
function extract_identifiers(entry::BibEntry)
    ids = WorkIdentifier[]

    doi = get(entry.fields, "doi", nothing)
    doi !== nothing && push!(ids, WorkIdentifier(:doi, normalize_doi(doi)))

    eprint = get(entry.fields, "eprint", nothing)
    archiveprefix = get(entry.fields, "archiveprefix", nothing)
    if eprint !== nothing && archiveprefix !== nothing &&
            lowercase(strip(archiveprefix)) == "arxiv"
        push!(ids, WorkIdentifier(:arxiv, strip(eprint)))
    end

    isbn = get(entry.fields, "isbn", nothing)
    isbn !== nothing && push!(ids, WorkIdentifier(:isbn, strip(isbn)))

    url = get(entry.fields, "url", nothing)
    url !== nothing && push!(ids, WorkIdentifier(:url, url))

    return ids
end
