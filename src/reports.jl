function markdown_escape(value)
    value === nothing && return ""
    return replace(String(value), "|" => "\\|", "\n" => " ")
end

function checklist_symbol(severity::Symbol)
    severity == :green && return "✅"
    severity == :red && return "❌"
    severity == :amber && return "⚠️"
    return "•"
end

function flag_text(severity::Symbol)
    return "$(checklist_symbol(severity)) $(severity)"
end

function field_group_label(group)
    return join(["`$(field)`" for field in group], " or ")
end

function entry_has_field(entry::BibEntry, field::AbstractString)
    value = get(entry.fields, field, nothing)
    value === nothing && return false
    return !isempty(strip(String(value)))
end

function missing_required_field_groups(report::EntryReport)
    missing = Vector{Vector{String}}()
    for group in required_field_groups(report.entry.type)
        present = any(field -> entry_has_field(report.entry, field), group)
        present || push!(missing, group)
    end
    return missing
end

function general_flag_items(report::EntryReport)
    items = NamedTuple[]
    usable_sources = filter(!source_is_error, report.sources)
    error_sources = filter(source_is_error, report.sources)
    missing_required = missing_required_field_groups(report)

    source_severity = if !isempty(usable_sources)
        :green
    elseif isempty(report.sources)
        :red
    else
        :amber
    end
    source_message = if !isempty(usable_sources)
        "source metadata found from $(join(unique([s.provider for s in usable_sources]), ", "))"
    elseif isempty(report.sources)
        "no source metadata was found"
    else
        "only provider errors were returned"
    end
    push!(items, (flag="Source metadata", severity=source_severity, message=source_message))

    provider_message = isempty(error_sources) ?
        "no provider errors recorded" :
        "provider errors from $(join(unique([s.provider for s in error_sources]), ", "))"
    push!(items, (flag="Provider errors", severity=isempty(error_sources) ? :green : :amber,
        message=provider_message))

    required_message = isempty(missing_required) ?
        "all required field groups are present" :
        "missing required field group(s): " *
            join([field_group_label(group) for group in missing_required], "; ")
    push!(items, (flag="Required fields", severity=isempty(missing_required) ? :green : :red,
        message=required_message))

    comparison_message = isempty(report.comparisons) ?
        "no field comparisons were possible" :
        "$(length(report.comparisons)) field comparison(s) made"
    push!(items, (flag="Field comparisons", severity=isempty(report.comparisons) ? :red : :green,
        message=comparison_message))

    pdf_message = isempty(report.pdf_candidates) ?
        "no PDF candidate found; this is not necessarily an error" :
        "$(length(report.pdf_candidates)) PDF candidate(s) found"
    push!(items, (flag="PDF candidates", severity=isempty(report.pdf_candidates) ? :amber : :green,
        message=pdf_message))

    confidence_severity = report.confidence >= 0.8 ? :green :
        report.confidence > 0 ? :amber : :red
    push!(items, (flag="Confidence", severity=confidence_severity,
        message="confidence score $(report.confidence)"))

    return items
end

function field_flag_note(entry::BibEntry, cmp::FieldComparison)
    severity = comparison_severity(entry, cmp)
    severity == :ignored && return ""
    importance = field_importance(entry, cmp.field)
    if severity == :green
        return "`$(cmp.field)` matches source metadata ($(cmp.status))"
    elseif cmp.status == :conflict
        return "`$(cmp.field)` conflicts with source metadata: $(cmp.note)"
    elseif cmp.status == :missing_input
        return "`$(cmp.field)` is missing from BibTeX ($(importance))"
    elseif cmp.status == :missing_source
        return "`$(cmp.field)` could not be verified from source metadata"
    elseif cmp.status == :ambiguous
        return "`$(cmp.field)` needs manual review: $(cmp.note)"
    end
    return "`$(cmp.field)` needs review: $(cmp.note)"
end

