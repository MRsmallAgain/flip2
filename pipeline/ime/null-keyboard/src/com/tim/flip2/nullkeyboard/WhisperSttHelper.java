package com.tim.flip2.nullkeyboard;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.Manifest;

import java.io.File;
import java.util.Arrays;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Offline STT via whisper.cpp (batch): audio is captured from the mic for the
 * whole listen, then transcribed in one {@code whisper_full} call on stop.
 * Unlike Vosk there are no streaming partials and no decode-lag harvest.
 * Models are single ggml .bin files under app filesDir/whisper/{en,uk}/
 * (pushed by {@code flip2 ime whisper}); the language preference is the same
 * SharedPreferences key VoskSttHelper uses, so the engines are interchangeable.
 */
final class WhisperSttHelper implements SttEngine {

    static final String LANG_EN = "en";
    static final String LANG_UK = "uk";

    private static final String PREFS = "flip2_null_ime";
    private static final String KEY_LANG = "stt_lang";
    private static final int SAMPLE_RATE = 16000;
    private static final int CHANNEL_MASK = AudioFormat.CHANNEL_IN_MONO;
    private static final int ENCODING = AudioFormat.ENCODING_PCM_16BIT;
    private static final long LISTEN_TIMEOUT_MS = 12000L;
    /** whisper_full thread count — 2 of 4 little cores keeps the IME responsive. */
    private static final int N_THREADS = 2;
    /** Capture cap (~30 s) so a runaway listen cannot exhaust RAM. */
    private static final int MAX_CAPTURE_SECONDS = 30;
    /** Peak sample below which the capture is treated as silence (skips decode). */
    private static final int SILENCE_PEAK = 300;

    /** Extra roots after app-private files (mirrors VoskSttHelper). */
    private static final String[] MODEL_ROOTS_EXTRA = {
            "/sdcard/Android/data/com.tim.flip2.nullkeyboard/files/whisper",
            "/data/local/flip2/whisper",
    };

    /** Same contract as {@link SttEngine.Listener}; kept as a distinct type so
     *  existing call sites compile unchanged. */
    interface Listener extends SttEngine.Listener {
    }

    private static final boolean sLibOk;

    static {
        boolean ok;
        try {
            // libwhisper.so is linked against the NDK shared C++ runtime.
            // Load it first so a missing libc++_shared.so fails here, not as a
            // silent whisperjni dlopen that leaves the IME on Vosk.
            System.loadLibrary("c++_shared");
            System.loadLibrary("whisperjni");
            ok = true;
        } catch (Throwable t) {
            Log.e("Flip2STT", "whisperjni load failed", t);
            ok = false;
        }
        sLibOk = ok;
    }

    static boolean libOk() {
        return sLibOk;
    }

