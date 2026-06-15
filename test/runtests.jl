using HTTP
using IncCSV
using PaperFetch
using Test

const EXAMPLES = joinpath(@__DIR__, "..", "examples")
const FIXTURE = joinpath(EXAMPLES, "metadata_fixture.json")

example(name) = joinpath(EXAMPLES, name)

@testset "normalization" begin
    @test normalize_doi("https://doi.org/10.1000/ABC") == "10.1000/abc"
    @test normalize_doi("doi: 10.1000/ABC") == "10.1000/abc"
    @test normalize_text("{Caf\\'e} Data") == "cafe data"
    @test normalize_text("Cafe-data") == "cafe data"
end

@testset "BibTeX and plain input" begin
    entries = read_bibtex(example("01_exact_article.bib"); check=:none)
    @test length(entries) == 1
    @test entries[1].key == "doe2020exact"
    @test entries[1].type == "article"
    @test entries[1].fields["doi"] == "10.1000/exact.2020"
    @test entries[1].fields["author"] == "Jane Doe and John Smith"

    plain = read_items(example("11_plain_dois.txt"); check=:none)
    @test length(plain) == 2
    @test plain[1].fields["doi"] == "10.1000/exact.2020"
    @test plain[2].fields["doi"] == "10.1000/dataset.2023"
end

@testset "comparison statuses from examples" begin
    cases = Dict(
        "01_exact_article.bib" => [:exact],
        "02_title_case_article.bib" => [:normalized],
        "03_latex_accents.bib" => [:normalized, :equivalent],
        "04_missing_doi.bib" => [:missing_input],
        "05_conflicting_doi.bib" => [:conflict],
        "06_web_reference.bib" => [:exact],
        "07_dataset_reference.bib" => [:exact],
        "08_arxiv_preprint.bib" => [:exact],
        "09_book_chapter.bib" => [:exact],
        "10_online_report.bib" => [:missing_input],
    )

    for (file, expected_statuses) in cases
        reports = check_bibliography(example(file); fixture=FIXTURE, check=:none)
        @test length(reports) == 1
        statuses = [comparison.status for comparison in reports[1].comparisons]
        for status in expected_statuses
            @test status in statuses
        end
        @test 0.0 <= reports[1].confidence <= 1.0
    end
end

@testset "reports" begin
    reports = check_bibliography(example("01_exact_article.bib"); fixture=FIXTURE, check=:none)
    outdir = mktempdir()
    paths = write_reports(reports, outdir)

    @test isfile(paths[:markdown])
    @test isfile(paths[:inc])
    @test occursin("doe2020exact", read(paths[:markdown], String))

    inc = IncCSV.readinc(paths[:inc])
    @test IncCSV.metadata(inc)["title"] == "PaperFetch bibliography validation report"
    rows = collect(IncCSV.table(inc))
    @test length(rows) >= 1
end

@testset "fetch manifests" begin
    reports = check_bibliography(example("01_exact_article.bib"); fixture=FIXTURE, check=:none)
    outdir = mktempdir()

    fake_get(url, headers; redirect=true, readtimeout=60, status_exception=false) =
        HTTP.Response(200, ["Content-Type" => "application/pdf"], body=Vector{UInt8}("%PDF-1.4\nfixture\n"))

    results, manifest = fetch_pdfs(reports, outdir; http_get=fake_get)
    @test isfile(manifest)
    @test any(result -> result.status == "downloaded", results)
    downloaded = first(result for result in results if result.status == "downloaded")
    @test isfile(downloaded.file)
    @test downloaded.sha256 !== nothing

    no_pdf_entry = BibEntry("no_pdf", "misc", Dict("title" => "No PDF"))
    no_pdf_report = EntryReport(no_pdf_entry, SourceRecord[], FieldComparison[], 0.0, String[], String[])
    skipped, _ = fetch_pdfs([no_pdf_report], mktempdir(); http_get=fake_get)
    @test skipped[1].status == "skipped"
end

@testset "CLI check mode" begin
    outdir = mktempdir()
    PaperFetch.main(["check", example("01_exact_article.bib"), "--fixture", FIXTURE, "--outdir", outdir])
    @test isfile(joinpath(outdir, "paperfetch_report.md"))
    @test isfile(joinpath(outdir, "paperfetch_report.inc"))
end
