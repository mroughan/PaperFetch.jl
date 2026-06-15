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

function value_from_source(source::SourceRecord, field::AbstractString)
    field == "title"     && return source.title
    field == "doi"       && return source.doi
    field == "url"       && return source.url
    field == "journal"   && return source.journal
    field == "pages"     && return source.pages
    field == "publisher" && return source.publisher
    field == "year"      && return source.year
    field == "author"    && return isempty(source.authors) ? nothing : join(source.authors, " and ")
    return nothing
end

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
    elseif field == "author"
        left, right = normalize_authors(input), normalize_authors(source)
        # Use :conflict when names differ (not :ambiguous); :ambiguous is for truly
        # undecidable cases, not clear disagreements.
        status = left == right ? (input == source ? :exact : :equivalent) : :conflict
        note   = left == right ? "authors are equivalent after name normalization" :
                                 "author strings differ after normalization; manual review required"
        return FieldComparison(field, status, input, source, note)
    else
        left, right = normalize_text(input), normalize_text(source)
        status = if input == source
            :exact
        elseif left == right
            :normalized
        elseif occursin(left, right) || occursin(right, left)
            :equivalent
        else
            :conflict
        end
        note = status == :conflict ? "normalized text differs" :
                                     "text matches after accepted normalization"
        return FieldComparison(field, status, input, source, note)
    end
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

function source_identity(source::SourceRecord)
    source.doi !== nothing && return "doi:" * normalize_doi(source.doi)
    !isempty(source.id) && return source.provider * ":" * source.id
    source.url !== nothing && return "url:" * source.url
    source.title !== nothing && return "title:" * normalize_text(source.title)
    return source.provider
end

"""
    compare_entry(entry, sources; fields=["doi","title","author","year","journal","pages","publisher","url"])

Compare one `BibEntry` with candidate source records and return an `EntryReport`.

# Example

```julia
entry = BibEntry("x", "article", Dict("doi" => "10.1000/x", "title" => "A"))
source = SourceRecord(provider="fixture", doi="10.1000/x", title="A")
compare_entry(entry, [source]).confidence == 1.0
```
"""
function compare_entry(entry::BibEntry, sources::Vector{SourceRecord};
        fields = ["doi", "title", "author", "year", "journal", "pages", "publisher", "url"])
    if isempty(sources)
        return EntryReport(entry, SourceRecord[], FieldComparison[], 0.0,
            ["no source metadata found"], String[])
    end

    best_source      = first(sources)
    best_comparisons = FieldComparison[]
    best_score       = -1.0

    for source in sources
        comparisons = FieldComparison[]
        for field in fields
            input_value  = get(entry.fields, field, nothing)
            source_value = value_from_source(source, field)
            input_value === nothing && source_value === nothing && continue
            push!(comparisons, compare_value(field, input_value, source_value))
        end
        score = comparison_score(comparisons)
        if score > best_score
            best_score       = score
            best_source      = source
            best_comparisons = comparisons
        end
    end

    notes = String["best source: $(best_source.provider) ($(source_identity(best_source)))"]
    for cmp in best_comparisons
        cmp.status in (:conflict, :ambiguous, :missing_input) &&
            push!(notes, "$(cmp.field): $(cmp.note)")
    end
    pdfs = String[]
    for source in sources
        source.pdf_url !== nothing && source.pdf_url ∉ pdfs && push!(pdfs, source.pdf_url)
    end
    return EntryReport(entry, sources, best_comparisons, max(best_score, 0.0), notes, pdfs)
end
