# Changelog

## Unreleased

- Reimplemented the package around typed bibliography, source metadata,
  comparison, report, and fetch result records.
- Added BibParser.jl-based BibTeX parsing.
- Added fixture-backed source metadata checks for deterministic offline tests.
- Added tolerant field comparison for titles, authors, years, pages, publisher
  names, URLs, and exact normalized DOI checks.
- Added Markdown and INC report writers.
- Added PDF fetching from explicit candidate URLs with an INC manifest.
- Added 10 small BibTeX examples, one plain DOI-list example, and metadata
  fixtures.
- Added an offline test suite covering normalization, parsing, comparison,
  reports, fetch manifests, and the CLI.
- Added reference provenance notes and local copies of key implementation
  reference material.
