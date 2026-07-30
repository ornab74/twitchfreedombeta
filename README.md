# Twitch Freedom

Twitch Freedom is a private, local-first Twitch player built with Flutter. It
plays streams, connects to Twitch chat, and can optionally run speech-to-text
and a local Gemma assistant on your own device.

There are no ads, thumbnails, emotes, cloud AI services, or demo channels in
the app. You choose what to enable.

## What it does

- Plays Twitch video or audio-only streams.
- Lets you choose stream quality and CPU or GPU video acceleration.
- Reads Twitch chat and can send messages after you connect your account.
- Stores settings, chat memory, and optional transcripts as encrypted records
  in a local SQLite vault.
- Supports optional local Gemma 4 E2B AI features.
- Supports optional local Moonshine Tiny speech-to-text and closed captions.

AI and transcript storage are off until you enable them.

## Linux and Chromebook setup

Install Flutter first, then install the Linux build packages:

```bash
./scripts/install-linux-build-deps.sh
flutter config --enable-linux-desktop
flutter pub get
```

For normal use, run a release build:

```bash
flutter run --release -d linux
```

For performance testing with DevTools, use profile mode:

```bash
flutter run --profile -d linux
```

Plain `flutter run` starts a debug build. Debug mode uses JIT compilation and
extra checks, so its frame rate is not representative of the finished app.

On ChromeOS/Crostini, Twitch Freedom uses Sommelier's X11 bridge because the
native Wayland Flutter surface can stall on affected images. If the container
has no usable `/dev/dri` render node, the app keeps video safe by using Mesa
llvmpipe and CPU media decoding. A machine with a usable render node
automatically gets the accelerated path.

## First launch

1. Create a vault password with at least 10 characters.
2. Add a Twitch channel.
3. Choose Video or Audio only, select a quality, and press Play.
4. Open Control Center to change video acceleration, captions, AI, privacy, or
   appearance settings.

The Linux keyring is only used for the optional “remember this device” feature.
If Crostini reports `KeyringLocked`, password unlock still works normally.

## Twitch account connection

Watching public streams does not require storing your Twitch password. To use
account features:

1. Create a Twitch Developer application.
2. Open Control Center in Twitch Freedom.
3. Enter the application's Client ID and Client Secret.
4. Start device authorization and approve the code in your browser.

Requested scopes are `chat:read`, `user:write:chat`, and
`user:read:follows`.

## Local AI model

The expected file is:

```text
gemma-4-E2B-it.litertlm
```

You can download it inside the app or select that exact `.litertlm` file. The
app checks the pinned SHA-256 digest before registering it. Model files are
large and are intentionally ignored by Git.

Moonshine Tiny is the lower-cost speech model used for optional captions. Raw
audio windows are temporary and are deleted after local transcription.
Transcript retention is a separate opt-in setting.

## Where local data lives

On Linux, the vault and downloaded models are kept in the Flutter application
support directory under `TwitchFreedom/`:

```text
TwitchFreedom/vault.sqlite3
TwitchFreedom/models/
```

The vault encrypts individual records with AES-256-GCM. The SQLite file itself
is not page-encrypted, so file size and update timing can still be visible. See
[SECURITY.md](SECURITY.md) for the full security boundary.

`.gitignore` excludes SQLite databases and their WAL/SHM files, downloaded
models, temporary audio, profiler output, local environment files, and signing
keys. Do not force-add those files to a commit.

## Useful Linux overrides

Most users should leave these unset:

```bash
TWITCH_FREEDOM_SOFTWARE=1 flutter run --release -d linux
TWITCH_FREEDOM_ACCELERATED_UI=1 flutter run --release -d linux
TWITCH_FREEDOM_GDK_BACKEND=wayland flutter run --release -d linux
LP_NUM_THREADS=6 flutter run --release -d linux
```

- `TWITCH_FREEDOM_SOFTWARE=1` forces the CPU-safe UI path.
- `TWITCH_FREEDOM_ACCELERATED_UI=1` tries acceleration even without a detected
  render node.
- `TWITCH_FREEDOM_GDK_BACKEND=wayland` is an experimental override. The tested
  Crostini default is X11.
- `LP_NUM_THREADS` manually limits llvmpipe workers. The Crostini default is
  four so input and video decoding retain CPU time.

## Development checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
./tool/verify_linux_ready.sh
```

The Linux player uses local Media Kit patches in `third_party/`. Do not replace
those path dependencies with hosted packages unless the native texture and
shutdown fixes have been upstreamed.

## Privacy and licensing

Nothing is automatically posted to Twitch. Raw chat remains visible even when
AI features are enabled, and AI-generated alternatives are labeled.

See [SECURITY.md](SECURITY.md), [docs/architecture.md](docs/architecture.md),
and [docs/licensing.md](docs/licensing.md) for implementation and licensing
details.
