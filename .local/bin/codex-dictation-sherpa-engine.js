'use strict';

const fs = require('node:fs');
const path = require('node:path');

function createEngine(options = {}) {
  const nativeDir = options.nativeDir || process.env.CODEX_DICTATION_SHERPA_NATIVE_DIR ||
    path.join(process.env.HOME || '', '.local/share/codex-dictation/sherpa-onnx-linux-x64');
  const modelDir = options.modelDir || process.env.CODEX_DICTATION_SHERPA_MODEL_DIR ||
    path.join(process.env.HOME || '', '.paseo/models/local-speech/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8');
  const nativeModule = path.join(nativeDir, 'index.js');
  const model = {
    encoder: path.join(modelDir, 'encoder.int8.onnx'),
    decoder: path.join(modelDir, 'decoder.int8.onnx'),
    joiner: path.join(modelDir, 'joiner.int8.onnx'),
    tokens: path.join(modelDir, 'tokens.txt'),
  };

  for (const target of [
    path.join(nativeDir, 'sherpa-onnx.node'),
    nativeModule,
    ...Object.values(model),
  ]) {
    if (!fs.existsSync(target)) {
      throw new Error(`Missing Sherpa-ONNX file: ${target}`);
    }
  }

  const libraryPath = process.env.LD_LIBRARY_PATH || '';
  if (!libraryPath.split(':').includes(nativeDir)) {
    process.env.LD_LIBRARY_PATH = [nativeDir, libraryPath].filter(Boolean).join(':');
  }

  const sherpa = require(nativeModule);
  const recognizer = sherpa.createOfflineRecognizer({
    featConfig: {
      sampleRate: 16000,
      featureDim: 80,
    },
    modelConfig: {
      transducer: {
        encoder: model.encoder,
        decoder: model.decoder,
        joiner: model.joiner,
      },
      tokens: model.tokens,
      modelType: 'nemo_transducer',
      numThreads: Number(options.threads || process.env.CODEX_DICTATION_SHERPA_THREADS || 4),
      provider: 'cpu',
      debug: 0,
    },
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
  });

  return {
    transcribe(audioFile) {
      const wave = sherpa.readWave(audioFile);
      if (!wave || wave.sampleRate !== 16000) {
        throw new Error(`Sherpa expects 16 kHz WAV audio; received ${wave?.sampleRate || 'unknown'} Hz`);
      }
      const stream = sherpa.createOfflineStream(recognizer);
      sherpa.acceptWaveformOffline(stream, wave);
      sherpa.decodeOfflineStream(recognizer, stream);
      const result = JSON.parse(sherpa.getOfflineStreamResultAsJson(stream));
      return String(result.text || '').trim();
    },
  };
}

module.exports = { createEngine };
