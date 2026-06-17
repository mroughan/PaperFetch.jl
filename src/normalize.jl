const LATEX_ACCENTS = Dict(
    "\\'a" => "a", "\\'e" => "e", "\\'i" => "i", "\\'o" => "o", "\\'u" => "u",
    "\\`a" => "a", "\\`e" => "e", "\\`i" => "i", "\\`o" => "o", "\\`u" => "u",
    "\\\"a" => "a", "\\\"e" => "e", "\\\"i" => "i", "\\\"o" => "o", "\\\"u" => "u",
    "\\~n" => "n", "\\c c" => "c", "\\aa" => "a", "\\ae" => "ae", "\\oe" => "oe",
)

function strip_latex(value::AbstractString)
    text = lowercase(value)
    text = replace(text, r"``|''|[“”„]" => "\"")
    text = replace(text, r"[‘’‚]" => "'")
    text = replace(text, r"\{\\([`'\"^~=.uvHtcdb])\s*\{?([a-z])\}?\}" => s"\2")
    text = replace(text, r"\\([`'\"^~=.uvHtcdb])\s*\{?([a-z])\}?" => s"\2")
    for (src, dst) in LATEX_ACCENTS
        text = replace(text, src => dst)
    end
    text = replace(text, r"\\(?:raggedright|footnotesize|scriptsize|small|normalsize|large|Large|LARGE|huge|Huge)\b" => " ")
    text = replace(text, r"[{}]" => "")
    text = replace(text, r"\\[a-zA-Z]+" => "")
    return text
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

function normalize_url(value::AbstractString)
    text = strip(value)
    text = replace(text, r"[.)]+$" => "")
    doi_match = match(r"(?i)^https?://(?:dx\.)?doi\.org/(10\.\d{4,9}/.+)$", text)
    if doi_match !== nothing
        capture = doi_match.captures[1]
        capture !== nothing && return "doi:" * normalize_doi(capture)
    end
    text = replace(text, r"(?i)^https?://" => "")
    text = replace(text, r"/+$" => "")
    return lowercase(text)
end

"""
    normalize_text(value)

Normalize bibliographic text for tolerant comparison.

Removes BibTeX braces and LaTeX accent commands, applies Unicode
normalization (NFD + stripmark), lowercases, and collapses punctuation
and whitespace.

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

"""
    normalize_pages(value)

Normalize a page range to a single-hyphen form with no whitespace.

# Example

```julia
normalize_pages("123 -- 130") == "123-130"
```
"""
normalize_pages(value::AbstractString) = replace(strip(value), r"\s+" => "", r"-+" => "-")

"""
    normalize_year(value)

Extract a four-digit year from a string, or return `""`.

# Example

```julia
normalize_year("Published 2020") == "2020"
```
"""
function normalize_year(value::AbstractString)
    m = match(r"\d{4}", value)
    return m === nothing ? "" : m.match
end

"""
    normalize_authors(value)

Normalize an author string for tolerant comparison.

Splits on ` and ` or ` & `, normalizes each name, sorts alphabetically,
and joins with `;`. Order-invariant.

# Example

```julia
normalize_authors("Smith, J. and Doe, J.") == normalize_authors("Doe, J. and Smith, J.")
```
"""
function normalize_author_part(value::AbstractString)
    text = strip(value)
    if occursin(",", text)
        pieces = split(text, ","; limit=2)
        text = strip(pieces[2]) * " " * strip(pieces[1])
    end
    return normalize_text(text)
end

function normalize_authors(value::AbstractString)
    value = replace(value, r"(?i)\bet\.?\s+al\.?" => "")
    parts = split(value, r"\s+(?:and|&)\s+"i)
    clean = normalize_author_part.(parts)
    sort!(filter!(!isempty, clean))
    return join(clean, ";")
end

function normalized_author_signature_part(value::AbstractString)
    text = strip(value)
    given = ""
    surname = ""
    if occursin(",", text)
        pieces = split(text, ","; limit=2)
        surname = normalize_text(strip(pieces[1]))
        given = normalize_text(strip(pieces[2]))
    else
        pieces = split(normalize_text(text))
        isempty(pieces) && return nothing
        surname = last(pieces)
        given = join(pieces[1:end-1], " ")
    end
    isempty(surname) && return nothing
    initials = join([first(part) for part in split(given) if !isempty(part)])
    return (surname=surname, initials=initials)
end

function normalized_author_signatures(value::AbstractString)
    value = replace(value, r"(?i)\bet\.?\s+al\.?" => "")
    parts = split(value, r"\s+(?:and|&)\s+"i)
    sigs = filter(!isnothing, normalized_author_signature_part.(parts))
    return sort!(collect(sigs), by=s -> (s.surname, s.initials))
end

function compatible_initials(left::AbstractString, right::AbstractString)
    isempty(left) || isempty(right) || startswith(left, right) || startswith(right, left)
end

function author_signatures_match(left::AbstractString, right::AbstractString)
    a = normalized_author_signatures(left)
    b = normalized_author_signatures(right)
    (isempty(a) || isempty(b) || length(a) != length(b)) && return false
    for (x, y) in zip(a, b)
        x.surname == y.surname || return false
        compatible_initials(x.initials, y.initials) || return false
    end
    return true
end

function author_surnames(value::AbstractString)
    sigs = normalized_author_signatures(value)
    return unique([sig.surname for sig in sigs if !isempty(sig.surname)])
end

function edit_distance(left::AbstractString, right::AbstractString)
    a = collect(left)
    b = collect(right)
    previous = collect(0:length(b))
    current = similar(previous)
    for (i, ca) in enumerate(a)
        current[1] = i
        for (j, cb) in enumerate(b)
            current[j + 1] = min(
                previous[j + 1] + 1,
                current[j] + 1,
                previous[j] + (ca == cb ? 0 : 1),
            )
        end
        previous, current = current, previous
    end
    return previous[end]
end

function near_match(left::AbstractString, right::AbstractString; max_ratio::Float64=0.12)
    (isempty(left) || isempty(right)) && return false
    distance = edit_distance(left, right)
    scale = max(length(collect(left)), length(collect(right)))
    return scale > 0 && distance / scale <= max_ratio
end

"""
    slugify(value; maxlen=96)

Convert a string to a URL/filename-safe slug.

# Example

```julia
slugify("My Great Paper!") == "my-great-paper"
```
"""
function slugify(value::AbstractString; maxlen::Int=96)
    text = replace(normalize_text(value), r"[^a-z0-9]+" => "-")
    text = replace(text, r"^-+|-+$" => "")
    isempty(text) && return "untitled"
    return first(text, maxlen)
end
