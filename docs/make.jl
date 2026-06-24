using Documenter
using PaperFetch

const ROOT = dirname(@__DIR__)
const SOURCE_LINKS = isdir(joinpath(ROOT, ".git")) ?
    (repo = "https://github.com/mroughan/PaperFetch.jl/blob/{commit}{path}#L{line}",) :
    (remotes = nothing,)

makedocs(;
    sitename = "PaperFetch.jl",
    modules = [PaperFetch],
    SOURCE_LINKS...,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://mroughan.github.io/PaperFetch.jl/",
        edit_link = "main",
        repolink = "https://github.com/mroughan/PaperFetch.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Examples" => "examples.md",
        "Live Providers" => "providers.md",
        "Reports and Manifests" => "reports.md",
        "Stand-Alone Executable" => "standalone.md",
        "API Reference" => "api.md",
    ],
    checkdocs = :exports,
)

deploydocs(
    repo = "github.com/mroughan/PaperFetch.jl.git",
    devbranch = "main",
)
