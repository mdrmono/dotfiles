#!/usr/bin/env node

'use strict';

const net = require('node:net');

const socketPath = process.argv[2];
const audioFile = process.argv[3];
const timeoutMs = Number(process.env.CODEX_DICTATION_SHERPA_TIMEOUT_MS || 120000);

if (!socketPath || !audioFile) {
  console.error('Usage: codex-dictation-sherpa-client.js SOCKET_PATH AUDIO_FILE');
  process.exit(2);
}

const deadline = Date.now() + timeoutMs;
let socket;
let response = '';
let retryTimer;
let connected = false;

function fail(message) {
  if (retryTimer) clearTimeout(retryTimer);
  socket?.destroy();
  console.error(message);
  process.exit(1);
}

function connect() {
  if (Date.now() >= deadline) {
    fail('Timed out waiting for the Sherpa transcription service.');
  }
  socket = net.createConnection(socketPath);
  socket.setEncoding('utf8');
  socket.on('connect', () => {
    connected = true;
    socket.end(`${JSON.stringify({ audioFile })}\n`);
  });
  socket.on('data', (chunk) => {
    response += chunk;
  });
  socket.on('end', () => {
    try {
      const result = JSON.parse(response);
      if (!result.ok) fail(result.error || 'Sherpa transcription failed.');
      process.stdout.write(`${String(result.text || '').trim()}\n`);
    } catch (error) {
      fail(`Invalid Sherpa service response: ${error.message}`);
    }
  });
  socket.on('error', (error) => {
    socket.destroy();
    if (connected) {
      fail(`Sherpa service connection failed: ${error.message}`);
    }
    retryTimer = setTimeout(connect, 100);
  });
}

connect();
