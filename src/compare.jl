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

`notes` contains entry-level diagnostics such as provider errors, discarded
candidate sources, and warnings about self-comparison fallback. Field-level
diagnostics live in `comparisons`.

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

const IGNORED_REFERENCE_FIELDS = Set([
    "abstract", "annote", "annotation", "bibsource", "biburl", "file",
    "groups", "keywords", "language", "mendeley-tags", "owner",
    "readstatus", "timestamp",
])

const SUPPLEMENTARY_FIELDS_BY_TYPE = Dict(
    "article" => Set(["doi", "url", "volume", "number", "pages", "publisher", "issn", "month"]),
    "book" => Set(["isbn", "doi", "url", "edition", "address", "series", "volume", "number", "month"]),
    "booklet" => Set(["author", "howpublished", "address", "month", "year", "url", "doi"]),
    "inbook" => Set(["chapter", "pages", "publisher", "editor", "doi", "url", "isbn", "address"]),
    "incollection" => Set(["chapter", "pages", "publisher", "editor", "doi", "url", "isbn", "address"]),
    "inproceedings" => Set(["publisher", "organization", "pages", "editor", "doi", "url", "isbn", "address"]),
    "conference" => Set(["publisher", "organization", "pages", "editor", "doi", "url", "isbn", "address"]),
    "manual" => Set(["author", "organization", "address", "edition", "month", "year", "url", "doi"]),
    "mastersthesis" => Set(["type", "address", "month", "doi", "url"]),
    "phdthesis" => Set(["type", "address", "month", "doi", "url"]),
    "proceedings" => Set(["editor", "publisher", "organization", "address", "month", "doi", "url", "isbn"]),
    "techreport" => Set(["type", "number", "address", "month", "doi", "url"]),
    "report" => Set(["type", "number", "address", "month", "doi", "url"]),
    "misc" => Set(["author", "year", "month", "note", "howpublished", "doi", "url", "urldate"]),
    "online" => Set(["author", "year", "month", "note", "howpublished", "doi", "urldate"]),
    "www" => Set(["author", "year", "month", "note", "howpublished", "doi", "urldate"]),
)

function required_field_groups(type::AbstractString)
    t = lowercase(type)
    if t == "article"
        return [["author"], ["title"], ["journal"], ["year"]]
    elseif t in ("book",)
        return [["author", "editor"], ["title"], ["publisher"], ["year"]]
    elseif t in ("inbook", "incollection")
        return [["author", "editor"], ["title"], ["booktitle"], ["year"]]
    elseif t in ("inproceedings", "conference")
        return [["author"], ["title"], ["booktitle"], ["year"]]
    elseif t in ("manual",)
        return [["title"]]
    elseif t in ("mastersthesis", "phdthesis")
        return [["author"], ["title"], ["school"], ["year"]]
    elseif t in ("proceedings",)
        return [["title"], ["year"]]
    elseif t in ("techreport", "report")
        return [["author"], ["title"], ["institution"], ["year"]]
    elseif t in ("misc", "online", "www")
        return [["title"], ["url", "howpublished"]]
    else
        return [["title"]]
    end
end

function field_importance(entry::BibEntry, field::AbstractString)
    clean = lowercase(String(field))
    clean in IGNORED_REFERENCE_FIELDS && return :ignored
    for group in required_field_groups(entry.type)
        clean in group && return :important
    end
    clean in get(SUPPLEMENTARY_FIELDS_BY_TYPE, lowercase(entry.type), Set{String}()) &&
        return :supplementary
    return :supplementary
end

function comparison_severity(entry::BibEntry, cmp::FieldComparison)
    importance = field_importance(entry, cmp.field)
    importance == :ignored && return :ignored
    cmp.status in (:exact, :normalized, :equivalent) && return :green
    cmp.status == :conflict && return :red
    cmp.status == :ambiguous && return :amber
    cmp.status == :missing_input && return importance == :important ? :red : :amber
    cmp.status == :missing_source && return :amber
    return :amber
end

