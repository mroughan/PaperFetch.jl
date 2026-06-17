using HTTP
using IncCSV
using JSON3
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
    @test PaperFetch.normalize_authors("García, Ana and Müller, Max") ==
          PaperFetch.normalize_authors("Muller, Max and Garcia, Ana")
    @test PaperFetch.normalize_authors("Smith, Jane et al.") ==
          PaperFetch.normalize_authors("Smith, Jane")
    @test !isempty(PaperFetch.normalize_authors("Smith, J. and Doe, J."))
    @test PaperFetch.near_match("bibliography checking", "bibliogrpahy checking")
    @test !PaperFetch.near_match("bibliography checking", "network calculus")

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

    cmp3 = PaperFetch.compare_value("author", "García, Ana and Müller, Max", "Ana Garcia and Max Muller")
    @test cmp3.status in (:exact, :equivalent)

    cmp4 = PaperFetch.compare_value("author", "Jane Smith et al.", "Jane Smith and John Doe and Ana Garcia")
    @test cmp4.status == :ambiguous

    cmp5 = PaperFetch.compare_value("author", "Jane Smiht", "Jane Smith")
    @test cmp5.status == :ambiguous

    title_cmp = PaperFetch.compare_value("title", "A small bibliogrpahy checker", "A small bibliography checker")
    @test title_cmp.status == :ambiguous
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

    e_note = BibEntry("note_doi", "article", Dict(
        "title" => "DOI in the wrong field",
        "note" => "Published as doi:10.1234/ABC.DEF.",
    ))
    ids_note = extract_identifiers(e_note)
    @test any(id -> id.kind == :doi && id.value == "10.1234/abc.def", ids_note)

    e_url = BibEntry("url_doi", "article", Dict(
        "url" => "https://doi.org/10.7554/eLife.32822",
    ))
    ids_url = extract_identifiers(e_url)
    @test any(id -> id.kind == :doi && id.value == "10.7554/elife.32822", ids_url)
    @test any(id -> id.kind == :url, ids_url)

    e_latex_note = BibEntry("latex_note_doi", "article", Dict(
        "note" => raw"DOI: \url{10.1007/s10489-019-01592-4}",
    ))
    ids_latex = extract_identifiers(e_latex_note)
    @test any(id -> id.kind == :doi && id.value == "10.1007/s10489-019-01592-4", ids_latex)

    e_note_url = BibEntry("note_url", "misc", Dict(
        "note" => raw"Archived at \url{https://example.org/report.pdf}.",
    ))
    ids_note_url = extract_identifiers(e_note_url)
    @test any(id -> id.kind == :url && id.value == "https://example.org/report.pdf", ids_note_url)

    e_arxiv_note = BibEntry("arxiv_note", "misc", Dict(
        "note" => "Preprint: arXiv:2401.01234v2",
    ))
    ids_arxiv_note = extract_identifiers(e_arxiv_note)
    @test any(id -> id.kind == :arxiv && id.value == "2401.01234v2", ids_arxiv_note)
end

