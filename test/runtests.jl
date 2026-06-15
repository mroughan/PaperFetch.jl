using HTTP
using IncCSV
using PaperFetch
using Test

const EXAMPLES = joinpath(@__DIR__, "..", "examples")
const FIXTURE  = joinpath(EXAMPLES, "metadata_fixture.json")

example(name) = joinpath(EXAMPLES, name)

@testset "normalization" begin
    @test normalize_doi("https://doi.org/10.1000/ABC") == "10.1000/abc"
    @test normalize_doi("doi: 10.1000/ABC") == "10.1000/abc"
    @test normalize_text("{Caf\\'e} Data") == "cafe data"
    @test normalize_text("Cafe-data") == "cafe data"
end

@testset "normalization helpers" begin
    @test PaperFetch.normalize_pages("123 -- 130") == "123-130"
    @test PaperFetch.normalize_pages("123--130")   == "123-130"
    @test PaperFetch.normalize_pages("123-130")    == "123-130"

    @test PaperFetch.normalize_year("2020") == "2020"
    @test PaperFetch.normalize_year("Published in 2020, online") == "2020"
    @test PaperFetch.normalize_year("no year here") == ""

    @test PaperFetch.normalize_authors("Smith, J. and Doe, J.") ==
          PaperFetch.normalize_authors("Doe, J. and Smith, J.")
    @test !isempty(PaperFetch.normalize_authors("Smith, J. and Doe, J."))

    @test PaperFetch.comparison_score(FieldComparison[]) == 0.0
    @test PaperFetch.comparison_score([FieldComparison("doi", :exact, "x", "x", "")]) == 1.0
    @test PaperFetch.comparison_score([FieldComparison("doi", :conflict, "x", "y", "")]) == 0.0
    @test PaperFetch.comparison_score([
        FieldComparison("doi",   :exact,    "x", "x", ""),
        FieldComparison("title", :conflict, "a", "b", ""),
    ]) == 0.5

    # :missing_source weight must be ≤ 0.2 after the fix
    score_missing = PaperFetch.comparison_score(
        [FieldComparison("doi", :missing_source, "x", nothing, "")])
    @test score_missing <= 0.2
end

@testset "compare_value author mismatch" begin
    # Differing author strings should give :conflict, not :ambiguous
    cmp = PaperFetch.compare_value("author", "Smith, J.", "Jones, A.")
    @test cmp.status == :conflict

    # Matching (order-invariant) author strings should give :equivalent or :exact
    cmp2 = PaperFetch.compare_value("author", "Jane Doe and John Smith", "John Smith and Jane Doe")
    @test cmp2.status in (:exact, :equivalent)
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
    # Keys are item1, item2, … regardless of blank lines or comments
    @test plain[1].key == "item1"
    @test plain[2].key == "item2"
end

@testset "WorkIdentifier extraction" begin
    e_doi = BibEntry("x", "article", Dict("doi" => "https://doi.org/10.1000/ABC"))
    ids   = extract_identifiers(e_doi)
    @test length(ids) == 1
    @test ids[1].kind  == :doi
    @test ids[1].value == "10.1000/abc"

    e_arxiv = BibEntry("y", "misc", Dict(
        "eprint"        => "2401.01234",
        "archiveprefix" => "arXiv",
        "url"           => "https://arxiv.org/abs/2401.01234",
    ))
    ids_ax = extract_identifiers(e_arxiv)
    kinds  = [id.kind for id in ids_ax]
    @test :arxiv in kinds
    @test :url   in kinds
    arxiv_id = first(id for id in ids_ax if id.kind == :arxiv)
    @test arxiv_id.value == "2401.01234"

    e_isbn   = BibEntry("z", "book", Dict("isbn" => "978-3-16-148410-0"))
    ids_isbn = extract_identifiers(e_isbn)
    @test any(id -> id.kind == :isbn, ids_isbn)
end

