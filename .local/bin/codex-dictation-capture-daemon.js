#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const { spawn } = require('node:child_process');

const socketPath = process.argv[2] || process.env.CODEX_DICTATION_CAPTURE_SOCKET;
const sampleRate = 16000;
const channels = 1;
const bytesPerSample = 2;
const preRollMs = Number(process.env.CODEX_DICTATION_PRE_ROLL_MS || 500);
const preRollBytes = Math.max(0, Math.floor(sampleRate * channels * bytesPerSample * preRollMs / 1000));

if (!socketPath) {
  console.error('Usage: codex-dictation-capture-daemon.js SOCKET_PATH');
  process.exit(2);
}

const socketDir = path.dirname(socketPath);
fs.mkdirSync(socketDir, { recursive: true, mode: 0o700 });
try {
  fs.unlinkSync(socketPath);
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

function resolveAudioFile(value) {
  const audioFile = path.resolve(String(value || ''));
  const relative = path.relative(socketDir, audioFile);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Audio file must be inside the dictation runtime directory.');
  }
  return audioFile;
}

function appendToRing(ring, chunk) {
  if (preRollBytes === 0) return Buffer.alloc(0);
  const combined = Buffer.concat([ring, chunk]);
  return combined.length > preRollBytes ? combined.subarray(combined.length - preRollBytes) : combined;
}

function wavHeader(dataLength) {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + dataLength, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * channels * bytesPerSample, 28);
  header.writeUInt16LE(channels * bytesPerSample, 32);
  header.writeUInt16LE(bytesPerSample * 8, 34);
  header.write('data', 36);
  header.writeUInt32LE(dataLength, 40);
  return header;
}

let ring = Buffer.alloc(0);
let recording = null;
let shuttingDown = false;
let server;

function writeRecording(audioFile, chunks) {
  const pcm = Buffer.concat(chunks);
  fs.writeFileSync(audioFile, Buffer.concat([wavHeader(pcm.length), pcm]), { mode: 0o600 });
  return pcm.length;
}

function startRecording() {
  if (recording) throw new Error('Dictation is already recording.');
  recording = { chunks: [Buffer.from(ring)] };
  return { state: 'recording' };
}

function snapshotRecording(request) {
  if (!recording) throw new Error('Dictation is not recording.');
  const audioFile = resolveAudioFile(request.audioFile);
  const bytes = writeRecording(audioFile, recording.chunks);
  return { state: 'recording', bytes };
}

function stopRecording(request) {
  if (!recording) throw new Error('Dictation is not recording.');
  const audioFile = resolveAudioFile(request.audioFile);
  const activeRecording = recording;
  recording = null;
  const bytes = writeRecording(audioFile, activeRecording.chunks);
  return { state: 'ready', bytes };
}

const recorder = spawn('/usr/bin/pw-record', [
  '--rate', String(sampleRate),
  '--channels', String(channels),
  '--format', 's16',
  '--latency', '20ms',
  '-',
], { stdio: ['ignore', 'pipe', 'inherit'] });

recorder.stdout.on('data', (chunk) => {
  const copy = Buffer.from(chunk);
  if (recording) recording.chunks.push(copy);
  else ring = appendToRing(ring, copy);
});

recorder.on('error', (error) => {
  console.error(`PipeWire capture failed: ${error.message}`);
  process.exit(1);
});

recorder.on('exit', (code, signal) => {
  if (!shuttingDown) {
    console.error(`PipeWire capture exited: code=${code} signal=${signal || 'none'}`);
    process.exit(1);
  }
});

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  recorder.kill('SIGTERM');
  server?.close(() => {
    try {
      fs.unlinkSync(socketPath);
    } catch {
      // The socket may already have been removed during shutdown.
    }
    process.exit(0);
  });
}

function handleRequest(request) {
  if (request.command === 'start') return startRecording();
  if (request.command === 'snapshot') return snapshotRecording(request);
  if (request.command === 'stop') return stopRecording(request);
  throw new Error(`Unknown capture command: ${request.command}`);
}

let busy = Promise.resolve();
server = net.createServer({ allowHalfOpen: true }, (socket) => {
  let body = '';
  socket.setEncoding('utf8');
  socket.on('error', () => {
    // The client may disappear while a WAV is being finalized.
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
      let result;
      try {
        result = { ok: true, ...handleRequest(request) };
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
  console.error(`Capture service error: ${error.message}`);
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
  console.error(`Capture service listening on ${socketPath}; pre-roll=${preRollMs}ms`);
});
