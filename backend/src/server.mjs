import http from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { StreamEngine } from './stream-engine.mjs';

const port = Number(process.env.PORT ?? 8080);
const publicBase = process.env.PUBLIC_BASE_URL ?? `http://127.0.0.1:${port}`;
const wsBase = process.env.PUBLIC_WS_URL ?? publicBase.replace(/^http/, 'ws');
const apiKeyHash = process.env.MOBILE_API_KEY_SHA256 ?? '';
const region = process.env.DO_REGION ?? 'unknown';
const version = process.env.APP_VERSION ?? 'dev';
const engine = new StreamEngine({ maxSessions: Number(process.env.MAX_SESSIONS ?? 4) });

function json(res, status, body) {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': data.length,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  res.end(data);
}

function readBody(req, max = 64 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let bytes = 0;
    req.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > max) {
        reject(new Error('body_too_large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks)) : {});
      } catch {
        reject(new Error('invalid_json'));
      }
    });
    req.on('error', reject);
  });
}

function authorized(req) {
  if (!apiKeyHash) return process.env.NODE_ENV !== 'production';
  const auth = req.headers.authorization ?? '';
  const raw = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!raw) return false;
  const digest = createHash('sha256').update(raw).digest();
  const expected = Buffer.from(apiKeyHash, 'hex');
  return expected.length === digest.length && timingSafeEqual(expected, digest);
}

function sessionFromPath(pathname) {
  const match = /^\/v1\/streaming\/sessions\/([^/]+)(?:\/(heartbeat|telemetry))?$/.exec(pathname);
  if (!match) return null;
  return { id: decodeURIComponent(match[1]), action: match[2] ?? '' };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', publicBase);

  if (req.method === 'GET' && url.pathname === '/v1/health') {
    return json(res, 200, {
      ok: true,
      region,
      version,
      websocket_ready: true,
      twitch_ready: Boolean(process.env.TWITCH_CLIENT_ID && process.env.TWITCH_CLIENT_SECRET),
      sessions: engine.sessions.size,
    });
  }

  if (!authorized(req)) return json(res, 401, { error: 'unauthorized' });

  if (req.method === 'POST' && url.pathname === '/v1/streaming/sessions') {
    try {
      const body = await readBody(req);
      const channel = String(body.channel ?? '').trim().toLowerCase();
      if (!/^[a-z0-9_]{1,25}$/.test(channel)) return json(res, 400, { error: 'invalid_channel' });

      const session = engine.createSession({
        deviceId: String(req.headers['x-device-id'] ?? 'mobile'),
        channel,
        chunkTargetMs: 1000,
        maxBufferMs: 10000,
      });
      return json(res, 201, {
        session_id: session.id,
        playback_url: `${publicBase}/v1/streaming/sessions/${session.id}/preview`,
        websocket_url: `${wsBase}/v1/streaming/ingest/${session.id}`,
        expires_at: new Date(Date.now() + 15 * 60_000).toISOString(),
        chunk_target_ms: session.chunkTargetMs,
        max_buffer_ms: session.maxBufferMs,
        reconnect_grace_ms: 30000,
        fallback_mode: session.fallback.kind,
      });
    } catch (error) {
      if (error.message === 'capacity') return json(res, 503, { error: 'capacity' });
      return json(res, 400, { error: error.message ?? 'bad_request' });
    }
  }

  const route = sessionFromPath(url.pathname);
  if (route) {
    const session = engine.get(route.id);
    if (!session) return json(res, 404, { error: 'not_found' });

    if (req.method === 'POST' && route.action === 'heartbeat') {
      session.heartbeat();
      return json(res, 200, session.telemetry());
    }
    if (req.method === 'GET' && route.action === 'telemetry') {
      return json(res, 200, session.telemetry());
    }
    if (req.method === 'DELETE' && route.action === '') {
      engine.delete(route.id);
      return json(res, 200, { ended: true });
    }
  }

  return json(res, 404, { error: 'not_found' });
});

const wss = new WebSocketServer({ noServer: true, maxPayload: 2 * 1024 * 1024 });

server.on('upgrade', (req, socket, head) => {
  try {
    const url = new URL(req.url ?? '/', wsBase);
    const match = /^\/v1\/streaming\/ingest\/([^/]+)$/.exec(url.pathname);
    const session = match ? engine.get(match[1]) : null;
    if (!session || !authorized(req)) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws, session));
  } catch {
    socket.destroy();
  }
});

wss.on('connection', (ws, session) => {
  ws.binaryType = 'nodebuffer';
  ws.on('message', (payload, isBinary) => {
    try {
      if (!isBinary) {
        const message = JSON.parse(payload.toString('utf8'));
        if (message.type === 'heartbeat') {
          session.heartbeat();
          ws.send(JSON.stringify({ type: 'telemetry', ...session.telemetry() }));
        }
        return;
      }

      if (payload.length < 17) throw new Error('chunk_header_short');
      const version = payload.readUInt8(0);
      if (version !== 1) throw new Error('chunk_version');
      const sequence = payload.readUInt32BE(1);
      const durationMs = payload.readUInt32BE(5);
      const flags = payload.readUInt8(9);
      const mimeLength = payload.readUInt16BE(10);
      const headerLength = 12 + mimeLength;
      if (headerLength >= payload.length) throw new Error('chunk_payload_short');
      const contentType = payload.subarray(12, headerLength).toString('utf8');
      const data = payload.subarray(headerLength);
      const result = session.ingest({
        sequence,
        durationMs,
        keyframe: (flags & 1) === 1,
        contentType,
        data,
      });
      ws.send(JSON.stringify({ type: 'ack', sequence, ...result, ...session.telemetry() }));
    } catch (error) {
      ws.send(JSON.stringify({ type: 'error', code: error.message ?? 'ingest_error' }));
    }
  });
});

setInterval(() => engine.tick(), 500).unref();
server.listen(port, '0.0.0.0', () => {
  console.log(`Twitch Freedom stream node listening on :${port}`);
});
