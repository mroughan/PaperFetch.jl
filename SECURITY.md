# Security model

PaperFetch.jl deliberately avoids direct handling of library credentials.

Recommended patterns:

1. Log into the library in your own browser.
2. Use either an institutional proxy URL pattern or a locally exported cookie file.
3. Run PaperFetch.jl on your own computer.
4. Never upload or email cookie files, session tokens, or passwords.

The optional cookie-file mode treats cookies as bearer tokens. Anyone with that file may temporarily inherit your web session, so keep it private and delete it after use.

The tool writes the proxied URLs it tried into reports. If your proxy URLs contain session identifiers, do not share those reports publicly without checking them.
