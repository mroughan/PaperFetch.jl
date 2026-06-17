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

function field_group_label(group)
    return join(["`$(field)`" for field in group], " or ")
end

function entry_has_field(entry::BibEntry, field::AbstractString)
    value = get(entry.fields, field, nothing)
    value === nothing && return false
    return !isempty(strip(String(value)))
end

function checklist_items(report::EntryReport)
    items = NamedTuple[]
    for group in required_field_groups(report.entry.type)
        present = any(field -> entry_has_field(report.entry, field), group)
        push!(items, (
            severity = present ? :green : :red,
            field = join(group, "/"),
            message = present ?
                "Required field $(field_group_label(group)) is present" :
                "Required field $(field_group_label(group)) is missing",
        ))
    end
    for cmp in report.comparisons
        severity = comparison_severity(report.entry, cmp)
        severity == :ignored && continue
        importance = field_importance(report.entry, cmp.field)
        message = if severity == :green
            "`$(cmp.field)` matches source metadata ($(cmp.status))"
        elseif cmp.status == :conflict
            "`$(cmp.field)` conflicts with source metadata: $(cmp.note)"
        elseif cmp.status == :missing_input
            "`$(cmp.field)` is missing from BibTeX ($(importance))"
        elseif cmp.status == :missing_source
            "`$(cmp.field)` could not be verified from source metadata"
        elseif cmp.status == :ambiguous
            "`$(cmp.field)` needs manual review: $(cmp.note)"
        else
            "`$(cmp.field)` needs review: $(cmp.note)"
        end
        push!(items, (severity=severity, field=cmp.field, message=message))
    end
    return items
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
            println(io, "\nChecklist:")
            for item in checklist_items(report)
                println(io, "- $(checklist_symbol(item.severity)) $(item.message)")
            end
            println(io, "\n| Field | Status | BibTeX | Source | Note |")
            println(io, "| --- | --- | --- | --- | --- |")
            for cmp in report.comparisons
                println(io, "| $(cmp.field) | $(cmp.status) | $(markdown_escape(cmp.input)) | $(markdown_escape(cmp.source)) | $(markdown_escape(cmp.note)) |")
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
