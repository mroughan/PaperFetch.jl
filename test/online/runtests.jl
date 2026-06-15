using PaperFetch
using Test

const ONLINE_ENABLED = lowercase(get(ENV, "PAPERFETCH_ONLINE", "false")) in ("1", "true", "yes")
const CONTACT_EMAIL = get(ENV, "PAPERFETCH_EMAIL", "")
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const ONLINE_BIB = joinpath(ROOT, "examples", "online", "field_tests.bib")

function successful_sources(report)
    return filter(source -> !endswith(source.provider, "-error"), report.sources)
end

function has_exact_doi(report)
    return any(comparison -> comparison.field == "doi" && comparison.status == :exact,
        report.comparisons)
end

if !ONLINE_ENABLED
    @info "Skipping online PaperFetch tests. Set PAPERFETCH_ONLINE=true and PAPERFETCH_EMAIL=you@example.edu to run them."
    exit()
end

isempty(CONTACT_EMAIL) && error("Set PAPERFETCH_EMAIL before running online tests.")

@testset "online field tests" begin
    reports = check_bibliography(ONLINE_BIB; use_apis=true, email=CONTACT_EMAIL, check=:none)

    @test length(reports) == 3

    for report in reports
        @test !isempty(successful_sources(report))
        @test has_exact_doi(report)
        @test report.confidence >= 0.45
    end

    @test any(report -> !isempty(report.pdf_candidates), reports)

    outdir = mktempdir()
    paths = write_reports(reports, outdir; basename="online_field_report")
    @test isfile(paths[:markdown])
    @test isfile(paths[:inc])
end