@testset "API fallback lookup paths" begin
    calls = String[]
    function fake_json(url; headers=Pair{String,String}[])
        push!(calls, url)
        if occursin("api.crossref.org/works?", url)
            return JSON3.read("""
            {"message":{"items":[{
              "DOI":"10.1234/title-search",
              "title":["Fallback Search Paper"],
              "author":[{"given":"Erin","family":"Example"}],
              "URL":"https://doi.org/10.1234/title-search",
              "container-title":["Journal of Checks"],
              "page":"10-20",
              "publisher":"Example Press"
            }]}}
            """)
        elseif occursin("api.openalex.org/works?search=", url)
            return JSON3.read("""{"results":[]}""")
        elseif occursin("api.semanticscholar.org/graph/v1/paper/search", url)
            return JSON3.read("""{"data":[]}""")
        elseif occursin("eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi", url)
            return JSON3.read("""{"esearchresult":{"idlist":[]}}""")
        elseif occursin("eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi", url)
            return JSON3.read("""{"result":{}}""")
        elseif occursin("api.core.ac.uk/v3/search/works", url)
            return JSON3.read("""{"results":[]}""")
        elseif occursin("api.figshare.com/v2/articles/search", url)
            return JSON3.read("""[]""")
        elseif occursin("openlibrary.org/search.json", url)
            return JSON3.read("""
            {"docs":[{
              "key":"/works/OL1W",
              "title":"Fallback Book",
              "author_name":["Bert Book"],
              "first_publish_year":2020,
              "publisher":["Library Press"],
              "isbn":["9780000000001"]
            }]}
            """)
        elseif occursin("www.googleapis.com/books", url)
            return JSON3.read("""
            {"items":[{"id":"gb1","volumeInfo":{
              "title":"Fallback Book",
              "authors":["Bert Book"],
              "publishedDate":"2020",
              "publisher":"Google Press",
              "infoLink":"https://books.example/fallback"
            }}]}
            """)
        else
            return JSON3.read("{}")
        end
    end
    fake_text(url; headers=Pair{String,String}[]) = begin
        push!(calls, url)
        return "<feed></feed>"
    end

    provider = PaperFetch.ApiProvider(get_json=fake_json, get_text=fake_text)
    article = BibEntry("no_doi_search", "article", Dict(
        "title" => "Fallback Search Paper",
        "author" => "Example, Erin",
        "year" => "2024",
    ))
    article_sources = PaperFetch.sources_for(provider, article)
    @test any(source -> source.provider == "crossref-search" &&
        source.doi == "10.1234/title-search", article_sources)
    @test any(url -> occursin("query.bibliographic=", url), calls)

    book = BibEntry("book_search", "book", Dict(
        "title" => "Fallback Book",
        "author" => "Bert Book",
    ))
    book_sources = PaperFetch.sources_for(provider, book)
    @test any(source -> source.provider == "openlibrary-search" &&
        source.publisher == "Library Press", book_sources)
    @test any(source -> source.provider == "google-books" &&
        source.publisher == "Google Press", book_sources)
end

