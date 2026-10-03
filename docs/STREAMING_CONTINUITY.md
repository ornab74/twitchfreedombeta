# Mobile -> DigitalOcean continuity architecture

## Goal

The phone is the encoder and control surface. The DigitalOcean node is the continuity plane. Losing mobile connectivity must not immediately kill the public stream.

## Fast path

1. Android/iOS captures camera/mic and encodes locally with hardware codecs where available.
2. Encoded output is cut into ~1 second independently decodable chunks.
3. Each chunk receives a monotonically increasing sequence number and keyframe flag.
4. The Flutter app sends framed chunks to an authenticated `wss://` ingest session.
5. The node stores only a bounded rolling window in RAM (target 8-12 seconds, hard byte ceiling).
6. The node's output process consumes the rolling source and publishes to Twitch.

No raw camera frames should cross the network when the phone can encode them first. That is wasteful on bandwidth, CPU and RAM.

## Connectivity loss

The node tracks both chunk age and mobile heartbeat age.

- `< 2.5-3 seconds`: tolerate jitter and consume buffered media.
- source stale but heartbeat alive: enter `fallback` mode.
- heartbeat also stale: stay on fallback but mark the mobile source `detached`.
- fresh keyframed chunks return: establish a short warm-up buffer, insert a discontinuity boundary, then cut back to phone media.

The public Twitch output process should remain alive throughout. Do not terminate and recreate the Twitch publish connection for ordinary mobile drops.

## Fallback scene

Fallback should be rendered server-side by FFmpeg as a tiny, predictable graph. Recommended sources:

- static image / generated branded frame,
- reconnect message and elapsed outage time,
- optional low-cost music/audio bed,
- optional pre-rendered clips or a playlist,
- optional server-side TTS announcements.

Keep fallback assets local to the droplet. A static image + AAC audio can sustain an output stream for very little RAM.

## Chunk format

Mobile and server use a compact binary WebSocket frame:

- protocol version: 1 byte
- sequence: uint32
- duration ms: uint32
- flags: 1 byte (`bit0 = keyframe`)
- MIME length: uint16
- MIME UTF-8 bytes
- encoded media payload

ACK messages include server buffer depth, last accepted sequence and discontinuity count. The mobile side can therefore speed up, pause, reconnect or lower bitrate based on actual server pressure.

## RAM budget for a 4-8 GB droplet

The stream engine must be bounded by construction.

Example single-stream budget:

- ingest rolling chunks: <= 64 MiB
- FFmpeg publisher + mux queues: 200-600 MiB depending on codec/filter graph
- Node control plane: normally well below 200 MiB
- local fallback assets: disk-backed, not permanently duplicated in RAM
- reserve the majority of memory for OS page cache and temporary encoder/transcoder pressure

Never allow an unbounded JavaScript array, FFmpeg queue, HLS directory or log buffer.

## Authentication

A permanent master secret should not be embedded in the Flutter application.

Preferred evolution:

1. provision a device-specific bootstrap key once;
2. store it in Android Keystore / iOS Keychain through secure storage;
3. exchange it over TLS for a short-lived session token;
4. bind the token to device ID, capability, expiration and optionally session ID;
5. rotate/revoke the bootstrap credential server-side.

The current backend skeleton accepts a bearer API key hash to establish the protocol. Production should upgrade that to short-lived signed device tokens before public deployment.

## Publishing to Twitch

The next server module should own the Twitch publishing process and never reveal Twitch stream credentials to the phone. The node receives encoded chunks, normalizes timestamps/remuxes when possible, and only transcodes when the mobile codec/profile cannot be passed through safely.

Target the cheap path first: hardware encode on phone -> server remux/continuity -> Twitch. Server transcoding is the expensive path and should be exceptional on a 4-8 GB node.

## Reconnect cutover

Do not switch back on the first packet. Wait for:

1. a fresh keyframe,
2. 2-3 contiguous chunks,
3. sane timestamps,
4. enough buffered duration to survive one network wobble.

Then signal the publisher graph to change input at a media boundary. This prevents corrupted GOPs, timestamp jumps and black frames.

## Future capability modules

Keep these separate from the stream loop:

- Twitch Helix/EventSub
- notification fan-out
- STT
- TTS
- Suno/music orchestration
- image generation
- moderation/AI

They can observe session events through an internal event bus. None should be able to block media ingest or Twitch publication.
