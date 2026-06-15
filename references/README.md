# Reference Material

Downloaded or locally inspected reference material used while rebuilding this
package.

Downloaded on: 2026-06-15

## Files

- `julia-style-guide.md`
  - Source: https://raw.githubusercontent.com/JuliaLang/julia/master/doc/src/manual/style-guide.md
  - Purpose: Julia naming, API, and style decisions.
  - Acceptable use: Julia documentation source, kept here for local review.

- `julia-performance-tips.md`
  - Source: https://raw.githubusercontent.com/JuliaLang/julia/master/doc/src/manual/performance-tips.md
  - Purpose: General Julia performance guidance for data structures and hot paths.
  - Acceptable use: Julia documentation source, kept here for local review.

- `inccsv-readme.md`
  - Source: https://raw.githubusercontent.com/mroughan/IncCSV.jl/main/README.md
  - Purpose: INC output format and `writeinc`/`readinc` behavior.
  - Acceptable use: Project README, kept here for local review.

## Locally Inspected References

- BibParser.jl v0.2.3 local package docs and source in
  `/home/matt/.julia/packages/BibParser/tQBkg`.
  - Purpose: `parse_file`, `parse_entry`, and `BibInternal.Entry` field layout.
  - Note: an attempted download of a guessed GitHub raw docs URL returned 404,
    so no remote BibParser documentation file is stored here.

## Uncertainties

- Provider APIs can change. The API adapters in `src/PaperFetch.jl` are small
  and tested offline with fixtures, but live Crossref, OpenAlex, and Unpaywall
  behavior should be checked before relying on network mode for production use.
