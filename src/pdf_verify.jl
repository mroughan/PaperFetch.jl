"""
    pdftotext_available()

Whether the `pdftotext` command-line tool (from poppler-utils) is installed.

Used to extract the embedded text layer of a born-digital PDF, without
needing OCR, before falling back to `ocr_tools_available`.
"""
pdftotext_available() = Sys.which("pdftotext") !== nothing

"""
    ocr_tools_available()

Whether both `pdftoppm` (poppler-utils, page rasterization) and `tesseract`
(OCR) are installed. Needed only for scanned/image-only PDFs whose embedded
text layer is empty or near-empty.
"""
ocr_tools_available() = Sys.which("pdftoppm") !== nothing && Sys.which("tesseract") !== nothing

"""
Minimum extracted character count below which a PDF's embedded text layer is
treated as absent (scanned/image-only), triggering the OCR fallback.
"""
const PDF_TEXT_MIN_CHARS = 40

"""
Number of leading pages rasterized and OCR'd when a PDF has no usable text
layer. Title, author, and year normally appear on the first page, so this is
kept small to bound OCR runtime.
"""
const PDF_OCR_MAX_PAGES = 3

function pdftotext_extract(path::AbstractString)
    pdftotext_available() || return ""
    try
        return read(pipeline(`pdftotext -layout $(path) -`; stderr=devnull), String)
    catch
        return ""
    end
end

function pdf_ocr_extract(path::AbstractString; max_pages::Int=PDF_OCR_MAX_PAGES)
    ocr_tools_available() || return ""
    mktempdir() do dir
        prefix = joinpath(dir, "page")
        try
            run(pipeline(`pdftoppm -png -r 200 -f 1 -l $(max_pages) $(path) $(prefix)`;
                stdout=devnull, stderr=devnull))
        catch
            return ""
        end
        pages = sort(filter(f -> endswith(f, ".png"), readdir(dir; join=true)))
        isempty(pages) && return ""
        chunks = String[]
        for page in pages
            try
                push!(chunks, read(pipeline(`tesseract $(page) - --psm 3`; stderr=devnull), String))
            catch
                continue
            end
        end
        return join(chunks, "\n")
    end
end

"""
    extract_pdf_text(path)

Best-effort text extraction from a PDF for identity verification.

Tries the embedded text layer via `pdftotext` first, since most academic
PDFs are born-digital and this is fast and exact. Only if that yields fewer
than `PDF_TEXT_MIN_CHARS` characters (a scanned/image-only PDF) does it fall
back to OCR: rasterizing the first `PDF_OCR_MAX_PAGES` pages with `pdftoppm`
and reading them with `tesseract`.

Returns a `(text, method)` named tuple; `method` is `:text` or `:ocr`. If the
required command-line tools are not installed, or extraction otherwise
fails, `text` is `""` — callers should treat that as "no evidence
available", not as a mismatch.

# Example

```julia
result = PaperFetch.extract_pdf_text("/nonexistent/missing.pdf")
result.text == ""
```
"""
function extract_pdf_text(path::AbstractString)
    text = pdftotext_extract(path)
    length(strip(text)) >= PDF_TEXT_MIN_CHARS && return (text=text, method=:text)
    ocr_text = pdf_ocr_extract(path)
    isempty(strip(ocr_text)) && return (text=text, method=:text)
    return (text=ocr_text, method=:ocr)
end

"""
    pdf_text_confirmation(entry, text, pdf_url; provider)

Best-effort identity check of `entry`'s `title`, creator (`author` or
`editor`), and `year` against `text` extracted from a candidate PDF.

Only fields actually found in `text` are set on the returned `SourceRecord`;
fields not found stay `nothing`, so `compare_entry` correctly reports
them as unconfirmed (`:missing_source`) rather than as a match. This mirrors
how every other provider adapter works: a field is only populated when the
source actually supplied it, so a record with nothing confirmed is
transparently discarded by the same "insufficient identity evidence" logic
used everywhere else, rather than needing a special case.

Author matching checks each of the entry's surnames against normalized `text`
and matches if any one of them is found — full-page OCR of a multi-author
byline is noisy, and requiring every surname to survive was too strict.

# Example

```julia
entry = BibEntry("x", "article", Dict("title" => "A Field-Rich Paper", "year" => "2020"))
source = PaperFetch.pdf_text_confirmation(entry, "Cover page. A Field-Rich Paper. 2020.",
    "https://example.org/paper.pdf"; provider="pdf-text")
source.title == "A Field-Rich Paper" && source.year == "2020"
```
"""
function pdf_text_confirmation(entry::BibEntry, text::AbstractString, pdf_url::AbstractString;
        provider::String)
    normalized = normalize_text(text)

    title = nonempty(get(entry.fields, "title", nothing))
    title_hit = title !== nothing && !isempty(normalized) &&
        !isempty(normalize_text(title)) && occursin(normalize_text(title), normalized)

    creator_field = haskey(entry.fields, "author") ? "author" : "editor"
    creator = nonempty(get(entry.fields, creator_field, nothing))
    surnames = creator === nothing ? String[] : author_surnames(creator)
    creator_hit = !isempty(surnames) && !isempty(normalized) &&
        any(surname -> occursin(normalize_text(surname), normalized), surnames)

    year = nonempty(get(entry.fields, "year", nothing))
    year_norm = year === nothing ? "" : normalize_year(year)
    year_hit = !isempty(year_norm) && occursin(year_norm, text)

    excerpt = isempty(normalized) ? "" : first(normalized, 240)
    return SourceRecord(provider=provider, id=pdf_url,
        title=title_hit ? title : nothing,
        authors=creator_hit ? [creator] : String[],
        year=year_hit ? year : nothing,
        pdf_url=pdf_url,
        raw=Dict{String,Any}("verification" => "full-text", "excerpt" => excerpt))
end

"""
    pdf_text_fallback_source(entry, pdf_url; http_get=HTTP.get)

Download `pdf_url` and attempt full-text identity verification against
`entry`, returning exactly one `SourceRecord`.

This is a deliberate exception to normally never downloading files just to
check a bibliography: it only runs (see `check_bibliography`'s
`verify_pdf_text` keyword) when no metadata provider found a reliable source
for the entry but a PDF candidate URL exists, as a last resort.

On download failure, returns a `"pdf-text-error"` record (surfaced as a
provider error note, like every other adapter's error record) rather than
raising, so a paywalled or unreachable PDF does not interrupt the rest of the
bibliography check.
"""
function pdf_text_fallback_source(entry::BibEntry, pdf_url::AbstractString; http_get=HTTP.get)
    return mktempdir() do dir
        dest = joinpath(dir, "candidate.pdf")
        ok, _, note, _, _ = download_pdf(pdf_url, dest; http_get)
        if !ok
            return SourceRecord(provider="pdf-text-error", id=pdf_url,
                raw=Dict{String,Any}("error" => note))
        end
        result = extract_pdf_text(dest)
        provider = result.method == :ocr ? "pdf-ocr" : "pdf-text"
        return pdf_text_confirmation(entry, result.text, pdf_url; provider)
    end
end
