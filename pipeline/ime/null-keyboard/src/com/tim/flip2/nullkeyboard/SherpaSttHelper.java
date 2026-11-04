package com.tim.flip2.nullkeyboard;

import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.Manifest;

import com.k2fsa.sherpa.onnx.EndpointConfig;
import com.k2fsa.sherpa.onnx.EndpointRule;
import com.k2fsa.sherpa.onnx.FeatureConfig;
import com.k2fsa.sherpa.onnx.OnlineModelConfig;
import com.k2fsa.sherpa.onnx.OnlineRecognizer;
import com.k2fsa.sherpa.onnx.OnlineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OnlineRecognizerResult;
import com.k2fsa.sherpa.onnx.OnlineStream;
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Offline streaming STT via Sherpa-ONNX. Models: files/sherpa/{en,uk}/ */
final class SherpaSttHelper implements SttEngine {

    static final String LANG_EN = "en";
    static final String LANG_UK = "uk";
    private static final String PREFS = "flip2_null_ime";
    private static final String KEY_LANG = "stt_lang";
    private static final int SAMPLE_RATE = 16000;
    private static final int LISTEN_TIMEOUT_MS = 12000;
    private static final String TAG = "Flip2STT";
    private static final String[] MODEL_ROOTS_EXTRA = {
            "/sdcard/Android/data/com.tim.flip2.nullkeyboard/files/sherpa",
            "/data/local/flip2/sherpa",
    };

    private static final boolean sLibOk;
    static {
        boolean ok;
        try {
            System.loadLibrary("onnxruntime");
            System.loadLibrary("sherpa-onnx-jni");
            ok = true;
        } catch (Throwable t) {
            Log.e(TAG, "sherpa load failed", t);
            ok = false;
        }
        sLibOk = ok;
    }

    static boolean libOk() { return sLibOk; }

    private final Context mApp;
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private final ExecutorService mBg = Executors.newSingleThreadExecutor();
    private final SttEngine.Listener mListener;
    private OnlineRecognizer mRecognizer;
    private String mLoadedLang;
    private AudioRecord mAudioRecord;
    private Thread mCaptureThread;
    private final AtomicBoolean mRecording = new AtomicBoolean(false);
    private volatile boolean mListening;
    private volatile boolean mStarting;
    private final Runnable mTimeout = this::onListenTimeout;

    SherpaSttHelper(Context context, SttEngine.Listener listener) {
        mApp = context.getApplicationContext();
        mListener = listener;
        preloadAsync(getLang(mApp));
    }

