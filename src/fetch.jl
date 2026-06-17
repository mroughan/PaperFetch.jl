"""
    FetchResult(key, status, file, source_url, final_url, note, sha256, bytes)

Manifest record for one PDF fetch attempt.

# Example

```julia
result = FetchResult("x", "skipped", nothing, nothing, nothing, "no PDF", nothing, 0)
result.status
```
"""
struct FetchResult
    key::String
    status::String
    file::Union{Nothing,String}
    source_url::Union{Nothing,String}
    final_url::Union{Nothing,String}
    note::String
    sha256::Union{Nothing,String}
    bytes::Int
end

function read_cookie_file(path::Union{Nothing,String})
    path === nothing && return Dict{String,String}()
    cookies = Dict{String,String}()
    for line in eachline(path)
        # Skip comments and the HttpOnly prefix used by some exporters
        clean = replace(line, r"^#HttpOnly_" => "")
        startswith(clean, "#") && continue
        parts = split(clean, '\t')
        length(parts) < 7 && continue
        domain, name, value = parts[1], parts[6], parts[7]
        existing = get(cookies, domain, "")
        cookies[domain] = isempty(existing) ? "$(name)=$(value)" : "$(existing); $(name)=$(value)"
    end
    return cookies
end

function cookie_for_url(cookies::Dict{String,String}, url::AbstractString)
    host = try
        URIs.URI(String(url)).host
    catch
        nothing
    end
    host === nothing && return nothing
    values = String[]
    for (domain, cookie) in cookies
        cleaned = replace(domain, r"^\." => "")
        if host == cleaned || endswith(host, "." * cleaned)
            push!(values, cookie)
        end
    end
    return isempty(values) ? nothing : join(values, "; ")
end

function proxied_url(url::String, ezproxy::Union{Nothing,String})
    ezproxy === nothing && return url
    template = strip(ezproxy)
    isempty(template) && return url
    return occursin("{url}", template) ? replace(template, "{url}" => escapeuri(url)) :
                                         template * escapeuri(url)
end

function download_pdf(url::String, dest::String; cookies::Dict{String,String}=Dict{String,String}(),
        ezproxy::Union{Nothing,String}=nothing, timeout::Int=60, http_get=HTTP.get)
    actual  = String(proxied_url(url, ezproxy))
    headers = ["User-Agent" => DEFAULT_USER_AGENT]
    cookie  = cookie_for_url(cookies, actual)
    cookie === nothing || push!(headers, "Cookie" => cookie)
    response = http_get(actual, headers; redirect=true, read_idle_timeout=timeout, status_exception=false)
    body  = Vector{UInt8}(response.body)
    ctype = lowercase(String(HTTP.header(response, "Content-Type", "")))
    looks_pdf = occursin("pdf", ctype) || (length(body) >= 4 && body[1:4] == UInt8['%','P','D','F'])
    if !(200 <= response.status < 300)
        return false, actual, "HTTP $(response.status)", nothing, 0
    elseif !looks_pdf
        return false, actual, "not a PDF; content-type=$(ctype)", nothing, length(body)
    end
    write(dest, body)
    return true, actual, "downloaded", bytes2hex(sha256(body)), length(body)
end

function write_manifest(path::AbstractString, results::Vector{FetchResult})
    rows = [(
        key=r.key,
        status=r.status,
        file=something(r.file, ""),
        source_url=something(r.source_url, ""),
        final_url=something(r.final_url, ""),
        note=r.note,
        sha256=something(r.sha256, ""),
        bytes=r.bytes,
    ) for r in results]
    metadata = Dict(
        "title"     => "PaperFetch PDF fetch manifest",
        "generated" => string(Dates.now()),
        "tool"      => "PaperFetch.jl",
        "columns"   => Dict(
            "key"        => "BibTeX entry key",
            "status"     => "downloaded, skipped, or failed",
            "file"       => "Local PDF path when downloaded",
            "source_url" => "Candidate PDF URL",
            "final_url"  => "URL after proxy template and redirects when known",
            "note"       => "Fetch note",
            "sha256"     => "SHA-256 hash of downloaded bytes",
            "bytes"      => "Downloaded byte count",
        ),
    )
    IncCSV.writeinc(path, rows; metadata)
    return path
end

"""
    fetch_pdfs(reports, outdir; cookie_file=nothing, ezproxy=nothing)

Download PDF candidates from reports and write an INC manifest.

Only explicit PDF candidate URLs are attempted. Missing PDFs are recorded as
`skipped`, not as validation failures.

# Example

```julia
entry = BibEntry("x", "misc", Dict("title" => "No PDF"))
report = EntryReport(entry, SourceRecord[], FieldComparison[], 0.0, String[], String[])
results, manifest = fetch_pdfs([report], mktempdir())
results[1].status == "skipped"
```
"""
function fetch_pdfs(reports::Vector{EntryReport}, outdir::AbstractString;
        cookie_file::Union{Nothing,String}=nothing, ezproxy::Union{Nothing,String}=nothing,
        http_get=HTTP.get)
    mkpath(outdir)
    cookies = read_cookie_file(cookie_file)
    results = FetchResult[]
    for report in reports
        if isempty(report.pdf_candidates)
            push!(results, FetchResult(report.entry.key, "skipped", nothing, nothing, nothing,
                "no PDF candidate", nothing, 0))
            continue
        end
        base = slugify(get(report.entry.fields, "title", report.entry.key))
        downloaded = false
        for (i, url) in enumerate(report.pdf_candidates)
            dest = joinpath(outdir, i == 1 ? "$(base).pdf" : "$(base)-$(i).pdf")
            ok, final_url, note, digest, nbytes = download_pdf(url, dest; cookies, ezproxy, http_get)
            if ok
                push!(results, FetchResult(report.entry.key, "downloaded", dest, url,
                    final_url, note, digest, nbytes))
                downloaded = true
                break
            else
                push!(results, FetchResult(report.entry.key, "failed", nothing, url,
                    final_url, note, digest, nbytes))
            end
        end
        # If all candidates failed, the last FetchResult records the last failure.
        _ = downloaded
    end
    manifest = write_manifest(joinpath(outdir, "manifest.inc"), results)
    return results, manifest
end