function value_from_source(source::SourceRecord, field::AbstractString)
    field == "title"     && return source.title
    field == "doi"       && return source.doi
    field == "url"       && return source.url
    field == "journal"   && return source.journal
    field == "booktitle" && return source.journal
    field == "pages"     && return source.pages
    field == "publisher" && return source.publisher
    field == "year"      && return source.year
    field == "author"    && return isempty(source.authors) ? nothing : join(source.authors, " and ")
    field == "editor"    && return isempty(source.authors) ? nothing : join(source.authors, " and ")
    return nothing
end

function value_from_entry(entry::BibEntry, field::AbstractString)
    field != "url" && return get(entry.fields, String(field), nothing)
    explicit = get(entry.fields, "url", nothing)
    explicit !== nothing && return explicit
    for fallback in ("note", "howpublished")
        text = get(entry.fields, fallback, nothing)
        text === nothing && continue
        urls = urls_in_text(text)
        isempty(urls) || return first(urls)
    end
    return nothing
end

source_is_error(source::SourceRecord) = endswith(source.provider, "-error")

function compare_value(field::String, input::Union{Nothing,String}, source::Union{Nothing,String})
    input  = nonempty(input)
    source = nonempty(source)
    input === nothing && source === nothing &&
        return FieldComparison(field, :ambiguous, nothing, nothing, "no value available")
    input === nothing &&
        return FieldComparison(field, :missing_input, nothing, source, "field is missing from BibTeX")
    source === nothing &&
        return FieldComparison(field, :missing_source, input, nothing, "source metadata has no comparable value")

    if field == "doi"
        left, right = normalize_doi(input), normalize_doi(source)
        status = left == right ? :exact : :conflict
        note   = left == right ? "normalized DOI is identical" : "DOI identifiers differ"
        return FieldComparison(field, status, input, source, note)
    elseif field == "pages"
        left, right = normalize_pages(input), normalize_pages(source)
        status = left == right ? (input == source ? :exact : :normalized) : :conflict
        note   = left == right ? "page range matches after dash normalization" : "page ranges differ"
        return FieldComparison(field, status, input, source, note)
    elseif field == "year"
        left, right = normalize_year(input), normalize_year(source)
        status = !isempty(left) && left == right ? (input == source ? :exact : :normalized) : :conflict
        note   = status in (:exact, :normalized) ? "year matches" : "years differ"
        return FieldComparison(field, status, input, source, note)
    elseif field == "url"
        left, right = normalize_url(input), normalize_url(source)
        status = left == right ? (input == source ? :exact : :normalized) : :conflict
        note = left == right ? "URLs match after DOI URL canonicalization" : "URLs differ"
        return FieldComparison(field, status, input, source, note)
    elseif field in ("author", "editor")
        label = field == "editor" ? "editor" : "author"
        plural_label = label * "s"
        left, right = normalize_authors(input), normalize_authors(source)
        left_unordered, right_unordered = normalize_authors_unordered(input), normalize_authors_unordered(source)
        input_truncated = occursin(r"(?i)\bet\.?\s+al\.?", input)
        source_truncated = occursin(r"(?i)\bet\.?\s+al\.?", source)
        status = if left == right
            input == source ? :exact : :equivalent
        elseif author_signatures_match(input, source)
            :equivalent
        elseif left_unordered == right_unordered || author_signatures_match_unordered(input, source)
            :ambiguous
        elseif (input_truncated || source_truncated) &&
                !isempty(left) && !isempty(right) &&
                (occursin(first(split(left, ";")), right) || occursin(first(split(right, ";")), left))
            :ambiguous
        elseif near_match(left, right; max_ratio=0.22)
            :ambiguous
        else
            :conflict
        end
        note = if status in (:exact, :equivalent)
            "$(plural_label) are equivalent after name normalization"
        elseif status == :ambiguous &&
                (left_unordered == right_unordered || author_signatures_match_unordered(input, source))
            "$(label) names match but order differs; manual review required"
        elseif status == :ambiguous && (input_truncated || source_truncated)
            "$(label) list appears truncated with et al.; manual review required"
        elseif status == :ambiguous
            "$(label) strings are close but not identical; possible spelling difference"
        else
            "$(label) strings differ after normalization; manual review required"
        end
        return FieldComparison(field, status, input, source, note)
    else
        left, right = normalize_text(input), normalize_text(source)
        status = if input == source
            :exact
        elseif left == right
            :normalized
        elseif occursin(left, right) || occursin(right, left)
            :equivalent
        elseif field == "title" && near_match(left, right; max_ratio=0.10)
            :ambiguous
        else
            :conflict
        end
        note = if status == :conflict
            "normalized text differs"
        elseif status == :ambiguous
            "normalized text is close but not identical; possible spelling difference"
        else
            "text matches after accepted normalization"
        end
        return FieldComparison(field, status, input, source, note)
    end
