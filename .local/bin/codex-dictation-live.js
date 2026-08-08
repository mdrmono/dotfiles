#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const { spawnSync } = require('node:child_process');

const xdotool = '/usr/local/bin/xdotool';
const xclip = '/usr/bin/xclip';
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

function comparableWord(value) {
  return value.toLocaleLowerCase().replace(/^\W+|\W+$/gu, '');
}

function mergeTranscripts(previous, segment) {
  if (!previous) return segment;
  if (!segment) return previous;

  const previousWords = previous.split(' ');
  const segmentWords = segment.split(' ');
  const maximum = Math.min(previousWords.length, segmentWords.length);
  let overlap = 0;
  for (let size = maximum; size > 0; size -= 1) {
    const previousTail = previousWords.slice(-size).map(comparableWord);
    const segmentHead = segmentWords.slice(0, size).map(comparableWord);
    if (previousTail.every((word, index) => word && word === segmentHead[index])) {
      overlap = size;
      break;
    }
  }
  return normalizeTranscript([...previousWords, ...segmentWords.slice(overlap)].join(' '));
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

function sendRepeatedKey(windowId, key, count) {
  let remaining = count;
  while (remaining > 0) {
    const chunk = Math.min(remaining, 128);
    runXdotool([
      'key', '--window', String(windowId), '--clearmodifiers', '--delay', '1',
      ...Array(chunk).fill(key),
    ]);
    remaining -= chunk;
  }
}

function readPrimarySelection() {
  const result = spawnSync(xclip, ['-selection', 'primary', '-o'], {
    encoding: 'utf8',
    timeout: 1000,
  });
  return result.status === 0 ? result.stdout : null;
}

function seedPrimarySelection(value) {
  const result = spawnSync(xclip, ['-selection', 'primary', '-i'], {
    input: value,
    encoding: 'utf8',
    timeout: 1000,
  });
  return result.status === 0;
}

function eraseOwnedText(windowId, expected) {
  if (!expected) return true;
  if (dryRun) {
    if (process.env.CODEX_DICTATION_LIVE_OWNERSHIP === 'unowned') return false;
    sendRepeatedKey(windowId, 'BackSpace', 1);
    return true;
  }
  if (!windowIsFocused(windowId)) return false;

  const count = Array.from(expected).length;
  const nonce = `codex-dictation-${process.pid}-${Date.now()}`;
  if (!seedPrimarySelection(nonce)) return false;

  sendRepeatedKey(windowId, 'shift+Left', count);
  const selected = readPrimarySelection();
  if (selected === expected) {
    sendRepeatedKey(windowId, 'BackSpace', 1);
    return true;
  }
  if (selected === nonce || selected === null) sendRepeatedKey(windowId, 'Right', count);
  else sendRepeatedKey(windowId, 'Right', 1);
  return false;
}

function updateComposer(windowId, stateFile, nextText, requireFocus) {
  const previous = readText(stateFile);
  if (previous === nextText) return 'unchanged';
  if (!windowExists(windowId) || (requireFocus && !windowIsFocused(windowId))) return 'unavailable';

  const update = planUpdate(previous, nextText);
  if (update.erase > 0) {
    if (!eraseOwnedText(windowId, previous)) return 'unowned';
    writeText(stateFile, '');
    if (nextText) {
      runXdotool([
        'type', '--window', String(windowId), '--clearmodifiers', '--delay', '1', '--', nextText,
      ]);
    }
    writeText(stateFile, nextText);
    return 'updated';
  }
  if (update.append) {
    runXdotool([
      'type', '--window', String(windowId), '--clearmodifiers', '--delay', '1', '--', update.append,
    ]);
  }
  writeText(stateFile, nextText);
  return 'updated';
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
  const minimumBytes = Number(process.env.CODEX_DICTATION_LIVE_MIN_BYTES || 48000);
  const growthBytes = Number(process.env.CODEX_DICTATION_LIVE_GROWTH_BYTES || 48000);
  const overlapBytes = Number(process.env.CODEX_DICTATION_LIVE_OVERLAP_BYTES || 16000);
  let firstChunk = true;
  let snapshotReady = false;
  let transcript = '';
  let lastError = '';

  while (readText(statusFile) === 'recording') {
    try {
      if (!snapshotReady) {
        const snapshot = await requestJson(captureSocket, {
          command: 'snapshot',
          audioFile: snapshotFile,
          minimumBytes: firstChunk ? minimumBytes : growthBytes,
          overlapBytes,
        }, 5000);
        snapshotReady = Number(snapshot.chunkBytes || 0) > 0;
        if (snapshotReady) firstChunk = false;
      }
      if (snapshotReady) {
        const result = await requestJson(sherpaSocket, { audioFile: snapshotFile }, 30000);
        const segment = normalizeTranscript(result.text);
        if (segment && !/^\[[^\]]+\]$/.test(segment)) {
          transcript = mergeTranscripts(transcript, segment);
          updateComposer(windowId, stateFile, transcript, true);
        }
        snapshotReady = false;
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
  const nextText = normalizeTranscript(readText(nextFile));
  const result = updateComposer(windowId, stateFile, nextText, false);
  if (result === 'unavailable') throw new Error('The original Codex window is unavailable.');
  if (result === 'unowned' && nextText) {
    runXdotool([
      'type', '--window', String(windowId), '--clearmodifiers', '--delay', '1', '--', ` ${nextText}`,
    ]);
  }
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
  const merged = mergeTranscripts('hello from local speech', 'local speech recognition works');
  if (merged !== 'hello from local speech recognition works') {
    throw new Error(`Unexpected transcript merge: ${merged}`);
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
