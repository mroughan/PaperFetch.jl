# Security Policy

PaperFetch.jl is a bibliography checking and PDF-fetching tool. It deliberately
avoids direct handling of library usernames and passwords.

## Credential Model

Recommended credential-assisted workflow:

1. Log into your library or proxy in your own browser.
2. Run PaperFetch.jl on your own computer.
3. Pass either an institutional proxy URL template or a local exported cookie
   file when you explicitly choose fetch mode.
4. Delete temporary cookie files when you are finished.

The optional cookie-file mode treats cookies as bearer tokens. Anyone with that
file may temporarily inherit your web session.

## What Not To Share

Do not commit, upload, email, or paste:

- browser cookies or exported `cookies.txt` files;
- passwords, session tokens, API keys, or proxy URLs containing secrets;
- private bibliographies;
- downloaded PDFs that you are not entitled to redistribute;
- API caches if they contain private URLs, request metadata, or unpublished
  bibliography information;
- reports that include proxied URLs or other sensitive local paths.

Generated outputs such as `.paperfetch_cache/`, `paperfetch_out/`, `downloads/`,
and `docs/build/` are ignored by git and should usually stay local.

## Responsible Use

Use a real contact email for public scholarly APIs. Keep batches small, respect
rate limits, and check library, publisher, and repository terms before
downloading PDFs.

PaperFetch.jl can help identify open-access PDFs and validate references, but it
does not grant access rights. Retrieve only material you are entitled to access.

## Reporting Security Issues

If you find a security issue, please contact the maintainer privately rather
than opening a public issue with exploit details. A public issue is fine for
ordinary bugs that do not expose credentials, private URLs, or private documents.
