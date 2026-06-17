# APIs To Consider

PaperFetch already has adapters for Crossref, OpenAlex, Unpaywall, DataCite,
arXiv, Open Library, Google Books, Semantic Scholar, PubMed, CORE, Figshare,
and simple landing-page metadata. The APIs below are plausible future additions,
but should remain optional until we have examples showing they improve real
bibliography checks.

## Europe PMC

Useful for biomedical literature, particularly PMID/PMCID/DOI crosswalks and
open-access full-text links. It overlaps with PubMed, but can be better when the
goal is to find a freely reachable manuscript or resolve PubMed Central records.

## OpenCitations Meta / COCI

Useful for citation graph checks and DOI-to-DOI reference links. This is less
about validating one BibTeX entry directly and more about checking whether a
reference sits in a plausible citation network or resolving incomplete
references through nearby citation metadata.

## WorldCat / OCLC

Potentially the strongest option for book and catalog metadata, especially for
older books, edited volumes, translations, and variant editions. Access and data
licensing are likely the main constraints, so this should be a user-configured
licensed adapter rather than a default online query.

## ISBNdb

Commercial book metadata API. It may help when an entry has an ISBN and Open
Library or Google Books returns weak or conflicting metadata. Treat it as an
optional paid service, not a default dependency.

## Library of Congress

Good for books, government material, historical material, reports, and archival
web resources. The API is attractive because it provides structured data and can
avoid scraping LoC pages directly.

## DBLP

High-value for computer science publications, especially conference papers,
proceedings, edited volumes, and author disambiguation. Its coverage is narrower
than OpenAlex or Semantic Scholar, but often cleaner for CS venues.

## HAL

Useful for French and European open-access papers, preprints, reports, and
theses. It may be especially valuable for entries whose BibTeX came from HAL or
whose URL points into `hal.science` / `archives-ouvertes.fr`.

## Zenodo

Useful for datasets, software, reports, preprints, and DOI-backed repository
items. DataCite will often cover Zenodo DOIs, but the Zenodo API can expose
repository-specific fields and file download links.

## Scopus

Strong curated metadata and citation data, but API access depends on Elsevier
terms, API keys, and institutional or non-commercial access conditions. It should
be an optional licensed adapter.

## Web of Science

High-quality curated citation/index metadata where institutional access exists.
Like Scopus, it should be optional and credential-based rather than built into
the default open workflow.

## Dimensions

Interesting for publications, grants, datasets, clinical trials, patents, and
policy documents. The API is subscription-oriented and better suited to an
optional adapter for institutions that already have access.

## The Lens

Broad scholarly and patent metadata. It could be useful for patents, standards,
and scholarly works that do not resolve cleanly through open scholarly APIs.
Check API access terms before integrating.

## ORCID

ORCID is interesting, but it is probably not a primary source for validating a
reference. Its best use would be author disambiguation: confirming that a
specific author lists a work, resolving name variants, or distinguishing two
authors with similar names. That can help explain ambiguous author comparisons,
but it should not override publisher, DOI, PubMed, or repository metadata.
