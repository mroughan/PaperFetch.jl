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
function normalize_authors(value::AbstractString)
    parts = split(value, r"\s+(?:and|&)\s+"i)
    clean = normalize_text.(parts)
    sort!(filter!(!isempty, clean))
    return join(clean, ";")
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
