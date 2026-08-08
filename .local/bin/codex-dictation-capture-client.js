#!/usr/bin/env node

'use strict';

const net = require('node:net');

const socketPath = process.argv[2];
const command = process.argv[3];
const audioFile = process.argv[4];
const timeoutMs = Number(process.env.CODEX_DICTATION_CAPTURE_TIMEOUT_MS || 10000);

if (!socketPath || !['start', 'snapshot', 'stop', 'status'].includes(command) ||
    (['snapshot', 'stop'].includes(command) && !audioFile)) {
  console.error('Usage: codex-dictation-capture-client.js SOCKET_PATH start|snapshot|stop|status [AUDIO_FILE]');
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
    fail('Timed out waiting for the dictation capture service.');
  }
  socket = net.createConnection(socketPath);
  socket.setEncoding('utf8');
  socket.on('connect', () => {
    connected = true;
    const request = { command, ...(audioFile ? { audioFile } : {}) };
    socket.end(`${JSON.stringify(request)}\n`);
  });
  socket.on('data', (chunk) => {
    response += chunk;
  });
  socket.on('end', () => {
    try {
      const result = JSON.parse(response);
      if (!result.ok) fail(result.error || 'Dictation capture request failed.');
      if (command === 'status') {
        process.stdout.write(`${String(result.state || '')}\n`, () => process.exit(0));
      } else {
        process.exit(0);
      }
    } catch (error) {
      fail(`Invalid capture service response: ${error.message}`);
    }
  });
  socket.on('error', (error) => {
    socket.destroy();
    if (connected) fail(`Dictation capture connection failed: ${error.message}`);
    retryTimer = setTimeout(connect, 100);
  });
}

connect();
