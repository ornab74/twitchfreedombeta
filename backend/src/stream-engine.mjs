import { randomUUID } from 'node:crypto';

export class BoundedChunkRing {
  constructor({ maxBytes = 64 * 1024 * 1024, maxDurationMs = 12000 } = {}) {
    this.maxBytes = maxBytes;
    this.maxDurationMs = maxDurationMs;
    this.items = [];
    this.bytes = 0;
    this.durationMs = 0;
  }

  push(chunk) {
    this.items.push(chunk);
    this.bytes += chunk.data.length;
    this.durationMs += chunk.durationMs;
    this.#trim();
  }

  #trim() {
    while (
      this.items.length > 1 &&
      (this.bytes > this.maxBytes || this.durationMs > this.maxDurationMs)
    ) {
      const removed = this.items.shift();
      this.bytes -= removed.data.length;
      this.durationMs -= removed.durationMs;
    }
  }

  snapshot() {
    return [...this.items];
  }
}

export class StreamSession {
  constructor({ deviceId, channel, chunkTargetMs = 1000, maxBufferMs = 10000 }) {
    this.id = randomUUID();
    this.deviceId = deviceId;
    this.channel = channel;
    this.chunkTargetMs = chunkTargetMs;
    this.maxBufferMs = maxBufferMs;
    this.state = 'warming';
    this.createdAt = Date.now();
    this.lastHeartbeatAt = Date.now();
    this.lastChunkAt = 0;
    this.sequence = -1;
    this.discontinuity = 0;
    this.ring = new BoundedChunkRing({ maxDurationMs: maxBufferMs });
    this.fallback = {
      kind: 'image',
      imagePath: process.env.FALLBACK_IMAGE ?? '',
      message: 'Mobile source reconnecting',
    };
  }

  heartbeat() {
    this.lastHeartbeatAt = Date.now();
  }

  ingest({ sequence, durationMs, keyframe, contentType, data }) {
    if (!Number.isInteger(sequence) || sequence < 0) throw new Error('bad_sequence');
    if (sequence <= this.sequence) return { accepted: false, duplicate: true };
    if (durationMs < 100 || durationMs > 5000) throw new Error('bad_duration');
    if (!Buffer.isBuffer(data) || data.length === 0) throw new Error('empty_chunk');

    if (this.sequence >= 0 && sequence !== this.sequence + 1) {
      this.discontinuity += 1;
    }
    this.sequence = sequence;
    this.lastChunkAt = Date.now();
    this.state = 'live';
    this.ring.push({ sequence, durationMs, keyframe, contentType, data });
    return { accepted: true, duplicate: false };
  }

  tick(now = Date.now()) {
    const sourceAge = this.lastChunkAt === 0 ? Infinity : now - this.lastChunkAt;
    const heartbeatAge = now - this.lastHeartbeatAt;

    if (sourceAge > Math.max(2500, this.chunkTargetMs * 3)) {
      this.state = heartbeatAge < 30000 ? 'fallback' : 'detached';
    } else {
      this.state = 'live';
    }
    return this.state;
  }

  telemetry() {
    return {
      session_id: this.id,
      state: this.state,
      buffered_ms: this.ring.durationMs,
      buffered_bytes: this.ring.bytes,
      sequence: this.sequence,
      discontinuities: this.discontinuity,
      source_age_ms: this.lastChunkAt === 0 ? null : Date.now() - this.lastChunkAt,
    };
  }
}

export class StreamEngine {
  constructor({ maxSessions = 4 } = {}) {
    this.maxSessions = maxSessions;
    this.sessions = new Map();
  }

  createSession(options) {
    if (this.sessions.size >= this.maxSessions) throw new Error('capacity');
    const session = new StreamSession(options);
    this.sessions.set(session.id, session);
    return session;
  }

  get(id) {
    return this.sessions.get(id) ?? null;
  }

  delete(id) {
    return this.sessions.delete(id);
  }

  tick() {
    const now = Date.now();
    for (const session of this.sessions.values()) session.tick(now);
  }
}
