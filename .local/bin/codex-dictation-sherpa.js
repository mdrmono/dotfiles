#!/usr/bin/env node

'use strict';

const { createEngine } = require('./codex-dictation-sherpa-engine.js');
const audioFile = process.env.CODEX_DICTATION_AUDIO_FILE || process.argv[2];

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!audioFile) {
  fail('Usage: codex-dictation-sherpa.js AUDIO_FILE');
}

const engine = createEngine();
process.stdout.write(`${engine.transcribe(audioFile)}\n`);
