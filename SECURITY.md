# Security and privacy

Sable works with real personal libraries and optional contributor accounts. Please treat both as sensitive.

## Credentials

- The repository contains no production tokens, sessions, passwords, or API keys.
- Credentials entered in Settings are stored in the macOS Keychain.
- Do not paste credentials into issues, screenshots, logs, fixtures, source files, or pull requests.
- Use your own MangaBaka, Roler, TMDB, TVDB, or Yen Press access where a workflow asks for it.

If you accidentally commit a credential, revoke it with the provider first. Removing it from a later commit does not remove it from Git history.

## Reports and sample data

Before sharing a Sable report, inspect it for local paths, filenames, series names, provider IDs, and account-related details. Use synthetic fixtures in bug reports whenever possible.

## Reporting a vulnerability

Please report security or privacy problems privately through GitHub's security advisory feature for this repository. Include the affected app, the smallest safe reproduction, and whether real files or credentials may be at risk. Do not open a public issue for an unpatched credential leak, destructive file operation, or account-authentication flaw.

## Safety boundary

Sable is designed around preview, explicit selection, confirmation, and receipts. Changes that weaken those boundaries need focused tests and a clear recovery story.
