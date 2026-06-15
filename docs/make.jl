using Documenter
using PaperFetch

makedocs(
    sitename = "PaperFetch.jl",
    modules = [PaperFetch],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://mroughan.github.io/PaperFetch.jl/",
        edit_link = "main",
    ),
    pages = [
        "Home" => "index.md",
        "Examples" => "examples.md",
        "API Reference" => "api.md",
    ],
    checkdocs = :exports,
)

deploydocs(
    repo = "github.com/mroughan/PaperFetch.jl.git",
)