    static String getLang(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_LANG, LANG_EN);
    }

    static void setLang(Context ctx, String lang) {
        String v = LANG_UK.equals(lang) ? LANG_UK : LANG_EN;
        SharedPreferences.Editor ed = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit();
        ed.putString(KEY_LANG, v);
        ed.apply();
    }

    static String cycleLang(Context ctx) {
        String next = LANG_UK.equals(getLang(ctx)) ? LANG_EN : LANG_UK;
        setLang(ctx, next);
        return next;
    }

    /** True when a ggml model for {@code lang} exists on the device. */
    static boolean modelAvailable(Context ctx, String lang) {
        return findModelFile(new File(ctx.getFilesDir(), "whisper/" + lang)) != null
                || findModelFile(new File(MODEL_ROOTS_EXTRA[0], lang)) != null
                || findModelFile(new File(MODEL_ROOTS_EXTRA[1], lang)) != null;
    }

    private final Context mApp;
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private final ExecutorService mBg = Executors.newSingleThreadExecutor();
    private final SttEngine.Listener mListener;

    /** Native whisper_context pointer (owned; freed via nativeFree). */
    private long mCtx;
    private String mLoadedLang;
    /** Volatile: the capture thread reads it, stopListening writes it on the main thread. */
    private volatile boolean mListening;
    private boolean mStarting;
    /** Set by stopListening — the capture delivers its transcription only when true. */
    private boolean mDeliverFinal;
    /** Set once startRecording succeeded this capture (gates the mic retry). */
    private volatile boolean mMicStarted;
    private boolean mMicRetry;
    /** Bumped on every listen start; stale capture completions are discarded. */
    private int mListenGen;
    private final Runnable mTimeout = this::onListenTimeout;

    WhisperSttHelper(Context context, SttEngine.Listener listener) {
        mApp = context.getApplicationContext();
        mListener = listener;
        // Warm the current language model in the background so the first
        // hold-* does not stall the IME input path.
        preloadAsync(getLang(mApp));
    }

    boolean hasMicPermission() {
        return mApp.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED;
    }

    public boolean isListening() {
        return mListening || mStarting;
    }

    /** Start (or stop if already listening). Returns false if could not start. */
    boolean toggleListen() {
        if (mListening || mStarting) {
            stopListening(true);
            return true;
        }
        return startListening();
    }

    public boolean startListening() {
        if (mListening || mStarting) {
            return true;
        }
        if (!hasMicPermission()) {
            mListener.onError("Mic permission — run: flip2 ime whisper");
            return false;
        }
        final String lang = getLang(mApp);
        mMicRetry = false;
        mDeliverFinal = false;
        mStarting = true;
        mListener.onListening();
        mBg.execute(() -> {
            try {
                ensureModelLocked(lang);
                mMain.post(() -> beginCapture(lang));
            } catch (Throwable t) {
                failStarting(t);
            }
        });
        return true;
    }

    /** Main thread: mic still free, model ready — kick off the capture loop. */
    private void beginCapture(String lang) {
        if (!mStarting) {
            return; // cancelled while loading
        }
        // The capture thread exits as soon as mListening is false. Set it
        // before the loop starts or the mic opens and closes with no audio.
        mListening = true;
        final int gen = ++mListenGen;
        mMain.removeCallbacks(mTimeout);
        mMain.postDelayed(mTimeout, LISTEN_TIMEOUT_MS);
        mBg.execute(() -> captureLoop(lang, gen));
    }

    /** Bg thread: own the mic until {@link #stopListening} clears {@code mListening}. */
    private void captureLoop(String lang, int gen) {
        short[] audio = new short[SAMPLE_RATE * MAX_CAPTURE_SECONDS];
        int captured = 0;
        AudioRecord mic = null;
        Throwable error = null;
        mMicStarted = false;
        try {
            int minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_MASK, ENCODING);
            if (minBuf <= 0) {
                throw new IllegalStateException("AudioRecord init failed");
            }
            mic = new AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE, CHANNEL_MASK,
                    ENCODING, Math.max(minBuf * 2, SAMPLE_RATE));
            if (mic.getState() != AudioRecord.STATE_INITIALIZED) {
                throw new IllegalStateException("Mic busy");
            }
            mic.startRecording();
            mMicStarted = true;
            short[] chunk = new short[SAMPLE_RATE / 10]; // 100 ms
            while (mListening && captured < audio.length) {
                int n = mic.read(chunk, 0, chunk.length);
                if (n > 0) {
                    int take = Math.min(n, audio.length - captured);
                    System.arraycopy(chunk, 0, audio, captured, take);
                    captured += take;
                } else if (n < 0) {
                    throw new IllegalStateException("Mic read failed: " + n);
                } else {
                    Thread.sleep(20);
                }
            }
        } catch (Throwable t) {
            error = t;
        }
        if (mic != null) {
            try {
                mic.stop();
            } catch (Throwable ignored) {
            }
            try {
                mic.release();
            } catch (Throwable ignored) {
            }
        }
        final int nSamples = captured;
        final Throwable err = error;
        mMain.post(() -> finishCapture(lang, gen, audio, nSamples, err));
    }

    /** Main thread: capture ended (mic already released by the loop). */
    private void finishCapture(String lang, int gen, short[] audio, int n, Throwable err) {
        mMain.removeCallbacks(mTimeout);
        mListening = false;
        boolean deliver = mDeliverFinal;
        mDeliverFinal = false;
        if (err != null) {
            String msg = err.getMessage();
            if (msg == null || msg.length() == 0) {
                msg = err.getClass().getSimpleName();
            }
            // AudioFlinger briefly refuses a new record track right after the
            // previous one is torn down — retry once from a clean slate.
            if (!mMicRetry && !mMicStarted
                    && (msg.contains("already in use") || msg.contains("initialize")
                    || msg.contains("Mic busy"))) {
                mMicRetry = true;
                mMain.postDelayed(() -> {
                    if (mStarting && gen == mListenGen && getLang(mApp).equals(lang)) {
                        mListening = true;
                        mMain.removeCallbacks(mTimeout);
                        mMain.postDelayed(mTimeout, LISTEN_TIMEOUT_MS);
                        mBg.execute(() -> captureLoop(lang, gen));
                    } else {
                        mStarting = false;
                        mListener.onIdle();
                    }
                }, 600L);
                return;
            }
            mStarting = false;
            mListener.onError(msg);
            mListener.onIdle();
            return;
        }
        mStarting = false;
        if (!deliver) {
            mListener.onIdle();
            return;
        }
        if (n == 0 || peak(audio, n) < SILENCE_PEAK) {
            mListener.onError("No speech detected");
            mListener.onIdle();
            return;
        }
        final short[] pcm = Arrays.copyOf(audio, n);
        mBg.execute(() -> {
            String text = null;
            Throwable terr = null;
            try {
                text = nativeTranscribe(mCtx, pcm, lang, N_THREADS);
            } catch (Throwable t) {
                terr = t;
            }
            final String fText = text == null ? "" : text.trim();
            final String fErr = terr == null ? null
                    : (terr.getMessage() != null ? terr.getMessage()
                    : terr.getClass().getSimpleName());
            mMain.post(() -> {
                if (fErr != null) {
                    mListener.onError(fErr);
                } else if (fText.length() > 0) {
                    mListener.onFinal(fText);
                } else {
                    mListener.onError("No speech detected");
                }
                mListener.onIdle();
            });
        });
    }

    public void stopListening(boolean deliverFinal) {
        mMain.removeCallbacks(mTimeout);
        if (!mListening) {
            mStarting = false;
            mListener.onIdle();
            return;
        }
        mListening = false;
        mDeliverFinal = deliverFinal;
        // The capture loop notices within one read (~100 ms), releases the mic,
        // and finishCapture then delivers or discards.
    }

    /** After lang change while listening: load new model then start mic. */
    public void switchLangAndListen() {
        stopListening(false);
        final String lang = getLang(mApp);
        mStarting = true;
        mListener.onListening();
        mBg.execute(() -> {
            try {
                ensureModelLocked(lang);
                mMain.post(() -> beginCapture(lang));
            } catch (Throwable t) {
                failStarting(t);
            }
        });
    }

    /** Drop the cached native model so the next listen reloads. */
    void invalidateModel() {
        stopListening(false);
        try {
            mBg.execute(() -> {
                synchronized (this) {
                    if (mCtx != 0) {
                        nativeFree(mCtx);
                        mCtx = 0;
                        mLoadedLang = null;
                    }
                }
                preloadAsync(getLang(mApp));
            });
        } catch (Throwable ignored) {
        }
    }

    public void release() {
        stopListening(false);
        try {
            mBg.execute(() -> {
                synchronized (this) {
                    if (mCtx != 0) {
                        nativeFree(mCtx);
                        mCtx = 0;
                        mLoadedLang = null;
                    }
                }
            });
            mBg.shutdown();
        } catch (Throwable ignored) {
        }
    }

    private void preloadAsync(String lang) {
        try {
            mBg.execute(() -> {
                try {
                    ensureModelLocked(lang);
                } catch (Throwable ignored) {
                    // First hold-* surfaces the error.
                }
            });
        } catch (Throwable ignored) {
        }
    }

    private void onListenTimeout() {
        stopListening(true);
    }

    private void failStarting(Throwable t) {
        String msg = t.getMessage();
        if (msg == null || msg.length() == 0) {
            msg = t.getClass().getSimpleName();
        }
        final String err = msg;
        mMain.post(() -> {
            mStarting = false;
            mListener.onError(err);
            mListener.onIdle();
        });
    }

    /** Must run on {@link #mBg}. */
    private synchronized void ensureModelLocked(String lang) throws Exception {
        if (!sLibOk) {
            throw new Exception("libwhisperjni missing — rebuild APK");
        }
        if (mCtx != 0 && lang.equals(mLoadedLang)) {
            return;
        }
        if (mCtx != 0) {
            nativeFree(mCtx);
            mCtx = 0;
            mLoadedLang = null;
        }
        File f = findModelFile(new File(mApp.getFilesDir(), "whisper/" + lang));
        if (f == null) {
            for (String root : MODEL_ROOTS_EXTRA) {
                f = findModelFile(new File(root, lang));
                if (f != null) {
                    break;
                }
            }
        }
        if (f == null) {
            throw new Exception("No " + lang + " whisper model — flip2 ime whisper");
        }
        mCtx = nativeInit(f.getAbsolutePath());
        if (mCtx == 0) {
            throw new Exception("Whisper model load failed (" + f.getName() + ")");
        }
        mLoadedLang = lang;
    }

    /** Largest ggml .bin in {@code dir} (>= 1 MB), or null. */
    private static File findModelFile(File dir) {
        File[] files = dir.listFiles();
        if (files == null) {
            return null;
        }
        File best = null;
        for (File f : files) {
            if (f.isFile() && f.getName().endsWith(".bin") && f.length() > 1024L * 1024) {
                if (best == null || f.length() > best.length()) {
                    best = f;
                }
            }
        }
        return best;
    }

    private static int peak(short[] a, int n) {
        int p = 0;
        for (int i = 0; i < n; i++) {
            int v = a[i] < 0 ? -a[i] : a[i];
            if (v > p) {
                p = v;
            }
        }
        return p;
    }

    private static native long nativeInit(String modelPath);

    private static native void nativeFree(long ctx);

    private static native String nativeTranscribe(long ctx, short[] pcm, String lang, int nThreads);
}