@testset "comparison statuses from examples" begin
    cases = Dict(
        "01_exact_article.bib"     => [:exact],
        "02_title_case_article.bib"=> [:normalized],
        "03_latex_accents.bib"     => [:normalized, :equivalent],
        "04_missing_doi.bib"       => [:missing_input],
        "05_conflicting_doi.bib"   => [:conflict],
        "06_web_reference.bib"     => [:exact],
        "07_dataset_reference.bib" => [:exact],
        "08_arxiv_preprint.bib"    => [:exact],
        "09_book_chapter.bib"      => [:exact],
        "10_online_report.bib"     => [:missing_input],
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
    outdir  = mktempdir()
    paths   = write_reports(reports, outdir)

    @test isfile(paths[:markdown])
    @test isfile(paths[:inc])
    @test occursin("doe2020exact", read(paths[:markdown], String))

    inc  = IncCSV.readinc(paths[:inc])
    @test IncCSV.metadata(inc)["title"] == "PaperFetch bibliography validation report"
    rows = collect(IncCSV.table(inc))
    @test length(rows) >= 1
end

@testset "fetch manifests" begin
    reports = check_bibliography(example("01_exact_article.bib"); fixture=FIXTURE, check=:none)
    outdir  = mktempdir()

    fake_get(_url, _headers; _kwargs...) =
        HTTP.Response(200, ["Content-Type" => "application/pdf"],
                      body=Vector{UInt8}("%PDF-1.4\nfixture\n"))

    results, manifest = fetch_pdfs(reports, outdir; http_get=fake_get)
    @test isfile(manifest)
    @test any(result -> result.status == "downloaded", results)
    downloaded = first(result for result in results if result.status == "downloaded")
    @test isfile(downloaded.file)
    @test downloaded.sha256 !== nothing

    no_pdf_entry  = BibEntry("no_pdf", "misc", Dict("title" => "No PDF"))
    no_pdf_report = EntryReport(no_pdf_entry, SourceRecord[], FieldComparison[], 0.0, String[], String[])
    skipped, _    = fetch_pdfs([no_pdf_report], mktempdir(); http_get=fake_get)
    @test skipped[1].status == "skipped"
end

@testset "cookie and proxy helpers" begin
    # Standard Netscape cookies.txt format
    cookiefile = tempname()
    write(cookiefile, ".example.org\tFALSE\t/\tFALSE\t0\tsession\tabc123\n")
    cookies = PaperFetch.read_cookie_file(cookiefile)
    @test haskey(cookies, ".example.org")
    @test occursin("abc123", cookies[".example.org"])

    # Matching subdomain
    cookie = PaperFetch.cookie_for_url(cookies, "https://www.example.org/page")
    @test cookie !== nothing
    @test occursin("abc123", cookie)

    # Non-matching host returns nothing
    @test PaperFetch.cookie_for_url(cookies, "https://other.com/page") === nothing

    # #HttpOnly_ prefix is stripped
    hf = tempname()
    write(hf, "#HttpOnly_.secure.org\tFALSE\t/\tTRUE\t0\ttoken\txyz\n")
    c2 = PaperFetch.read_cookie_file(hf)
    @test haskey(c2, ".secure.org")
    @test occursin("xyz", c2[".secure.org"])

    # Nothing path returns empty dict
    @test PaperFetch.read_cookie_file(nothing) == Dict{String,String}()

    # proxied_url with no proxy returns original URL
    @test PaperFetch.proxied_url("https://example.org/paper.pdf", nothing) ==
          "https://example.org/paper.pdf"

    # {url} template substitution
    out = PaperFetch.proxied_url("https://example.org/paper.pdf",
                                  "https://proxy.edu/login?url={url}")
    @test occursin("proxy.edu", out)
    @test occursin("example.org", out)

    # Append-style template (no {url} placeholder)
    out2 = PaperFetch.proxied_url("https://example.org/x", "https://proxy.edu/login?url=")
    @test startswith(out2, "https://proxy.edu/login?url=")
end

@testset "CLI check mode" begin
    outdir = mktempdir()
    PaperFetch.main(["check", example("01_exact_article.bib"), "--fixture", FIXTURE, "--outdir", outdir])
    @test isfile(joinpath(outdir, "paperfetch_report.md"))
    @test isfile(joinpath(outdir, "paperfetch_report.inc"))
end
