'use strict';

if (process.type === 'browser') {
    const { BrowserWindow } = require('electron');
    const suppressedTitles = new Set([
        'Voice Recorder',
        'Sprachrekorder',
        'Grabadora de voz',
        'Enregistreur vocal',
        'Registratore vocale',
        'ボイスレコーダー',
        'Gravador de voz',
        'Диктофон',
        '录音器',
        '錄音器',
    ]);

    const isSuppressedWindow = (window) => {
        try {
            return !window.isDestroyed() && suppressedTitles.has(window.getTitle());
        } catch {
            return false;
        }
    };

    for (const methodName of ['show', 'showInactive', 'restore', 'focus']) {
        const originalMethod = BrowserWindow.prototype[methodName];

        BrowserWindow.prototype[methodName] = function (...args) {
            if (isSuppressedWindow(this)) {
                if (this.isVisible()) {
                    this.hide();
                }
                return;
            }

            return Reflect.apply(originalMethod, this, args);
        };
    }
}