    static String getLang(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LANG, LANG_EN);
    }
    static void setLang(Context ctx, String lang) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_LANG, LANG_UK.equals(lang) ? LANG_UK : LANG_EN).apply();
    }
    static String cycleLang(Context ctx) {
        String next = LANG_UK.equals(getLang(ctx)) ? LANG_EN : LANG_UK;
        setLang(ctx, next);
        return next;
    }
    static boolean modelAvailable(Context ctx, String lang) { return findModelDir(ctx, lang) != null; }
    static boolean anyModelAvailable(Context ctx) {
        return modelAvailable(ctx, LANG_EN) || modelAvailable(ctx, LANG_UK);
    }

    @Override public boolean isListening() { return mListening || mStarting; }

    @Override
    public boolean startListening() {
        if (mListening || mStarting) return true;
        if (!sLibOk) { mListener.onError("Sherpa libs missing"); return false; }
        if (mApp.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            mListener.onError("Mic permission — flip2 ime sherpa"); return false;
        }
        final String lang = getLang(mApp);
        if (!modelAvailable(mApp, lang)) {
            mListener.onError("No " + lang + " model — flip2 ime sherpa"); return false;
        }
        mStarting = true;
        mListener.onListening();
        mBg.execute(() -> {
            try {
                ensureRecognizerLocked(lang);
                mMain.post(this::beginCapture);
            } catch (Throwable t) {
                String err = t.getMessage();
                if (err == null || err.isEmpty()) err = t.getClass().getSimpleName();
                final String e = err;
                mMain.post(() -> { mStarting = false; mListener.onError(e); mListener.onIdle(); });
            }
        });
        return true;
    }

    private void beginCapture() {
        if (!mStarting) return;
        try {
            int minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT);
            mAudioRecord = new AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, Math.max(minBuf, 1) * 2);
            if (mAudioRecord.getState() != AudioRecord.STATE_INITIALIZED) throw new IllegalStateException("Mic init failed");
            mAudioRecord.startRecording();
            mRecording.set(true);
            mStarting = false;
            mListening = true;
            mMain.removeCallbacks(mTimeout);
            mMain.postDelayed(mTimeout, LISTEN_TIMEOUT_MS + 500L);
            mCaptureThread = new Thread(this::captureLoop, "flip2-sherpa");
            mCaptureThread.start();
        } catch (Throwable t) {
            mStarting = false;
            releaseMic();
            mListener.onError(t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName());
            mListener.onIdle();
        }
    }

    private void captureLoop() {
        OnlineRecognizer rec = mRecognizer;
        if (rec == null) return;
        OnlineStream stream = rec.createStream("");
        int chunk = (int) (0.1 * SAMPLE_RATE);
        short[] buf = new short[chunk];
        String lastPartial = "";
        try {
            while (mRecording.get() && mAudioRecord != null) {
                int n = mAudioRecord.read(buf, 0, buf.length);
                if (n <= 0) continue;
                float[] samples = new float[n];
                for (int i = 0; i < n; i++) samples[i] = buf[i] / 32768.0f;
                stream.acceptWaveform(samples, SAMPLE_RATE);
                while (rec.isReady(stream)) rec.decode(stream);
                OnlineRecognizerResult result = rec.getResult(stream);
                String text = result != null ? result.getText() : "";
                if (text != null && text.length() > 0 && !text.equals(lastPartial)) {
                    lastPartial = text;
                    final String show = text;
                    mMain.post(() -> { if (mListening) mListener.onPartial(show); });
                }
                if (rec.isEndpoint(stream)) {
                    rec.reset(stream);
                    if (text != null && text.length() > 0) {
                        final String fin = text;
                        mMain.post(() -> { if (mListening) mListener.onFinal(fin); });
                    }
                    lastPartial = "";
                }
            }
        } catch (Throwable t) {
            Log.e(TAG, "capture", t);
        } finally {
            try { stream.release(); } catch (Throwable ignored) {}
        }
    }

    @Override
    public void stopListening(boolean deliverFinal) {
        mMain.removeCallbacks(mTimeout);
        mRecording.set(false);
        mListening = false;
        mStarting = false;
        releaseMic();
        mListener.onIdle();
    }

    private void releaseMic() {
        mRecording.set(false);
        AudioRecord ar = mAudioRecord;
        mAudioRecord = null;
        if (ar != null) {
            try { ar.stop(); } catch (Throwable ignored) {}
            try { ar.release(); } catch (Throwable ignored) {}
        }
        Thread t = mCaptureThread;
        mCaptureThread = null;
        if (t != null) try { t.join(1500L); } catch (InterruptedException ignored) {}
    }

    @Override public void switchLangAndListen() { stopListening(false); invalidateRecognizer(); startListening(); }

    @Override
    public void release() {
        stopListening(false);
        mBg.execute(() -> {
            synchronized (SherpaSttHelper.this) {
                if (mRecognizer != null) { try { mRecognizer.release(); } catch (Throwable ignored) {} mRecognizer = null; mLoadedLang = null; }
            }
        });
        mBg.shutdown();
    }

    private void invalidateRecognizer() {
        mBg.execute(() -> {
            synchronized (SherpaSttHelper.this) {
                if (mRecognizer != null) { try { mRecognizer.release(); } catch (Throwable ignored) {} mRecognizer = null; mLoadedLang = null; }
            }
            preloadAsync(getLang(mApp));
        });
    }

    private void onListenTimeout() { stopListening(true); }

    private void preloadAsync(String lang) {
        if (!modelAvailable(mApp, lang)) return;
        mBg.execute(() -> { try { ensureRecognizerLocked(lang); } catch (Throwable ignored) {} });
    }

    private synchronized void ensureRecognizerLocked(String lang) throws Exception {
        if (mRecognizer != null && lang.equals(mLoadedLang)) return;
        if (mRecognizer != null) { mRecognizer.release(); mRecognizer = null; mLoadedLang = null; }
        File dir = findModelDir(mApp, lang);
        if (dir == null) throw new Exception("No " + lang + " model — flip2 ime sherpa");
        mRecognizer = new OnlineRecognizer(null, buildConfig(dir, lang));
        mLoadedLang = lang;
    }

    private static OnlineRecognizerConfig buildConfig(File modelDir, String lang) throws Exception {
        String base = modelDir.getAbsolutePath();
        OnlineTransducerModelConfig transducer = new OnlineTransducerModelConfig("", "", "", null);
        if (LANG_EN.equals(lang)) {
            transducer.setEncoder(firstExisting(base, "encoder-epoch-99-avg-1.int8.onnx", "encoder-epoch-99-avg-1.onnx"));
            transducer.setDecoder(firstExisting(base, "decoder-epoch-99-avg-1.onnx"));
            transducer.setJoiner(firstExisting(base, "joiner-epoch-99-avg-1.int8.onnx", "joiner-epoch-99-avg-1.onnx"));
        } else {
            transducer.setEncoder(base + "/encoder.int8.onnx");
            transducer.setDecoder(base + "/decoder.int8.onnx");
            transducer.setJoiner(base + "/joiner.int8.onnx");
        }
        OnlineModelConfig modelConfig = new OnlineModelConfig(transducer, null, null, null, null,
                base + "/tokens.txt", 2, false, "cpu", "zipformer", "", "");
        FeatureConfig feat = new FeatureConfig(SAMPLE_RATE, 80, 0.0f);
        EndpointConfig ep = new EndpointConfig(
                new EndpointRule(false, 2.4f, 0.0f), new EndpointRule(true, 1.4f, 0.0f),
                new EndpointRule(false, 0.0f, 20.0f));
        return new OnlineRecognizerConfig(feat, modelConfig, null, null, null, ep, true,
                "greedy_search", 4, "", 1.5f, "", "", 0.0f);
    }

    private static String firstExisting(String base, String... names) throws Exception {
        for (String n : names) {
            File f = new File(base, n);
            if (f.isFile()) return f.getAbsolutePath();
        }
        throw new Exception("Missing model under " + base);
    }

    private static File findModelDir(Context ctx, String lang) {
        File local = new File(ctx.getFilesDir(), "sherpa/" + lang);
        if (isSherpaModelDir(local, lang)) return local;
        for (String root : MODEL_ROOTS_EXTRA) {
            File f = new File(root, lang);
            if (isSherpaModelDir(f, lang)) return f;
        }
        return null;
    }

    private static boolean isSherpaModelDir(File dir, String lang) {
        if (dir == null || !dir.isDirectory() || !new File(dir, "tokens.txt").isFile()) return false;
        if (LANG_EN.equals(lang)) {
            return new File(dir, "encoder-epoch-99-avg-1.onnx").isFile()
                    || new File(dir, "encoder-epoch-99-avg-1.int8.onnx").isFile();
        }
        return new File(dir, "encoder.int8.onnx").isFile();
    }
}