@testset "additional provider adapters" begin
    calls = String[]
    function fake_json(url; headers=Pair{String,String}[])
        push!(calls, url)
        if occursin("api.crossref.org/works/", url)
            return JSON3.read("{}")
        elseif occursin("api.openalex.org/works/doi:", url)
            return JSON3.read("{}")
        elseif occursin("api.unpaywall.org", url)
            return JSON3.read("{}")
        elseif occursin("api.datacite.org", url)
            return JSON3.read("{}")
        elseif occursin("api.semanticscholar.org/graph/v1/paper/DOI:", url)
            return JSON3.read("""
            {
              "paperId":"S2-1",
              "title":"Extra API Paper",
              "year":2024,
              "authors":[{"name":"Sam Semantic"}],
              "externalIds":{"DOI":"10.2222/extra"},
              "url":"https://www.semanticscholar.org/paper/S2-1",
              "venue":"API Journal",
              "openAccessPdf":{"url":"https://example.org/semantic.pdf"}
            }
            """)
        elseif occursin("api.semanticscholar.org/graph/v1/paper/search", url)
            return JSON3.read("""
            {"data":[{
              "paperId":"S2-2",
              "title":"Title Search Extra",
              "year":2023,
              "authors":[{"name":"Tara Title"}],
              "externalIds":{"DOI":"10.2222/title"},
              "url":"https://www.semanticscholar.org/paper/S2-2",
              "venue":"Search Journal"
            }]}
            """)
        elseif occursin("eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi", url)
            return JSON3.read("""{"esearchresult":{"idlist":["12345678"]}}""")
        elseif occursin("eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi", url)
            return JSON3.read("""
            {"result":{"12345678":{
              "uid":"12345678",
              "title":"PubMed Extra",
              "pubdate":"2024 Jan",
              "source":"PubMed Journal",
              "fulljournalname":"PubMed Journal Expanded",
              "pages":"1-2",
              "authors":[{"name":"Pat PubMed"}],
              "articleids":[{"idtype":"doi","value":"10.2222/pubmed"}]
            }}}
            """)
        elseif occursin("api.core.ac.uk/v3/search/works", url)
            return JSON3.read("""
            {"results":[{
              "id":987,
              "title":"CORE Extra",
              "authors":[{"name":"Cora Core"}],
              "yearPublished":2022,
              "doi":"10.2222/core",
              "publisher":"Repository Press",
              "downloadUrl":"https://example.org/core.pdf",
              "sourceFulltextUrls":["https://example.org/core"]
            }]}
            """)
        elseif occursin("api.figshare.com/v2/articles/search", url)
            return JSON3.read("""[{"id":321,"title":"Figshare Extra"}]""")
        elseif occursin("api.figshare.com/v2/articles/321", url)
            return JSON3.read("""
            {
              "id":321,
              "title":"Figshare Extra",
              "doi":"10.2222/figshare",
              "published_date":"2021-02-03T00:00:00Z",
              "url_public_html":"https://figshare.com/articles/321",
              "authors":[{"full_name":"Fiona Figshare"}],
              "files":[{"name":"paper.pdf","mime_type":"application/pdf","download_url":"https://example.org/figshare.pdf"}]
            }
            """)
        else
            return JSON3.read("{}")
        end
    end
    fake_text(url; headers=Pair{String,String}[]) = "<feed></feed>"

    provider = PaperFetch.ApiProvider(get_json=fake_json, get_text=fake_text)
    doi_entry = BibEntry("extra_doi", "article", Dict(
        "doi" => "10.2222/extra",
        "title" => "Extra API Paper",
    ))
    doi_sources = PaperFetch.sources_for(provider, doi_entry)
    @test any(source -> source.provider == "semantic-scholar" &&
        source.pdf_url == "https://example.org/semantic.pdf", doi_sources)
    @test any(source -> source.provider == "pubmed" &&
        source.doi == "10.2222/pubmed", doi_sources)
    @test any(source -> source.provider == "core" &&
        source.pdf_url == "https://example.org/core.pdf", doi_sources)
    @test any(source -> source.provider == "figshare" &&
        source.pdf_url == "https://example.org/figshare.pdf", doi_sources)

    pmid_entry = BibEntry("pmid_entry", "article", Dict(
        "pmid" => "12345678",
        "title" => "PubMed Extra",
    ))
    pmid_ids = extract_identifiers(pmid_entry)
    @test any(id -> id.kind == :pmid && id.value == "12345678", pmid_ids)
    pmid_sources = PaperFetch.sources_for(provider, pmid_entry)
    @test any(source -> source.provider == "pubmed" &&
        source.url == "https://pubmed.ncbi.nlm.nih.gov/12345678/", pmid_sources)

    title_entry = BibEntry("title_extra", "article", Dict(
        "title" => "Title Search Extra",
        "author" => "Title, Tara",
    ))
    title_sources = PaperFetch.sources_for(provider, title_entry)
    @test any(source -> source.provider == "semantic-scholar-search" &&
        source.doi == "10.2222/title", title_sources)
end

