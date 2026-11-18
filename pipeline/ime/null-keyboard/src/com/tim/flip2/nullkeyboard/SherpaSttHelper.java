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
    private static final int LISTEN_TIMEOUT_MS = 30000;
    private static final int TIMEOUT_WARN_MS = 5000;
    /** Cap preroll while the Sherpa model loads (~4 s at 16 kHz). */
    private static final int PREROLL_MAX_SAMPLES = SAMPLE_RATE * 4;
    /** Silence on throwaway stream after model load (ONNX cold start). */
    private static final float WARMUP_SECONDS = 0.35f;
    private static final int WARMUP_SAMPLES = (int) (SAMPLE_RATE * WARMUP_SECONDS);
    /** Per-PTT live stream: shorter than load warm-up so speech isn't pushed past early frames. */
    private static final float LIVE_STREAM_WARMUP_SECONDS = 0.12f;
    private static final int LIVE_STREAM_WARMUP_SAMPLES = (int) (SAMPLE_RATE * LIVE_STREAM_WARMUP_SECONDS);
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
    /** Offline commit decode — separate from mBg so the next * PTT is not stuck behind NeMo decode. */
    private final ExecutorService mCommitBg = Executors.newSingleThreadExecutor();
    private final SttEngine.Listener mListener;
    private OnlineRecognizer mRecognizer;
    private String mLoadedLang;
    private OfflineRecognizer mOffline;
    private String mLoadedOfflineLang;
    /** UK only: whole-utterance PCM, drained by {@link #decodeOffline()}. */
    private final List<float[]> mOfflinePcm = Collections.synchronizedList(new ArrayList<float[]>());
    /** PCM captured while the Sherpa model loads; drained when capture starts. */
    private final List<float[]> mPrerollPcm = Collections.synchronizedList(new ArrayList<float[]>());
    /** EN: full utterance for commit-time re-decode (cold streaming onset often clips first syllable). */
    private final List<float[]> mStreamingUtterancePcm = Collections.synchronizedList(new ArrayList<float[]>());
    private volatile boolean mOfflineMode;
    private AudioRecord mAudioRecord;
    private Thread mCaptureThread;
    private Thread mPrerollThread;
    private volatile boolean mPrerollActive;
    private final AtomicBoolean mRecording = new AtomicBoolean(false);
    private volatile boolean mListening;
    private volatile boolean mStarting;
    /** User released * before {@link #beginCapture}; drop late model-load callback. */
    private volatile boolean mAbortStartup;
    /** Set when stopping, so the capture thread flushes its pending streaming text. */
    private volatile boolean mFlushOnStop;
    /** Tail text produced by that flush, handed back to the caller of stopListening(). */
    private volatile String mStreamFinal;
    /** Segments committed at Sherpa endpoints (push-to-talk: one insert on release). */
    private final StringBuilder mStreamSegments = new StringBuilder();
    private final Runnable mTimeout = this::onListenTimeout;
    private final Runnable mTimeoutWarn = this::onListenTimeoutWarn;
    /** Serializes start/stop and prevents concurrent startListening from double-bumping mPttSession. */
    private final Object mPttLock = new Object();

    private int mPttSession;
    /** Posted only for cold offline load — removed on stop so stale runnables cannot abort after UP. */
    private Runnable mPendingBeginCapture;
    private long mListeningSinceUptimeMs;
    private boolean mLoggedFirstPartial;
    /** Blocks new PTT while EN commit runs (slow re-decode caused session overlap in logs). */
    private volatile boolean mCommitInProgress;
    /** Hide lone-letter partials until longer text or grace elapses ("O" @ ~3s = clipped hello). */
    private static final float PARTIAL_ONSET_GRACE_S = 2.5f;

    private static int totalSamples(List<float[]> chunks) {
        if (chunks == null) return 0;
        int n = 0;
        for (float[] c : chunks) if (c != null) n += c.length;
        return n;
    }

    /** Leading silence trim before commit decode (speech after quiet wait aligns at frame 0). */
    private static final float LEADING_SILENCE_THRESHOLD = 0.012f;
    private static final int LEADING_SILENCE_FRAME = (int) (SAMPLE_RATE * 0.02f);
    private static final int LEADING_TRIM_MAX_SAMPLES = (int) (SAMPLE_RATE * 1.8f);

    /**
     * Prefer fuller transcript on long holds; live flush often retains onset when commit decode clips.
     */
    private static String pickEnCommitText(String utterance, String live, float utteranceSec) {
        String u = utterance != null ? utterance.trim() : "";
        String l = live != null ? live.trim() : "";
        if (u.isEmpty()) return l;
        if (l.isEmpty()) return u;
        int uWords = countWords(u);
        int lWords = countWords(l);
        /* Long hold + live has more words → trust live over clipped commit (e.g. "er to night"). */
        if (utteranceSec >= 0.8f && lWords > uWords) {
            return l;
        }
        if (utteranceSec >= 1.2f) {
            if (lWords >= uWords + 1 || l.length() >= u.length() + 3) {
                return l;
            }
            if (uWords >= lWords + 2 && u.length() >= l.length() + 6) {
                return u;
            }
        }
        if (utteranceSec >= 1.0f && u.length() <= 6 && l.length() > u.length() + 2) {
            return l;
        }
        if (utteranceSec >= 2.0f && uWords <= 2 && lWords >= uWords + 1 && l.length() >= u.length() + 2) {
            return l;
        }
        if (l.length() > u.length() + 8 && l.endsWith(u)) {
            return l;
        }
        if (l.length() > u.length() + 5 && u.length() >= 3
                && l.regionMatches(true, l.length() - u.length(), u, 0, u.length())) {
            return l;
        }
        if (utteranceSec >= 1.0f && l.length() > u.length()) {
            return l;
        }
        return u;
    }

    private static String pickLongerTranscript(String a, String b) {
        String x = a != null ? a.trim() : "";
        String y = b != null ? b.trim() : "";
        if (x.isEmpty()) return y;
        if (y.isEmpty()) return x;
        int xw = countWords(x);
        int yw = countWords(y);
        if (yw > xw) return y;
        if (xw > yw) return x;
        return y.length() >= x.length() ? y : x;
    }

    private static int countWords(String s) {
        if (s == null || s.isEmpty()) return 0;
        int n = 0;
        boolean inWord = false;
        for (int i = 0; i < s.length(); i++) {
            if (Character.isLetterOrDigit(s.charAt(i))) {
                if (!inWord) {
                    n++;
                    inWord = true;
                }
            } else {
                inWord = false;
            }
        }
        return n;
    }

    private static float[] concatPcm(List<float[]> chunks) {
        int total = totalSamples(chunks);
        if (total == 0) return new float[0];
        float[] all = new float[total];
        int off = 0;
        for (float[] c : chunks) {
            if (c == null || c.length == 0) continue;
            System.arraycopy(c, 0, all, off, c.length);
            off += c.length;
        }
        return all;
    }

    /** Drop initial quiet frames so zipformer sees speech near t=0 (does not remove speech). */
    private static float[] trimLeadingSilence(float[] pcm) {
        if (pcm == null || pcm.length == 0) return pcm;
        int maxTrim = Math.min(LEADING_TRIM_MAX_SAMPLES, pcm.length);
        int i = 0;
        while (i < maxTrim) {
            int end = Math.min(i + LEADING_SILENCE_FRAME, pcm.length);
            float peak = 0f;
            for (int j = i; j < end; j++) {
                float a = Math.abs(pcm[j]);
                if (a > peak) peak = a;
            }
            if (peak > LEADING_SILENCE_THRESHOLD) break;
            i += LEADING_SILENCE_FRAME;
        }
        if (i == 0) return pcm;
        float[] out = new float[pcm.length - i];
        System.arraycopy(pcm, i, out, 0, out.length);
        Log.i(TAG, "leading trim " + (i / (float) SAMPLE_RATE) + "s");
        return out;
    }

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

    /** Mic active or model loading — not background commit decode (that must not block * down). */
    @Override public boolean isListening() {
        return mListening || mStarting;
    }

    @Override
    public boolean startListening() {
        synchronized (mPttLock) {
            if (mListening || mStarting) {
                Log.i(TAG, "ptt start ignored already active listening=" + mListening + " starting=" + mStarting);
                return true;
            }
            /* Do not block * while offline decode runs — mic/PTT is independent of bg commit. */
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
            clearStreamingUtterancePcm();
            synchronized (mStreamSegments) { mStreamSegments.setLength(0); }
            mAbortStartup = false;
            /* EN and UK both use offline NeMo (batch decode on * release). */
            mOfflineMode = LANG_EN.equals(lang) || LANG_UK.equals(lang);
            mPttSession++;
            mLoggedFirstPartial = false;
            mListeningSinceUptimeMs = 0;
            boolean offlineWarm;
            synchronized (this) {
                offlineWarm = mOffline != null && lang.equals(mLoadedOfflineLang);
            }
            Log.i(TAG, "ptt start session=" + mPttSession + " lang=" + lang + " offline_warm=" + offlineWarm);
            mStarting = true;
            mListener.onPreparing();
            if (!startMicPreroll()) {
                mStarting = false;
                return false;
            }
            final int captureSession = mPttSession;
            final String loadLang = lang;
            mPendingBeginCapture = null;
            if (offlineWarm) {
                beginCapture(captureSession);
            } else {
                final Runnable onMain = () -> beginCapture(captureSession);
                mPendingBeginCapture = onMain;
                mBg.execute(() -> {
                    try {
                        ensureOfflineLocked(loadLang);
                        mMain.post(onMain);
                    } catch (Throwable t) {
                        String err = t.getMessage();
                        if (err == null || err.isEmpty()) err = t.getClass().getSimpleName();
                        final String e = err;
                        mMain.post(() -> {
                            synchronized (mPttLock) {
                                if (captureSession != mPttSession) return;
                                mStarting = false;
                                releaseMic();
                                mListener.onError(e);
                                mListener.onIdle();
                            }
                        });
                    }
                });
            }
            return true;
        }
    }

    /** VOICE_RECOGNITION tuned for STT; MIC fallback if init fails. */
    private static AudioRecord openVoiceRecognitionMic(int bufferBytes) {
        AudioRecord ar = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferBytes);
        if (ar.getState() != AudioRecord.STATE_INITIALIZED) {
            try { ar.release(); } catch (Throwable ignored) {}
            ar = new AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferBytes);
            Log.i(TAG, "AudioRecord fallback MIC");
        } else {
            Log.i(TAG, "AudioRecord VOICE_RECOGNITION");
        }
        return ar;
    }

    /** FGS + mic + preroll thread before model load so early speech is not dropped. */
    private boolean startMicPreroll() {
        try {
            SttForegroundService.start(mApp);
            int minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT);
            int bufferBytes = Math.max(minBuf, 1) * 2;
            mAudioRecord = openVoiceRecognitionMic(bufferBytes);
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

    private void appendUtterancePcm(float[] samples) {
        if (samples == null || samples.length == 0) return;
        mStreamingUtterancePcm.add(samples);
    }

    private List<float[]> drainStreamingUtterancePcm() {
        synchronized (mStreamingUtterancePcm) {
            if (mStreamingUtterancePcm.isEmpty()) return Collections.emptyList();
            List<float[]> out = new ArrayList<>(mStreamingUtterancePcm);
            mStreamingUtterancePcm.clear();
            return out;
        }
    }

    private void clearStreamingUtterancePcm() {
        synchronized (mStreamingUtterancePcm) { mStreamingUtterancePcm.clear(); }
    }

    private void stopPrerollThread() {
        mPrerollActive = false;
        Thread t = mPrerollThread;
        mPrerollThread = null;
        if (t != null) {
            try { t.join(800L); } catch (InterruptedException ignored) {}
        }
    }

    private void beginCapture(int sessionId) {
        if (sessionId != mPttSession) {
            Log.i(TAG, "beginCapture skip stale session=" + sessionId + " current=" + mPttSession);
            return;
        }
        synchronized (mPttLock) {
            if (sessionId != mPttSession) return;
            if (!mStarting || mAbortStartup) {
                if (mAbortStartup) {
                    Log.i(TAG, "beginCapture abort startup session=" + sessionId);
                    mStarting = false;
                    releaseMicDrainPrerollOnly();
                    mListener.onIdle();
                }
                return;
            }
        }
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
            mListeningSinceUptimeMs = android.os.SystemClock.uptimeMillis();
            boolean warm;
            synchronized (this) {
                warm = mOffline != null && getLang(mApp).equals(mLoadedOfflineLang);
            }
            Log.i(TAG, "listening session=" + mPttSession + " offline_warm=" + warm
                    + " preroll_s=" + (prerollSamples / (float) SAMPLE_RATE));
            mListener.onListening();
            armListenTimeouts();
            final List<float[]> pr = preroll;
            mCaptureThread = new Thread(() -> captureOffline(pr), "flip2-sherpa");
            mCaptureThread.start();
        } catch (Throwable t) {
            mStarting = false;
            releaseMic();
            mListener.onError(t.getMessage() != null ? t.getMessage() : t.getClass().getSimpleName());
            mListener.onIdle();
        }
    }

    private static boolean shouldShowLivePartial(String show, long listeningSinceUptimeMs) {
        if (show == null || show.isEmpty()) return false;
        if (listeningSinceUptimeMs <= 0) return true;
        float since = (android.os.SystemClock.uptimeMillis() - listeningSinceUptimeMs) / 1000f;
        if (since >= PARTIAL_ONSET_GRACE_S) return true;
        String t = show.trim();
        if (t.length() >= 8) return true;
        if (t.length() <= 2 && countWords(t) <= 1) return false;
        return true;
    }

    private void postPartial(String show) {
        if (show == null || show.length() == 0) return;
        if (!shouldShowLivePartial(show, mListeningSinceUptimeMs)) return;
        if (!mLoggedFirstPartial) {
            mLoggedFirstPartial = true;
            float since = mListeningSinceUptimeMs > 0
                    ? (android.os.SystemClock.uptimeMillis() - mListeningSinceUptimeMs) / 1000f
                    : -1f;
            Log.i(TAG, "first partial session=" + mPttSession + " since_listening_s=" + since
                    + " [" + show + "]");
        }
        mMain.post(() -> {
            bumpListenActivity();
            mListener.onPartial(show);
        });
    }

    private static String currentResultText(OnlineRecognizer rec, OnlineStream stream) {
        OnlineRecognizerResult result = rec.getResult(stream);
        String text = result != null ? result.getText() : "";
        return text != null ? text : "";
    }

    /** Prime zipformer feature pipeline with silence so first real frames are not lost. */
    private static void warmupOnlineRecognizer(OnlineRecognizer rec) {
        if (rec == null) return;
        OnlineStream s = null;
        try {
            s = rec.createStream("");
            float[] silence = new float[WARMUP_SAMPLES];
            s.acceptWaveform(silence, SAMPLE_RATE);
            while (rec.isReady(s)) rec.decode(s);
            Log.i(TAG, "recognizer warm-up " + WARMUP_SECONDS + "s silence");
        } catch (Throwable t) {
            Log.w(TAG, "recognizer warm-up", t);
        } finally {
            if (s != null) try { s.release(); } catch (Throwable ignored) {}
        }
    }

    private static void warmupOnlineStream(OnlineRecognizer rec, OnlineStream stream) {
        if (rec == null || stream == null) return;
        try {
            float[] silence = new float[WARMUP_SAMPLES];
            stream.acceptWaveform(silence, SAMPLE_RATE);
            while (rec.isReady(stream)) rec.decode(stream);
        } catch (Throwable t) {
            Log.w(TAG, "stream warm-up", t);
        }
    }

    /** Short priming on each PTT live stream — full 0.35s pushes speech and clips word onsets. */
    private static void warmupLivePttStream(OnlineRecognizer rec, OnlineStream stream) {
        if (rec == null || stream == null) return;
        try {
            float[] silence = new float[LIVE_STREAM_WARMUP_SAMPLES];
            stream.acceptWaveform(silence, SAMPLE_RATE);
            while (rec.isReady(stream)) rec.decode(stream);
        } catch (Throwable t) {
            Log.w(TAG, "live stream warm-up", t);
        }
    }

    /** After each EN utterance, keep recognizer warm for the next PTT (cold-stream onset). */
    private void scheduleRecognizerWarmupAfterUtterance() {
        mBg.execute(() -> {
            OnlineRecognizer rec;
            synchronized (this) { rec = mRecognizer; }
            if (rec != null) warmupOnlineRecognizer(rec);
        });
    }

    private void captureStreaming(List<float[]> preroll) {
        OnlineRecognizer rec = mRecognizer;
        if (rec == null) {
            Log.e(TAG, "captureStreaming: recognizer null");
            return;
        }
        OnlineStream stream = rec.createStream("");
        int chunk = (int) (0.1 * SAMPLE_RATE);
        short[] buf = new short[chunk];
        String lastPartial = "";
        try {
            for (float[] pre : preroll) {
                if (pre == null || pre.length == 0) continue;
                appendUtterancePcm(pre);
                stream.acceptWaveform(pre, SAMPLE_RATE);
                while (rec.isReady(stream)) rec.decode(stream);
            }
            while (mRecording.get() && mAudioRecord != null) {
                int n = mAudioRecord.read(buf, 0, buf.length);
                if (n <= 0) continue;
                float[] samples = new float[n];
                for (int i = 0; i < n; i++) samples[i] = buf[i] / 32768.0f;
                appendUtterancePcm(samples);
                stream.acceptWaveform(samples, SAMPLE_RATE);
                while (rec.isReady(stream)) rec.decode(stream);
                String text = currentResultText(rec, stream);
                if (text.length() > 0 && !text.equals(lastPartial)) {
                    lastPartial = text;
                    postPartial(text);
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
                        Log.i(TAG, "stream flush session=" + mPttSession + " [" + text + "]");
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

    private void armListenTimeouts() {
        mMain.removeCallbacks(mTimeout);
        mMain.removeCallbacks(mTimeoutWarn);
        int warnAt = Math.max(0, LISTEN_TIMEOUT_MS - TIMEOUT_WARN_MS);
        if (warnAt > 0) {
            mMain.postDelayed(mTimeoutWarn, warnAt);
        }
        mMain.postDelayed(mTimeout, LISTEN_TIMEOUT_MS);
    }

    private void bumpListenActivity() {
        if (!mListening && !mStarting) return;
        armListenTimeouts();
    }

    private void onListenTimeoutWarn() {
        if (!mListening) return;
        mListener.onListenEnding();
    }

    private void cancelListenTimeouts() {
        mMain.removeCallbacks(mTimeout);
        mMain.removeCallbacks(mTimeoutWarn);
    }

    private void appendStreamSegment(String text) {
        if (text == null || text.length() == 0) return;
        synchronized (mStreamSegments) {
            if (mStreamSegments.length() > 0) mStreamSegments.append(' ');
            mStreamSegments.append(text.trim());
        }
    }

    /** Committed endpoint segments plus the recognizer's current partial. */
    private String streamDisplayText(String currentPartial) {
        synchronized (mStreamSegments) {
            if (mStreamSegments.length() == 0) {
                return currentPartial != null ? currentPartial : "";
            }
            if (currentPartial == null || currentPartial.length() == 0) {
                return mStreamSegments.toString();
            }
            return mStreamSegments + " " + currentPartial;
        }
    }

    private String mergedStreamFinal() {
        synchronized (mStreamSegments) {
            String tail = mStreamFinal;
            if (mStreamSegments.length() == 0) {
                return tail != null ? tail.trim() : "";
            }
            if (tail == null || tail.length() == 0) {
                return mStreamSegments.toString().trim();
            }
            return (mStreamSegments + " " + tail.trim()).trim();
        }
    }

    @Override
    public void stopListening(boolean deliverFinal) {
        cancelListenTimeouts();
        final boolean wasListening;
        final boolean wasStarting;
        final boolean offline;
        final int session;
        final boolean onlyStarting;
        List<float[]> earlyPreroll;
        synchronized (mPttLock) {
            wasListening = mListening;
            wasStarting = mStarting;
            offline = mOfflineMode;
            if (mPendingBeginCapture != null) {
                mMain.removeCallbacks(mPendingBeginCapture);
                mPendingBeginCapture = null;
            }
            if (wasStarting && !wasListening) {
                mAbortStartup = true;
            }
            mStreamFinal = null;
            mFlushOnStop = !offline && deliverFinal && (wasListening || wasStarting);
            mRecording.set(false);
            mListening = false;
            mStarting = false;
            session = mPttSession;
            onlyStarting = wasStarting && !wasListening;
            earlyPreroll = releaseMic();
        }
        if (offline && deliverFinal && wasListening) {
            final int commitSession = session;
            mMain.post(mListener::onProcessing);
            mCommitBg.execute(() -> {
                final String text = decodeOffline();
                mMain.post(() -> {
                    Log.i(TAG, "onFinal session=" + commitSession + " source=OFFLINE"
                            + " [" + (text != null ? text : "") + "]");
                    if (text != null && text.length() > 0) mListener.onFinal(text);
                    mListener.onIdle();
                });
            });
        } else if (offline && deliverFinal && onlyStarting && !earlyPreroll.isEmpty()) {
            final int commitSession = session;
            final List<float[]> pr = earlyPreroll;
            mCommitInProgress = true;
            mMain.post(mListener::onProcessing);
            mCommitBg.execute(() -> {
                String text = null;
                try {
                    text = decodeOfflineFromChunks(pr, commitSession);
                } catch (Throwable t) {
                    Log.e(TAG, "early preroll offline decode session=" + commitSession, t);
                } finally {
                    final String finalText = text;
                    mMain.post(() -> {
                        mCommitInProgress = false;
                        final String source = finalText != null && finalText.length() > 0
                                ? "EARLY_PREROLL_OFFLINE" : "NONE";
                        Log.i(TAG, "onFinal session=" + commitSession + " source=" + source
                                + " [" + (finalText != null ? finalText : "") + "]");
                        if (finalText != null && finalText.length() > 0) mListener.onFinal(finalText);
                        mListener.onIdle();
                    });
                }
            });
        } else {
            clearOfflinePcm();
            clearStreamingUtterancePcm();
            synchronized (mStreamSegments) { mStreamSegments.setLength(0); }
            mListener.onIdle();
        }
    }

    /** Mic off; returns drained preroll PCM (do not clear before drain on commit path). */
    private List<float[]> releaseMic() {
        mRecording.set(false);
        mPrerollActive = false;
        stopPrerollThread();
        List<float[]> preroll = drainPrerollPcm();
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
        return preroll;
    }

    private void releaseMicDrainPrerollOnly() {
        drainPrerollPcm();
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
        SttForegroundService.stop(mApp);
    }

    /** One-shot waveform feed (often worse onset than incremental live capture). */
    private static String decodeWaveformOnce(OnlineRecognizer rec, float[] pcm, int session, String variant) {
        if (rec == null || pcm == null || pcm.length == 0) return null;
        OnlineStream stream = rec.createStream("");
        try {
            stream.acceptWaveform(pcm, SAMPLE_RATE);
            while (rec.isReady(stream)) rec.decode(stream);
            stream.inputFinished();
            while (rec.isReady(stream)) rec.decode(stream);
            OnlineRecognizerResult tail = rec.getResult(stream);
            String text = tail != null ? tail.getText() : null;
            text = text != null ? text.trim() : null;
            Log.i(TAG, "utterance decode session=" + session + " " + variant + " "
                    + (pcm.length / (float) SAMPLE_RATE) + "s -> [" + text + "]");
            return text;
        } catch (Throwable t) {
            Log.e(TAG, "utterance decode session=" + session + " " + variant, t);
            return null;
        } finally {
            try { stream.release(); } catch (Throwable ignored) {}
        }
    }

    /** Commit decode matching live capture: short stream warm-up, then chunk-by-chunk feed. */
    private static String decodeUtteranceChunked(OnlineRecognizer rec, List<float[]> pcmChunks, int session) {
        if (rec == null || pcmChunks == null || pcmChunks.isEmpty()) return null;
        OnlineStream stream = rec.createStream("");
        int total = 0;
        try {
            for (float[] c : pcmChunks) {
                if (c == null || c.length == 0) continue;
                total += c.length;
                stream.acceptWaveform(c, SAMPLE_RATE);
                while (rec.isReady(stream)) rec.decode(stream);
            }
            if (total == 0) return null;
            stream.inputFinished();
            while (rec.isReady(stream)) rec.decode(stream);
            OnlineRecognizerResult tail = rec.getResult(stream);
            String text = tail != null ? tail.getText() : null;
            text = text != null ? text.trim() : null;
            Log.i(TAG, "utterance decode session=" + session + " chunks "
                    + (total / (float) SAMPLE_RATE) + "s -> [" + text + "]");
            return text;
        } catch (Throwable t) {
            Log.e(TAG, "utterance decode session=" + session + " chunks", t);
            return null;
        } finally {
            try { stream.release(); } catch (Throwable ignored) {}
        }
    }

    /**
     * EN commit: chunked re-decode (same recipe as live) vs bulk; pick fuller text.
     */
    private String decodeStreamingUtterance(List<float[]> pcmChunks, int session) {
        OnlineRecognizer rec;
        synchronized (this) { rec = mRecognizer; }
        if (rec == null || pcmChunks == null || pcmChunks.isEmpty()) return null;
        float[] raw = concatPcm(pcmChunks);
        if (raw.length == 0) return null;
        String chunked = decodeUtteranceChunked(rec, pcmChunks, session);
        String bulk = decodeWaveformOnce(rec, raw, session, "bulk");
        return pickLongerTranscript(chunked, bulk);
    }

    /** Drains the offline buffer and runs batch decode on the bg executor. */
    private String decodeOffline() {
        List<float[]> chunks;
        synchronized (mOfflinePcm) {
            chunks = new ArrayList<>(mOfflinePcm);
            mOfflinePcm.clear();
        }
        return decodeOfflineFromChunks(chunks, mPttSession);
    }

    private String decodeOfflineFromChunks(List<float[]> chunks, int session) {
        OfflineRecognizer rec;
        synchronized (this) { rec = mOffline; }
        if (rec == null || chunks == null || chunks.isEmpty()) return null;
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
            Log.i(TAG, "offline decode session=" + session + " "
                    + (total / (float) SAMPLE_RATE) + "s -> [" + text + "]");
            return text;
        } catch (Throwable t) {
            Log.e(TAG, "offline decode session=" + session, t);
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
        mCommitBg.shutdown();
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
                ensureOfflineLocked(lang);
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
        warmupOnlineRecognizer(mRecognizer);
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
        transducer.setEncoder(firstExisting(base, "encoder-epoch-99-avg-1.onnx", "encoder-epoch-99-avg-1.int8.onnx"));
        transducer.setDecoder(firstExisting(base, "decoder-epoch-99-avg-1.onnx"));
        transducer.setJoiner(firstExisting(base, "joiner-epoch-99-avg-1.onnx", "joiner-epoch-99-avg-1.int8.onnx"));
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
        /* Push-to-talk: user releases * to commit — mid-utterance endpoints split/clip text. */
        config.setEnableEndpoint(false);
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
        return new File(dir, "encoder.int8.onnx").isFile();
    }
}
