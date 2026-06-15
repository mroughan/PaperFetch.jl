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

Entries are returned sorted by key for stable, reproducible ordering.

# Example

```julia
entries = read_bibtex("examples/01_exact_article.bib"; check=:none)
length(entries) >= 1
```
"""
function read_bibtex(path::AbstractString; check=:warn)
    parsed = BibParser.parse_file(String(path); check)
    raw = sort!(collect(values(parsed)), by=e -> String(e.id))
    return [entry_to_bibentry(e) for e in raw]
end

"""
    read_items(path; check=:warn)

Read bibliography input. BibTeX files are parsed with BibParser; plain text
files are interpreted as one DOI or URL per non-comment line.

Item keys for plain-text input are `item1`, `item2`, … in line order,
skipping blank lines and comments.

# Example

```julia
items = read_items("examples/11_plain_dois.txt"; check=:none)
length(items) == 2
```
"""
function read_items(path::AbstractString; check=:warn)
    text = read(path, String)
    if occursin(r"@\w+\s*[\{\(]"i, text)
        return read_bibtex(path; check)
    end

    entries = BibEntry[]
    j = 0
    for line in split(text, '\n')
        item = strip(line)
        isempty(item) && continue
        startswith(item, "#") && continue
        j += 1
        fields = Dict{String,String}()
        if occursin(r"(?i)\b10\.\d{4,9}/", item)
            fields["doi"] = normalize_doi(item)
        elseif startswith(lowercase(item), "http://") || startswith(lowercase(item), "https://")
            fields["url"] = item
        else
            fields["title"] = item
        end
        push!(entries, BibEntry("item$(j)", "misc", fields))
    end
    return entries
end
