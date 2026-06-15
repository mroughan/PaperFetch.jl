function markdown_escape(value)
    value === nothing && return ""
    return replace(String(value), "|" => "\\|", "\n" => " ")
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
        for cmp in report.comparisons
            push!(rows, (
                key=report.entry.key,
                type=report.entry.type,
                confidence=report.confidence,
                field=cmp.field,
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