@testset "URL metadata and direct PDF lookup" begin
    function fake_text(url; headers=Pair{String,String}[])
        if endswith(url, ".pdf")
            return "%PDF-1.7\nfixture"
        end
        return """
        <html><head>
          <meta name="citation_title" content="URL Metadata Paper">
          <meta name="citation_author" content="Uma URL">
          <meta name="citation_doi" content="10.5555/url-meta">
          <meta name="citation_pdf_url" content="https://example.org/paper.pdf">
        </head></html>
        """
    end
    provider = PaperFetch.ApiProvider(get_text=fake_text,
        get_json=(url; headers=Pair{String,String}[]) -> JSON3.read("{}"))

    html_entry = BibEntry("url_meta", "misc", Dict(
        "title" => "URL Metadata Paper",
        "note" => raw"See \url{https://example.org/paper}",
    ))
    html_sources = PaperFetch.sources_for(provider, html_entry)
    @test any(source -> source.provider == "url-metadata" &&
        source.doi == "10.5555/url-meta" &&
        source.pdf_url == "https://example.org/paper.pdf", html_sources)

    pdf_entry = BibEntry("url_pdf", "misc", Dict(
        "title" => "Direct PDF",
        "url" => "https://example.org/direct.pdf",
    ))
    pdf_sources = PaperFetch.sources_for(provider, pdf_entry)
    @test any(source -> source.provider == "url-pdf" &&
        source.pdf_url == "https://example.org/direct.pdf", pdf_sources)
end

@testset "provider URL construction and errors" begin
    @test PaperFetch.doi_api_path("10.7554/eLife.32822") == "10.7554/elife.32822"
    @test PaperFetch.doi_api_path("https://doi.org/10.5281/zenodo.1234") ==
          "10.5281/zenodo.1234"

    err_source = SourceRecord(provider="crossref-error", doi="10.1000/x",
        raw=Dict{String,Any}("error" => "HTTP 404"))
    report = compare_entry(BibEntry("x", "article", Dict("doi" => "10.1000/x")), [err_source])
    @test report.confidence == 0.0
    @test isempty(report.comparisons)
    @test any(note -> occursin("provider error", note), report.notes)
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

@testset "misplaced DOI bibliography lookup" begin
    dir = mktempdir()
    bib = joinpath(dir, "misplaced.bib")
    fixture = joinpath(dir, "fixture.json")
    write(bib, """
    @article{wrongfield,
      author = {Example, Erin},
      title = {DOI In The Notes Field},
      year = {2024},
      note = {The DOI is https://doi.org/10.9999/wrongfield.2024}
    }
    """)
    write(fixture, """
    {"records":[{
      "provider":"fixture",
      "id":"10.9999/wrongfield.2024",
      "title":"DOI in the Notes Field",
      "authors":["Erin Example"],
      "year":"2024",
      "doi":"10.9999/wrongfield.2024"
    }]}
    """)
    reports = check_bibliography(bib; fixture, check=:none)
    @test length(reports) == 1
    @test any(cmp -> cmp.field == "doi" && cmp.status == :missing_input, reports[1].comparisons)
    @test any(source -> source.provider == "fixture", reports[1].sources)
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

@testset "report checklist and key preservation" begin
    entry = BibEntry("foo_bar-2024", "article", Dict(
        "author" => "Example, Erin",
        "title" => "Almost Correct Title",
        "journal" => "Journal of Checks",
        "year" => "2024",
        "abstract" => "A bibliography manager field that should not matter.",
    ))
    source = SourceRecord(provider="fixture", title="Almost Corect Title",
        authors=["Erin Example"], year="2024", journal="Journal of Checks",
        publisher="Example Press")
    report = compare_entry(entry, [source])
    outdir = mktempdir()
    paths = write_reports([report], outdir)
    md = read(paths[:markdown], String)

    @test occursin("## foo_bar-2024", md)
    @test occursin("✅", md)
    @test occursin("⚠️", md)
    @test occursin("`publisher` is missing from BibTeX", md)
    @test occursin("`title` needs manual review", md)
    @test !occursin("abstract", md)

    rows = collect(IncCSV.table(IncCSV.readinc(paths[:inc])))
    @test all(row -> row.key == "foo_bar-2024", rows)
    @test any(row -> row.field == "publisher" &&
        row.importance == "supplementary" &&
        row.severity == "amber", rows)
    @test any(row -> row.field == "title" &&
        row.importance == "important" &&
        row.severity == "amber", rows)
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
