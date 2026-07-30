# Security Model

## Goals

Twitch Freedom protects saved streams, Twitch app credentials, OAuth tokens, chat transcripts, preferences, local AI memory, and model attestations against casual offline disclosure and tampering after the application is closed.

## Cryptographic design

- Password KDF: Argon2id, 64 MiB, three iterations, parallelism two, 16-byte random salt.
- KEK: password-derived and never persisted.
- VUK: random 256-bit vault-unlock key, wrapped by the KEK.
- DEKs: versioned random 256-bit record keys wrapped by the VUK.
- Records: AES-256-GCM with a fresh 96-bit nonce.
- Associated data: record type hash, obscured ID, key version, and schema version.
- Logical IDs: HMAC-SHA-256-derived identifiers.
- Password change: rewraps the VUK.
- DEK rotation: inserts a new wrapped DEK, migrates every record, changes the active version, and retires unreferenced prior keys within one SQLite transaction.
- Remember-on-device: stores only the VUK in OS secure storage and fails closed when authentication fails.

## Network boundaries

- Twitch URLs must be HTTPS and match a Twitch host allowlist.
- Playback redirects are limited to Twitch/CDN suffixes.
- Manifest and response sizes are bounded.
- Twitch playback signatures, OAuth tokens, secrets, and model prompts are redacted from logs.
- No embedded WebView is required for ordinary operation.
- Device authorization opens the system browser.

## Local AI boundaries

- AI is disabled by default.
- Model installation uses a pinned URL, maximum byte count, and pinned SHA-256.
- Chat text is treated as untrusted quoted data in prompts.
- The model cannot post messages.
- Protective Mirror never replaces the canonical stored chat line.
- Speech audio is ephemeral and deleted after local transcription.
- Derived memory is isolated by channel and expires.

## Out of scope

- A compromised operating system or process with access to unlocked memory.
- Screen capture, keylogging, or malicious accessibility services.
- Traffic analysis and filesystem metadata such as ciphertext size and timestamps.
- Twitch account compromise.
- Vulnerabilities in native media/model runtimes.

## Reporting

Do not include OAuth tokens, client secrets, model prompts, chat logs, or vault files in public bug reports. Reproduce using synthetic records and attach redacted diagnostics only.
