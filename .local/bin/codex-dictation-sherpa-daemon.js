#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const { createEngine } = require('./codex-dictation-sherpa-engine.js');

const socketPath = process.argv[2] || process.env.CODEX_DICTATION_SHERPA_SOCKET;
const idleTimeoutMs = Number(process.env.CODEX_DICTATION_SHERPA_IDLE_MS || 300000);

if (!socketPath) {
  console.error('Usage: codex-dictation-sherpa-daemon.js SOCKET_PATH');
  process.exit(2);
}

const socketDir = path.dirname(socketPath);
fs.mkdirSync(socketDir, { recursive: true, mode: 0o700 });
try {
  fs.unlinkSync(socketPath);
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

console.error('Loading Sherpa model…');
const engine = createEngine();
console.error('Sherpa model ready.');

let idleTimer;
let busy = Promise.resolve();
let shuttingDown = false;

function armIdleTimer() {
  clearTimeout(idleTimer);
  if (!Number.isFinite(idleTimeoutMs) || idleTimeoutMs <= 0) return;
  idleTimer = setTimeout(shutdown, idleTimeoutMs);
  idleTimer.unref();
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  clearTimeout(idleTimer);
  server.close(() => {
    try {
      fs.unlinkSync(socketPath);
    } catch {
      // The socket may already have been removed during shutdown.
    }
    process.exit(0);
  });
}

function handleRequest(socket, request) {
  const audioFile = path.resolve(String(request.audioFile || ''));
  const relative = path.relative(socketDir, audioFile);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Audio file must be inside the dictation runtime directory.');
  }
  if (!fs.existsSync(audioFile)) {
    throw new Error(`Audio file does not exist: ${audioFile}`);
  }
  const text = engine.transcribe(audioFile);
  return { ok: true, text };
}

const server = net.createServer({ allowHalfOpen: true }, (socket) => {
  let body = '';
  socket.setEncoding('utf8');
  socket.on('error', () => {
    // The client may disappear while a transcription is running.
  });
  socket.on('data', (chunk) => {
    body += chunk;
  });
  socket.once('end', () => {
    let request;
    try {
      request = JSON.parse(body);
    } catch (error) {
      if (!socket.destroyed && !socket.writableEnded) {
        socket.end(`${JSON.stringify({ ok: false, error: `Invalid request: ${error.message}` })}\n`);
      }
      return;
    }
    busy = busy.then(() => {
      armIdleTimer();
      let result;
      try {
        result = handleRequest(socket, request);
      } catch (error) {
        result = { ok: false, error: error.message };
      }
      if (!socket.destroyed && !socket.writableEnded) {
        socket.end(`${JSON.stringify(result)}\n`);
      }
    });
  });
});

server.on('error', (error) => {
  console.error(`Sherpa service error: ${error.message}`);
  process.exit(1);
});

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
server.listen(socketPath, () => {
  try {
    fs.chmodSync(socketPath, 0o600);
  } catch {
    // The parent runtime directory is already private to the user.
  }
  armIdleTimer();
  console.error(`Sherpa service listening on ${socketPath}`);
});