end

function year_gap(left::Union{Nothing,String}, right::Union{Nothing,String})
    left === nothing && return nothing
    right === nothing && return nothing
    a = normalize_year(left)
    b = normalize_year(right)
    (isempty(a) || isempty(b)) && return nothing
    return abs(parse(Int, a) - parse(Int, b))
end

function year_hard_mismatch(entry::BibEntry, source::SourceRecord)
    gap = year_gap(get(entry.fields, "year", nothing), source.year)
    gap === nothing && return false
    return lowercase(entry.type) == "book" ? gap >= 3 : gap >= 2
end

function source_hard_mismatch(entry::BibEntry, source::SourceRecord, comparisons::Vector{FieldComparison})
    for cmp in comparisons
        if cmp.field in ("title", "author", "editor") && cmp.status == :conflict
            return true
        end
    end
    return year_hard_mismatch(entry, source)
end

function comparison_score(comparisons)
    isempty(comparisons) && return 0.0
    # :missing_source is not evidence of correctness; keep its weight low.
    weights = Dict(
        :exact          => 1.0,
        :normalized     => 0.92,
        :equivalent     => 0.75,
        :missing_source => 0.15,
        :missing_input  => 0.2,
        :ambiguous      => 0.35,
        :conflict       => 0.0,
    )
    total = 0.0
    for cmp in comparisons
        total += get(weights, cmp.status, 0.0)
    end
    return round(total / length(comparisons); digits=3)
end

function default_comparison_fields(entry::BibEntry)
    t = lowercase(entry.type)
    container_field = t in ("inproceedings", "conference", "incollection", "inbook") ?
        "booktitle" : "journal"
    creator_field = haskey(entry.fields, "editor") && !haskey(entry.fields, "author") &&
        t in ("book", "inbook", "incollection") ? "editor" : "author"
    return ["doi", "title", creator_field, "year", container_field, "pages", "publisher", "url"]
end

function source_identity(source::SourceRecord)
    source.doi !== nothing && return "doi:" * normalize_doi(source.doi)
    !isempty(source.id) && return source.provider * ":" * source.id
    source.url !== nothing && return "url:" * source.url
    source.title !== nothing && return "title:" * first(source.title, 80)
    return source.provider
end