function write_markdown(path::AbstractString, reports::Vector{EntryReport})
    open(path, "w") do io
        println(io, "# PaperFetch Report\n")
        println(io, "Generated: $(Dates.now())\n")
        for report in reports
            println(io, "## $(report.entry.key)\n")
            println(io, "- Type: `$(report.entry.type)`")
            println(io, "- Confidence: $(report.confidence)")
            for note in report.notes
                println(io, "- Note: $(note)")
            end
            println(io, "\nGeneral flags:")
            println(io, "\n| Flag | Status | Diagnostic |")
            println(io, "| --- | --- | --- |")
            for item in general_flag_items(report)
                println(io, "| $(markdown_escape(item.flag)) | $(markdown_escape(flag_text(item.severity))) | $(markdown_escape(item.message)) |")
            end
            println(io, "\n| Flag | Field | Importance | Status | BibTeX | Source | Note |")
            println(io, "| --- | --- | --- | --- | --- | --- | --- |")
            for cmp in report.comparisons
                severity = comparison_severity(report.entry, cmp)
                importance = field_importance(report.entry, cmp.field)
                note = field_flag_note(report.entry, cmp)
                isempty(note) && (note = cmp.note)
                println(io, "| $(markdown_escape(flag_text(severity))) | $(markdown_escape(cmp.field)) | " *
                    "$(markdown_escape(importance)) | $(markdown_escape(cmp.status)) | " *
                    "$(markdown_escape(cmp.input)) | $(markdown_escape(cmp.source)) | " *
                    "$(markdown_escape(note)) |")
            end
            if !isempty(report.pdf_candidates)
                println(io, "\nPDF candidates:")
                for url in report.pdf_candidates
                    println(io, "- $(url)")
                end
            end
            println(io)
        end
    end
    return path
end

function comparison_rows(reports::Vector{EntryReport})
    rows = NamedTuple[]
    for report in reports
        if isempty(report.comparisons)
            push!(rows, (
                key=report.entry.key,
                type=report.entry.type,
                confidence=report.confidence,
                field="",
                importance="",
                severity="red",
                status="no_comparison",
                bibtex="",
                source="",
                note=isempty(report.notes) ? "no comparison performed" : first(report.notes),
                providers=join([s.provider for s in report.sources], ";"),
            ))
            continue
        end
        for cmp in report.comparisons
            push!(rows, (
                key=report.entry.key,
                type=report.entry.type,
                confidence=report.confidence,
                field=cmp.field,
                importance=String(field_importance(report.entry, cmp.field)),
                severity=String(comparison_severity(report.entry, cmp)),
                status=String(cmp.status),
                bibtex=something(cmp.input, ""),
                source=something(cmp.source, ""),
                note=cmp.note,
                providers=join([s.provider for s in report.sources], ";"),
            ))
        end
    end
    return rows
end

function write_inc(path::AbstractString, reports::Vector{EntryReport})
    rows = comparison_rows(reports)
    metadata = Dict(
        "title"     => "PaperFetch bibliography validation report",
        "generated" => string(Dates.now()),
        "tool"      => "PaperFetch.jl",
        "columns"   => Dict(
            "key"        => "BibTeX entry key",
            "type"       => "BibTeX entry type",
            "confidence" => "Record-level confidence score from 0 to 1",
            "field"      => "Compared field",
            "importance" => "Citation importance of the field: important, supplementary, or ignored",
            "severity"   => "Checklist severity for this comparison: green, amber, red, or ignored",
            "status"     => "Comparison status",
            "bibtex"     => "Input BibTeX value",
            "source"     => "Source metadata value",
            "note"       => "Human-readable comparison note",
            "providers"  => "Source metadata providers consulted",
        ),
    )
    IncCSV.writeinc(path, rows; metadata)
    return path
end

"""
    write_reports(reports, outdir; basename="paperfetch_report")

Write Markdown and INC reports for `reports`.

The default basename is `paperfetch_report` for direct API calls. CLI-generated
reports use the input file stem unless `--report-basename` is supplied. Pass
`basename` explicitly when a different output name is needed.

Markdown reports include entry-level general flags and field-level comparison
flags. INC reports contain one row per compared field, or one red
`no_comparison` row when no source comparison was possible.

# Example

```julia
entry = BibEntry("x", "misc", Dict("title" => "Example"))
report = EntryReport(entry, SourceRecord[], FieldComparison[], 0.0, String[], String[])
paths = write_reports([report], mktempdir())
haskey(paths, :markdown) && haskey(paths, :inc)
```
"""
function write_reports(reports::Vector{EntryReport}, outdir::AbstractString;
        basename::AbstractString="paperfetch_report")
    mkpath(outdir)
    md  = write_markdown(joinpath(outdir, string(basename, ".md")),  reports)
    inc = write_inc(     joinpath(outdir, string(basename, ".inc")), reports)
    return Dict(:markdown => md, :inc => inc)
end
