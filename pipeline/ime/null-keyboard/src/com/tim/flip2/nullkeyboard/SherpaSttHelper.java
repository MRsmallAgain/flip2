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
import com.k2fsa.sherpa.onnx.OfflineModelConfig;
import com.k2fsa.sherpa.onnx.OfflineRecognizer;
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OfflineRecognizerResult;
import com.k2fsa.sherpa.onnx.OfflineStream;
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig;
import com.k2fsa.sherpa.onnx.OnlineModelConfig;
import com.k2fsa.sherpa.onnx.OnlineRecognizer;
import com.k2fsa.sherpa.onnx.OnlineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OnlineRecognizerResult;
import com.k2fsa.sherpa.onnx.OnlineStream;
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Offline dictation via Sherpa-ONNX. Models: files/sherpa/{en,uk}/
 *
 * <p>EN uses the streaming zipformer with {@link OnlineRecognizer} (live
 * partials). UK only exists upstream as an offline multilingual NeMo model, so
 * it buffers the whole utterance and decodes once through
 * {@link OfflineRecognizer} with {@code model_type=nemo_transducer}.
 */
final class SherpaSttHelper implements SttEngine {

    static final String LANG_EN = "en";
    static final String LANG_UK = "uk";
    private static final String PREFS = "flip2_null_ime";
    private static final String KEY_LANG = "stt_lang";
    private static final int SAMPLE_RATE = 16000;
    private static final int LISTEN_TIMEOUT_MS = 12000;
    /** Cap preroll while the Sherpa model loads (~4 s at 16 kHz). */
    private static final int PREROLL_MAX_SAMPLES = SAMPLE_RATE * 4;
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
    private OfflineRecognizer mOffline;
    private String mLoadedOfflineLang;
    /** UK only: whole-utterance PCM, drained by {@link #decodeOffline()}. */
    private final List<float[]> mOfflinePcm = Collections.synchronizedList(new ArrayList<float[]>());
    /** PCM captured while the Sherpa model loads; drained when capture starts. */
    private final List<float[]> mPrerollPcm = Collections.synchronizedList(new ArrayList<float[]>());
    private volatile boolean mOfflineMode;
    private AudioRecord mAudioRecord;
    private Thread mCaptureThread;
    private Thread mPrerollThread;
    private volatile boolean mPrerollActive;
    private final AtomicBoolean mRecording = new AtomicBoolean(false);
    private volatile boolean mListening;
    private volatile boolean mStarting;
    /** Set when stopping, so the capture thread flushes its pending streaming text. */
    private volatile boolean mFlushOnStop;
    /** Tail text produced by that flush, handed back to the caller of stopListening(). */
    private volatile String mStreamFinal;
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
        clearOfflinePcm();
        clearPrerollPcm();
        mOfflineMode = LANG_UK.equals(lang);
        mStarting = true;
        mListener.onListening();
        if (!startMicPreroll()) {
            mStarting = false;
            return false;
        }
        mBg.execute(() -> {
            try {
                if (mOfflineMode) ensureOfflineLocked(lang);
                else ensureRecognizerLocked(lang);
                mMain.post(this::beginCapture);
            } catch (Throwable t) {
                String err = t.getMessage();
                if (err == null || err.isEmpty()) err = t.getClass().getSimpleName();
                final String e = err;
                mMain.post(() -> { mStarting = false; releaseMic(); mListener.onError(e); mListener.onIdle(); });
            }
        });
        return true;
    }

    /** FGS + mic + preroll thread before model load so early speech is not dropped. */
    private boolean startMicPreroll() {
        try {
            SttForegroundService.start(mApp);
            int minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT);
            mAudioRecord = new AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, Math.max(minBuf, 1) * 2);
            if (mAudioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                throw new IllegalStateException("Mic init failed");
            }
            mAudioRecord.startRecording();
            mPrerollActive = true;
            mPrerollThread = new Thread(this::capturePreroll, "flip2-sherpa-preroll");
            mPrerollThread.start();
            Log.i(TAG, "preroll mic started");
            return true;
        } catch (Throwable t) {
            releaseMic();
            mListener.onError(t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName());
            mListener.onIdle();
            return false;
        }
    }

    private void capturePreroll() {
        int chunk = (int) (0.1 * SAMPLE_RATE);
        short[] buf = new short[chunk];
        try {
            while (mPrerollActive && mAudioRecord != null) {
                int n = mAudioRecord.read(buf, 0, buf.length);
                if (n <= 0) continue;
                float[] samples = new float[n];
                for (int i = 0; i < n; i++) samples[i] = buf[i] / 32768.0f;
                appendPreroll(samples);
            }
        } catch (Throwable t) {
            Log.e(TAG, "preroll capture", t);
        }
    }

    private void appendPreroll(float[] samples) {
        synchronized (mPrerollPcm) {
            mPrerollPcm.add(samples);
            int total = 0;
            for (float[] c : mPrerollPcm) total += c.length;
            while (total > PREROLL_MAX_SAMPLES && !mPrerollPcm.isEmpty()) {
                total -= mPrerollPcm.get(0).length;
                mPrerollPcm.remove(0);
            }
        }
    }

    private List<float[]> drainPrerollPcm() {
        synchronized (mPrerollPcm) {
            if (mPrerollPcm.isEmpty()) return Collections.emptyList();
            List<float[]> out = new ArrayList<>(mPrerollPcm);
            mPrerollPcm.clear();
            return out;
        }
    }

    private void clearPrerollPcm() {
        synchronized (mPrerollPcm) { mPrerollPcm.clear(); }
    }

    private void stopPrerollThread() {
        mPrerollActive = false;
        Thread t = mPrerollThread;
        mPrerollThread = null;
        if (t != null) {
            try { t.join(800L); } catch (InterruptedException ignored) {}
        }
    }

    private void beginCapture() {
        if (!mStarting) return;
        try {
            stopPrerollThread();
            List<float[]> preroll = drainPrerollPcm();
            int prerollSamples = 0;
            for (float[] c : preroll) prerollSamples += c.length;
            if (prerollSamples > 0) {
                Log.i(TAG, "preroll drained " + (prerollSamples / (float) SAMPLE_RATE) + "s");
            }
            mRecording.set(true);
            mStarting = false;
            mListening = true;
            mMain.removeCallbacks(mTimeout);
            mMain.postDelayed(mTimeout, LISTEN_TIMEOUT_MS + 500L);
            final List<float[]> pr = preroll;
            mCaptureThread = new Thread(() -> {
                if (mOfflineMode) captureOffline(pr);
                else captureStreaming(pr);
            }, "flip2-sherpa");
            mCaptureThread.start();
        } catch (Throwable t) {
            mStarting = false;
            releaseMic();
            mListener.onError(t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName());
            mListener.onIdle();
        }
    }

    private void captureStreaming(List<float[]> preroll) {
        OnlineRecognizer rec = mRecognizer;
        if (rec == null) return;
        OnlineStream stream = rec.createStream("");
        int chunk = (int) (0.1 * SAMPLE_RATE);
        short[] buf = new short[chunk];
        String lastPartial = "";
        try {
            for (float[] pre : preroll) {
                if (pre == null || pre.length == 0) continue;
                stream.acceptWaveform(pre, SAMPLE_RATE);
                while (rec.isReady(stream)) rec.decode(stream);
            }
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
            /* Without an endpoint the recognizer never commits, so releasing * mid
               sentence used to throw the transcript away. inputFinished() makes the
               tail decodable and we hand it back through mStreamFinal. */
            try {
                if (mFlushOnStop) {
                    stream.inputFinished();
                    while (rec.isReady(stream)) rec.decode(stream);
                    OnlineRecognizerResult tail = rec.getResult(stream);
                    String text = tail != null ? tail.getText() : null;
                    if (text != null && text.length() > 0) {
                        mStreamFinal = text;
                        Log.i(TAG, "stream flush [" + text + "]");
                    }
                }
            } catch (Throwable t) {
                Log.e(TAG, "stream flush", t);
            }
            try { stream.release(); } catch (Throwable ignored) {}
        }
    }

    /** UK: no partials are possible from an offline model, so just buffer. */
    private void captureOffline(List<float[]> preroll) {
        for (float[] pre : preroll) {
            if (pre != null && pre.length > 0) mOfflinePcm.add(pre);
        }
        int chunk = (int) (0.1 * SAMPLE_RATE);
        short[] buf = new short[chunk];
        try {
            while (mRecording.get() && mAudioRecord != null) {
                int n = mAudioRecord.read(buf, 0, buf.length);
                if (n <= 0) continue;
                float[] samples = new float[n];
                for (int i = 0; i < n; i++) samples[i] = buf[i] / 32768.0f;
                mOfflinePcm.add(samples);
            }
        } catch (Throwable t) {
            Log.e(TAG, "offline capture", t);
        }
    }

    @Override
    public void stopListening(boolean deliverFinal) {
        mMain.removeCallbacks(mTimeout);
        boolean wasListening = mListening;
        boolean offline = mOfflineMode;
        mStreamFinal = null;
        mFlushOnStop = !offline && deliverFinal && wasListening;
        mRecording.set(false);
        mListening = false;
        mStarting = false;
        releaseMic();
        mFlushOnStop = false;
        if (offline && deliverFinal && wasListening) {
            mBg.execute(() -> {
                final String text = decodeOffline();
                mMain.post(() -> {
                    if (text != null && text.length() > 0) mListener.onFinal(text);
                    mListener.onIdle();
                });
            });
        } else if (!offline && wasListening) {
            String tail = mStreamFinal;
            mStreamFinal = null;
            if (tail != null && tail.length() > 0) mListener.onFinal(tail);
            mListener.onIdle();
        } else {
            clearOfflinePcm();
            mListener.onIdle();
        }
    }

    private void releaseMic() {
        mRecording.set(false);
        mPrerollActive = false;
        stopPrerollThread();
        clearPrerollPcm();
        AudioRecord ar = mAudioRecord;
        mAudioRecord = null;
        if (ar != null) {
            try { ar.stop(); } catch (Throwable ignored) {}
            try { ar.release(); } catch (Throwable ignored) {}
        }
        Thread t = mCaptureThread;
        mCaptureThread = null;
        if (t != null) try { t.join(1500L); } catch (InterruptedException ignored) {}
        SttForegroundService.stop(mApp);
    }

    /** Drains the UK buffer and runs the offline recognizer on the bg executor. */
    private String decodeOffline() {
        OfflineRecognizer rec;
        synchronized (this) { rec = mOffline; }
        List<float[]> chunks;
        synchronized (mOfflinePcm) {
            chunks = new ArrayList<>(mOfflinePcm);
            mOfflinePcm.clear();
        }
        if (rec == null || chunks.isEmpty()) return null;
        int total = 0;
        for (int i = 0; i < chunks.size(); i++) total += chunks.get(i).length;
        if (total == 0) return null;
        float[] all = new float[total];
        int off = 0;
        for (int i = 0; i < chunks.size(); i++) {
            float[] c = chunks.get(i);
            System.arraycopy(c, 0, all, off, c.length);
            off += c.length;
        }
        OfflineStream stream = rec.createStream();
        try {
            stream.acceptWaveform(all, SAMPLE_RATE);
            rec.decode(stream);
            OfflineRecognizerResult r = rec.getResult(stream);
            String text = r != null ? r.getText() : null;
            Log.i(TAG, "offline decode " + (total / (float) SAMPLE_RATE) + "s -> [" + text + "]");
            return text;
        } catch (Throwable t) {
            Log.e(TAG, "offline decode", t);
            return null;
        } finally {
            try { stream.release(); } catch (Throwable ignored) {}
        }
    }

    private void clearOfflinePcm() {
        synchronized (mOfflinePcm) { mOfflinePcm.clear(); }
    }

    @Override public void switchLangAndListen() { stopListening(false); invalidateRecognizer(); startListening(); }

    @Override
    public void release() {
        stopListening(false);
        mBg.execute(this::releaseRecognizersLocked);
        mBg.shutdown();
    }

    private void invalidateRecognizer() {
        mBg.execute(() -> {
            releaseRecognizersLocked();
            preloadAsync(getLang(mApp));
        });
    }

    private synchronized void releaseRecognizersLocked() {
        if (mRecognizer != null) {
            try { mRecognizer.release(); } catch (Throwable ignored) {}
            mRecognizer = null;
            mLoadedLang = null;
        }
        if (mOffline != null) {
            try { mOffline.release(); } catch (Throwable ignored) {}
            mOffline = null;
            mLoadedOfflineLang = null;
        }
    }

    private void onListenTimeout() { stopListening(true); }

    private void preloadAsync(String lang) {
        if (!modelAvailable(mApp, lang)) return;
        mBg.execute(() -> {
            try {
                if (LANG_UK.equals(lang)) ensureOfflineLocked(lang);
                else ensureRecognizerLocked(lang);
            } catch (Throwable ignored) {}
        });
    }

    private synchronized void ensureRecognizerLocked(String lang) throws Exception {
        if (mRecognizer != null && lang.equals(mLoadedLang)) return;
        if (mRecognizer != null) { mRecognizer.release(); mRecognizer = null; mLoadedLang = null; }
        File dir = findModelDir(mApp, lang);
        if (dir == null) throw new Exception("No " + lang + " model — flip2 ime sherpa");
        mRecognizer = new OnlineRecognizer(null, buildConfig(dir, lang));
        mLoadedLang = lang;
    }

    /* The multilingual NeMo pack has no streaming variant, so UK goes through the
       batch recognizer: nemo_transducer picks the NeMo offline impl, which reads
       subsampling_factor from the encoder metadata (the field that crashed the
       online loader, since it also wants window_size). */
    private synchronized void ensureOfflineLocked(String lang) throws Exception {
        if (mOffline != null && lang.equals(mLoadedOfflineLang)) return;
        if (mOffline != null) { mOffline.release(); mOffline = null; mLoadedOfflineLang = null; }
        File dir = findModelDir(mApp, lang);
        if (dir == null) throw new Exception("No " + lang + " model — flip2 ime sherpa");
        mOffline = new OfflineRecognizer(null, buildOfflineConfig(dir));
        mLoadedOfflineLang = lang;
        Log.i(TAG, "offline recognizer loaded: " + dir.getAbsolutePath());
    }

    /* Sherpa 2.0.1's Kotlin config constructors take non-null arguments, so build
       them with the no-arg forms + setters. Passing null to the full constructors
       throws before the model is ever loaded. */
    private static OnlineRecognizerConfig buildConfig(File modelDir, String lang) throws Exception {
        String base = modelDir.getAbsolutePath();
        OnlineTransducerModelConfig transducer = new OnlineTransducerModelConfig();
        if (LANG_EN.equals(lang)) {
            transducer.setEncoder(firstExisting(base, "encoder-epoch-99-avg-1.int8.onnx", "encoder-epoch-99-avg-1.onnx"));
            transducer.setDecoder(firstExisting(base, "decoder-epoch-99-avg-1.onnx"));
            transducer.setJoiner(firstExisting(base, "joiner-epoch-99-avg-1.int8.onnx", "joiner-epoch-99-avg-1.onnx"));
        } else {
            transducer.setEncoder(base + "/encoder.int8.onnx");
            transducer.setDecoder(base + "/decoder.int8.onnx");
            transducer.setJoiner(base + "/joiner.int8.onnx");
        }
        OnlineModelConfig modelConfig = new OnlineModelConfig();
        modelConfig.setTransducer(transducer);
        modelConfig.setTokens(base + "/tokens.txt");
        modelConfig.setNumThreads(2);
        modelConfig.setDebug(false);
        modelConfig.setProvider("cpu");
        modelConfig.setModelType("zipformer");

        EndpointConfig ep = new EndpointConfig(
                new EndpointRule(false, 2.4f, 0.0f), new EndpointRule(true, 1.4f, 0.0f),
                new EndpointRule(false, 0.0f, 20.0f));

        OnlineRecognizerConfig config = new OnlineRecognizerConfig();
        config.setFeatConfig(new FeatureConfig(SAMPLE_RATE, 80, 0.0f));
        config.setModelConfig(modelConfig);
        config.setEndpointConfig(ep);
        config.setEnableEndpoint(true);
        config.setDecodingMethod("greedy_search");
        config.setMaxActivePaths(4);
        config.setHotwordsScore(1.5f);
        return config;
    }

    private static OfflineRecognizerConfig buildOfflineConfig(File modelDir) {
        String base = modelDir.getAbsolutePath();
        OfflineTransducerModelConfig transducer = new OfflineTransducerModelConfig();
        transducer.setEncoder(base + "/encoder.int8.onnx");
        transducer.setDecoder(base + "/decoder.int8.onnx");
        transducer.setJoiner(base + "/joiner.int8.onnx");

        OfflineModelConfig modelConfig = new OfflineModelConfig();
        modelConfig.setTransducer(transducer);
        modelConfig.setTokens(base + "/tokens.txt");
        modelConfig.setNumThreads(2);
        modelConfig.setDebug(false);
        modelConfig.setProvider("cpu");
        modelConfig.setModelType("nemo_transducer");

        OfflineRecognizerConfig config = new OfflineRecognizerConfig();
        config.setFeatConfig(new FeatureConfig(SAMPLE_RATE, 80, 0.0f));
        config.setModelConfig(modelConfig);
        config.setDecodingMethod("greedy_search");
        config.setMaxActivePaths(4);
        return config;
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