"""
    compare_entry(entry, sources; fields=nothing)

Compare one `BibEntry` with candidate source records and return an `EntryReport`.

By default, proceedings and chapter-style entries compare their container as
`booktitle`; articles compare `journal`. Books and chapter-style entries with
an `editor` but no `author` compare `editor` as the creator field.

The comparison is tolerant for bibliographic formatting, but conflicts are still
reported explicitly. DOI values must match after DOI normalization. Author and
editor names use the same normalization, including accents and initials.

# Example

```julia
entry = BibEntry("x", "article", Dict("doi" => "10.1000/x", "title" => "A"))
source = SourceRecord(provider="fixture", doi="10.1000/x", title="A")
compare_entry(entry, [source]).confidence == 1.0
```

```julia
book = BibEntry("edited", "book", Dict("editor" => "Example, Erin", "title" => "Edited"))
src = SourceRecord(provider="fixture", title="Edited", authors=["Erin Example"])
any(cmp -> cmp.field == "editor", compare_entry(book, [src]).comparisons)
```
"""
function compare_entry(entry::BibEntry, sources::Vector{SourceRecord};
        fields = nothing)
    comparison_fields = fields === nothing ? default_comparison_fields(entry) : fields
    if isempty(sources)
        return EntryReport(entry, SourceRecord[], FieldComparison[], 0.0,
            ["no source metadata found"], String[])
    end

    provider_errors = filter(source_is_error, sources)
    usable_sources = filter(!source_is_error, sources)
    if isempty(usable_sources)
        notes = isempty(provider_errors) ? ["no source metadata found"] :
            ["provider error: $(source.provider) $(get(source.raw, "error", ""))" for source in provider_errors]
        return EntryReport(entry, sources, FieldComparison[], 0.0, notes, String[])
    end

    # The `CandidateProvider` fallback (used when no fixture, explicit
    # provider, or `use_apis=true` is configured) only ever returns the
    # entry's own title/doi/url echoed back as a "source". Comparing an entry
    # against itself cannot detect an incorrect doi, title, or author, so make
    # that limitation explicit in the report rather than letting it look like
    # an independently-verified match.
    self_comparison_only = all(s -> s.provider == "input", usable_sources)
    self_comparison_note = "no external metadata provider was queried for this entry; " *
        "it was compared only against its own bibliography fields (title/doi/url), so " *
        "this result cannot detect an incorrect doi, title, or author"

    candidates = NamedTuple[]

    for source in usable_sources
        comparisons = FieldComparison[]
        for field in comparison_fields
            input_value  = value_from_entry(entry, field)
            source_value = value_from_source(source, field)
            input_value === nothing && source_value === nothing && continue
            push!(comparisons, compare_value(field, input_value, source_value))
        end
        score = comparison_score(comparisons)
        push!(candidates, (
            source=source,
            comparisons=comparisons,
            score=score,
            reliable=!source_hard_mismatch(entry, source, comparisons),
        ))
    end

    reliable_candidates = filter(candidate -> candidate.reliable, candidates)

    discarded_notes = String[]
    for candidate in candidates
        candidate.reliable && continue
        reasons = [cmp.field for cmp in candidate.comparisons
            if cmp.field in ("title", "author", "editor") && cmp.status == :conflict]
        year_hard_mismatch(entry, candidate.source) && push!(reasons, "year")
        isempty(reasons) || push!(discarded_notes,
            "discarded $(candidate.source.provider) ($(source_identity(candidate.source))): " *
            "hard mismatch in $(join(unique(reasons), ", "))")
    end

    if isempty(reliable_candidates)
        notes = String["no reliable source metadata found"]
        self_comparison_only && push!(notes, self_comparison_note)
        append!(notes, discarded_notes)
        for source in provider_errors
            push!(notes, "provider error: $(source.provider) $(get(source.raw, "error", ""))")
        end
        return EntryReport(entry, sources, FieldComparison[], 0.0, notes, String[])
    end

    best = first(sort!(collect(reliable_candidates), by=candidate -> candidate.score, rev=true))
    best_source      = best.source
    best_comparisons = best.comparisons
    best_score       = best.score

    notes = String["best source: $(best_source.provider) ($(source_identity(best_source)))"]
    self_comparison_only && push!(notes, self_comparison_note)
    entry_doi = nonempty(get(entry.fields, "doi", nothing))
    if entry_doi !== nothing
        entry_doi_norm = normalize_doi(entry_doi)
        best_doi_norm  = best_source.doi === nothing ? nothing : normalize_doi(best_source.doi)
        if best_doi_norm != entry_doi_norm &&
                any(c -> c.source.doi !== nothing && normalize_doi(c.source.doi) == entry_doi_norm, candidates)
            push!(notes, "doi $(entry_doi) in the bibliography does not match this entry's " *
                "title/author; the best matching source was instead found by title/author " *
                "search and uses a different doi")
        end
    end
    append!(notes, discarded_notes)
    for source in provider_errors
        push!(notes, "provider error: $(source.provider) $(get(source.raw, "error", ""))")
    end
    for cmp in best_comparisons
        cmp.status in (:conflict, :ambiguous, :missing_input) &&
            push!(notes, "$(cmp.field): $(cmp.note)")
    end
    pdfs = String[]
    for source in usable_sources
        source.pdf_url !== nothing && source.pdf_url ∉ pdfs && push!(pdfs, source.pdf_url)
    end
    return EntryReport(entry, sources, best_comparisons, max(best_score, 0.0), notes, pdfs)
end
