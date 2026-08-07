#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const { spawnSync } = require('node:child_process');

const xdotool = '/usr/local/bin/xdotool';
const dryRun = process.env.CODEX_DICTATION_LIVE_DRY_RUN === '1';

function readText(file) {
  try {
    return fs.readFileSync(file, 'utf8').replace(/[\r\n]+/g, ' ').trim();
  } catch (error) {
    if (error.code === 'ENOENT') return '';
    throw error;
  }
}

function writeText(file, text) {
  if (!text) {
    try {
      fs.unlinkSync(file);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    return;
  }
  fs.writeFileSync(file, `${text}\n`, { mode: 0o600 });
}

function normalizeTranscript(value) {
  return String(value || '')
    .replace(/[\r\n]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\bcode\s+x\b/gi, 'Codex')
    .replace(/\bcodecks\b/gi, 'Codex')
    .replace(/\bcodex\b/gi, 'Codex');
}

function planUpdate(previous, next) {
  const previousChars = Array.from(previous);
  const nextChars = Array.from(next);
  let common = 0;
  while (common < previousChars.length && common < nextChars.length &&
         previousChars[common] === nextChars[common]) {
    common += 1;
  }
  return {
    prefix: nextChars.slice(0, common).join(''),
    erase: previousChars.length - common,
    append: nextChars.slice(common).join(''),
  };
}

function runXdotool(args) {
  if (dryRun) {
    process.stdout.write(`${JSON.stringify(args)}\n`);
    return;
  }
  const result = spawnSync(xdotool, args, { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(String(result.stderr || result.stdout || 'xdotool failed').trim());
  }
}

function windowExists(windowId) {
  if (dryRun) return true;
  return spawnSync(xdotool, ['getwindowname', windowId], { stdio: 'ignore' }).status === 0;
}

function windowIsFocused(windowId) {
  if (dryRun) return true;
  const result = spawnSync(xdotool, ['getactivewindow'], { encoding: 'utf8' });
  return result.status === 0 && result.stdout.trim() === String(windowId);
}

function eraseCharacters(windowId, count) {
  let remaining = count;
  while (remaining > 0) {
    const chunk = Math.min(remaining, 128);
    runXdotool([
      'key', '--window', String(windowId), '--clearmodifiers', '--delay', '1',
      ...Array(chunk).fill('BackSpace'),
    ]);
    remaining -= chunk;
  }
}

function updateComposer(windowId, stateFile, nextText, requireFocus) {
  const previous = readText(stateFile);
  if (previous === nextText) return true;
  if (!windowExists(windowId) || (requireFocus && !windowIsFocused(windowId))) return false;

  const update = planUpdate(previous, nextText);
  if (update.erase > 0) {
    eraseCharacters(windowId, update.erase);
    writeText(stateFile, update.prefix);
  }
  if (update.append) {
    runXdotool([
      'type', '--window', String(windowId), '--clearmodifiers', '--delay', '1', '--', update.append,
    ]);
  }
  writeText(stateFile, nextText);
  return true;
}

function requestJson(socketPath, request, timeoutMs) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let response = '';
    let settled = false;

    function finish(error, value) {
      if (settled) return;
      settled = true;
      socket.destroy();
      if (error) reject(error);
      else resolve(value);
    }

    socket.setEncoding('utf8');
    socket.setTimeout(timeoutMs, () => finish(new Error(`Timed out waiting for ${socketPath}`)));
    socket.on('connect', () => socket.end(`${JSON.stringify(request)}\n`));
    socket.on('data', (chunk) => {
      response += chunk;
    });
    socket.on('end', () => {
      try {
        const result = JSON.parse(response);
        if (!result.ok) throw new Error(result.error || 'Local dictation request failed.');
        finish(null, result);
      } catch (error) {
        finish(error);
      }
    });
    socket.on('error', (error) => finish(error));
  });
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function watch(args) {
  const [captureSocket, sherpaSocket, snapshotFile, windowId, statusFile, stateFile] = args;
  if (!captureSocket || !sherpaSocket || !snapshotFile || !windowId || !statusFile || !stateFile) {
    throw new Error('Usage: codex-dictation-live.js watch CAPTURE_SOCKET SHERPA_SOCKET SNAPSHOT WINDOW STATUS STATE');
  }

  const intervalMs = Number(process.env.CODEX_DICTATION_LIVE_INTERVAL_MS || 1000);
  const minimumBytes = Number(process.env.CODEX_DICTATION_LIVE_MIN_BYTES || 32000);
  const growthBytes = Number(process.env.CODEX_DICTATION_LIVE_GROWTH_BYTES || 16000);
  let lastBytes = 0;
  let lastError = '';

  while (readText(statusFile) === 'recording') {
    try {
      const snapshot = await requestJson(captureSocket, {
        command: 'snapshot',
        audioFile: snapshotFile,
      }, 5000);
      const bytes = Number(snapshot.bytes || 0);
      if (bytes >= minimumBytes && bytes - lastBytes >= growthBytes) {
        const result = await requestJson(sherpaSocket, { audioFile: snapshotFile }, 30000);
        const text = normalizeTranscript(result.text);
        if (text && !/^\[[^\]]+\]$/.test(text)) {
          updateComposer(windowId, stateFile, text, true);
        }
        lastBytes = bytes;
      }
      lastError = '';
    } catch (error) {
      if (error.message !== lastError) {
        console.error(`Live dictation: ${error.message}`);
        lastError = error.message;
      }
    }
    await sleep(intervalMs);
  }
}

function replace(args) {
  const [windowId, stateFile, nextFile] = args;
  if (!windowId || !stateFile || !nextFile) {
    throw new Error('Usage: codex-dictation-live.js replace WINDOW STATE NEXT');
  }
  updateComposer(windowId, stateFile, normalizeTranscript(readText(nextFile)), false);
}

function selfTest() {
  const update = planUpdate('hello world', 'hello there');
  if (update.prefix !== 'hello ' || update.erase !== 5 || update.append !== 'there') {
    throw new Error(`Unexpected replacement plan: ${JSON.stringify(update)}`);
  }
  const growth = planUpdate('hello', 'hello world');
  if (growth.prefix !== 'hello' || growth.erase !== 0 || growth.append !== ' world') {
    throw new Error(`Unexpected append plan: ${JSON.stringify(growth)}`);
  }
  process.stdout.write('self-test passed\n');
}

async function main() {
  const mode = process.argv[2];
  if (mode === 'watch') await watch(process.argv.slice(3));
  else if (mode === 'replace') replace(process.argv.slice(3));
  else if (mode === 'self-test') selfTest();
  else throw new Error('Usage: codex-dictation-live.js watch|replace|self-test ...');
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
