package com.tim.flip2.nullkeyboard;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import android.Manifest;

import org.json.JSONObject;
import org.vosk.LibVosk;
import org.vosk.LogLevel;
import org.vosk.Model;
import org.vosk.Recognizer;
import org.vosk.android.RecognitionListener;
import org.vosk.android.SpeechService;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Offline STT via Vosk. Models live outside the APK under
 * app filesDir/vosk/{en,uk}/ (pushed by {@code flip2 ime models}).
 * Language preference: SharedPreferences key {@code stt_lang} = "en"|"uk".
 *
 * Model construction is heavy (~seconds) — always done off the main thread.
 */
final class VoskSttHelper {

    static final String LANG_EN = "en";
    static final String LANG_UK = "uk";

    private static final String PREFS = "flip2_null_ime";
    private static final String KEY_LANG = "stt_lang";
    private static final float SAMPLE_RATE = 16000.0f;
    private static final int LISTEN_TIMEOUT_MS = 12000;

    /**
     * Extra roots after app-private files. /data/local/flip2/vosk is often
     * SELinux-blocked (system_data_file) for the IME uid.
     */
    private static final String[] MODEL_ROOTS_EXTRA = {
            "/sdcard/Android/data/com.tim.flip2.nullkeyboard/files/vosk",
            "/data/local/flip2/vosk",
    };

    interface Listener {
        void onListening();
        void onPartial(String text);
        void onFinal(String text);
        void onError(String message);
        void onIdle();
    }

    private final Context mApp;
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private final ExecutorService mBg = Executors.newSingleThreadExecutor();
    private final Listener mListener;

    private Model mModel;
    private String mLoadedLang;
    private SpeechService mSpeech;
    private Recognizer mRecognizer;
    /** Bumped on every listen start and stop; stale Vosk callbacks from an ended listen are dropped. */
    private int mListenGen;
    private boolean mListening;
    private boolean mStarting;
    /** Text already delivered via onResult this listen — skip duplicate in onFinalResult. */
    private String mCommittedThisListen;
    private final Runnable mTimeout = this::onListenTimeout;

    VoskSttHelper(Context context, Listener listener) {
        mApp = context.getApplicationContext();
        mListener = listener;
        try {
            LibVosk.setLogLevel(LogLevel.WARNINGS);
        } catch (Throwable ignored) {
        }
        // Warm the current language model in the background so first hold-*
        // does not stall the IME input path.
        preloadAsync(getLang(mApp));
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

    boolean hasMicPermission() {
        return mApp.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED;
    }

    boolean isListening() {
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

    boolean startListening() {
        if (mListening || mStarting) {
            return true;
        }
        if (!hasMicPermission()) {
            mListener.onError("Mic permission — run: flip2 ime models");
            return false;
        }
        final String lang = getLang(mApp);
        mListenGen++;
        mStarting = true;
        mListener.onListening(); // toast immediately; model may still be loading
        mBg.execute(() -> {
            try {
                ensureModelLocked(lang);
                mMain.post(() -> beginMicAfterModel(lang));
            } catch (Throwable t) {
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
        });
        return true;
    }

    private void beginMicAfterModel(String lang) {
        if (!mStarting) {
            // Cancelled while loading
            return;
        }
        final int gen = mListenGen;
        try {
            if (mModel == null || !lang.equals(mLoadedLang)) {
                throw new Exception("No " + lang + " model — flip2 ime models");
            }
            mCommittedThisListen = null;
            Recognizer rec = new Recognizer(mModel, SAMPLE_RATE);
            mRecognizer = rec;
            mSpeech = new SpeechService(rec, SAMPLE_RATE);
            boolean ok = mSpeech.startListening(new RecognitionListener() {
                @Override
                public void onPartialResult(String hypothesis) {
                    String t = extractJson(hypothesis, "partial");
                    if (t != null && t.length() > 0) {
                        mMain.post(() -> mListener.onPartial(t));
                    }
                }

                @Override
                public void onResult(String hypothesis) {
                    String t = extractJson(hypothesis, "text");
                    if (t != null && t.length() > 0) {
                        mMain.post(() -> {
                            if (gen == mListenGen) {
                                commitAndContinue(t);
                            }
                        });
                    }
                }

                @Override
                public void onFinalResult(String hypothesis) {
                    String t = extractJson(hypothesis, "text");
                    mMain.post(() -> {
                        if (gen == mListenGen) {
                            finishWithText(t);
                        }
                    });
                }

                @Override
                public void onError(Exception e) {
                    String msg = e != null ? e.getMessage() : "STT error";
                    mMain.post(() -> {
                        stopListening(false);
                        mListener.onError(msg != null ? msg : "STT error");
                        mListener.onIdle();
                    });
                }

                @Override
                public void onTimeout() {
                    mMain.post(() -> stopListening(true));
                }
            }, LISTEN_TIMEOUT_MS);
            if (!ok) {
                shutdownSpeech();
                mStarting = false;
                mListener.onError("Mic busy");
                mListener.onIdle();
                return;
            }
            mStarting = false;
            mListening = true;
            mMain.removeCallbacks(mTimeout);
            mMain.postDelayed(mTimeout, LISTEN_TIMEOUT_MS + 500L);
        } catch (Throwable t) {
            shutdownSpeech();
            mStarting = false;
            String msg = t.getMessage();
            if (msg == null || msg.length() == 0) {
                msg = t.getClass().getSimpleName();
            }
            mListener.onError(msg);
            mListener.onIdle();
        }
    }

    void stopListening(boolean deliverFinal) {
        mMain.removeCallbacks(mTimeout);
        // Kill any Vosk callbacks still queued from this listen.
        mListenGen++;
        mStarting = false;
        if (!mListening && mSpeech == null) {
            mListener.onIdle();
            return;
        }
        mListening = false;
        SpeechService svc = mSpeech;
        mSpeech = null;
        Recognizer rec = mRecognizer;
        mRecognizer = null;
        String finalText = null;
        if (svc != null) {
            try {
                if (deliverFinal) {
                    // stop() only interrupts the reader thread — onFinalResult never
                    // fires afterwards; harvest the pending hypothesis directly.
                    svc.stop();
                    if (rec != null) {
                        finalText = extractJson(rec.getFinalResult(), "text");
                    }
                } else {
                    svc.cancel();
                }
            } catch (Throwable ignored) {
            }
            try {
                svc.shutdown();
            } catch (Throwable ignored) {
            }
        }
        closeRecognizer(rec);
        boolean dup = mCommittedThisListen != null
                && (finalText == null || finalText.equals(mCommittedThisListen));
        mCommittedThisListen = null;
        if (deliverFinal && finalText != null && finalText.length() > 0 && !dup) {
            mListener.onFinal(finalText);
        }
        mListener.onIdle();
    }

    private void closeRecognizer(Recognizer rec) {
        if (rec != null) {
            try {
                rec.close();
            } catch (Throwable ignored) {
            }
        }
    }

    void release() {
        stopListening(false);
        mBg.execute(() -> {
            synchronized (VoskSttHelper.this) {
                if (mModel != null) {
                    try {
                        mModel.close();
                    } catch (Throwable ignored) {
                    }
                    mModel = null;
                    mLoadedLang = null;
                }
            }
        });
        mBg.shutdown();
    }

    /** Drop cached model so next listen reloads after lang change. */
    void invalidateModel() {
        stopListening(false);
        mBg.execute(() -> {
            synchronized (VoskSttHelper.this) {
                if (mModel != null) {
                    try {
                        mModel.close();
                    } catch (Throwable ignored) {
                    }
                    mModel = null;
                    mLoadedLang = null;
                }
            }
            preloadAsync(getLang(mApp));
        });
    }

    /** After lang change while listening: load new model then start mic (no race with invalidateModel). */
    void switchLangAndListen() {
        stopListening(false);
        final String lang = getLang(mApp);
        mStarting = true;
        mListener.onListening();
        mBg.execute(() -> {
            try {
                ensureModelLocked(lang);
                mMain.post(() -> beginMicAfterModel(lang));
            } catch (Throwable t) {
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
        });
    }

    private void preloadAsync(String lang) {
        mBg.execute(() -> {
            try {
                ensureModelLocked(lang);
            } catch (Throwable ignored) {
                // First hold-* will surface the error.
            }
        });
    }

    private void onListenTimeout() {
        stopListening(true);
    }

    private void commitAndContinue(String text) {
        if (text == null || text.length() == 0) {
            return;
        }
        mCommittedThisListen = text;
        mListener.onFinal(text);
        mMain.removeCallbacks(mTimeout);
        if (mListening) {
            mMain.postDelayed(mTimeout, LISTEN_TIMEOUT_MS);
        }
    }

    private void finishWithText(String text) {
        mListening = false;
        mStarting = false;
        mMain.removeCallbacks(mTimeout);
        shutdownSpeech();
        if (text != null && text.length() > 0) {
            if (mCommittedThisListen == null || !text.equals(mCommittedThisListen)) {
                mListener.onFinal(text);
            }
        }
        mCommittedThisListen = null;
        mListener.onIdle();
    }

    private void shutdownSpeech() {
        SpeechService svc = mSpeech;
        mSpeech = null;
        Recognizer rec = mRecognizer;
        mRecognizer = null;
        if (svc != null) {
            try {
                svc.cancel();
            } catch (Throwable ignored) {
            }
            try {
                svc.shutdown();
            } catch (Throwable ignored) {
            }
        }
        closeRecognizer(rec);
    }

    /** Must run on {@link #mBg}. */
    private synchronized void ensureModelLocked(String lang) throws Exception {
        if (mModel != null && lang.equals(mLoadedLang)) {
            return;
        }
        if (mModel != null) {
            try {
                mModel.close();
            } catch (Throwable ignored) {
            }
            mModel = null;
            mLoadedLang = null;
        }
        File dir = findModelDir(lang);
        if (dir == null) {
            throw new Exception("No " + lang + " model — flip2 ime models");
        }
        mModel = new Model(dir.getAbsolutePath());
        mLoadedLang = lang;
    }

    private File findModelDir(String lang) {
        File local = new File(mApp.getFilesDir(), "vosk/" + lang);
        if (looksLikeModel(local)) {
            return local;
        }
        for (String root : MODEL_ROOTS_EXTRA) {
            File dir = new File(root, lang);
            if (looksLikeModel(dir)) {
                return dir;
            }
        }
        return null;
    }

    private static boolean looksLikeModel(File dir) {
        if (dir == null || !dir.isDirectory()) {
            return false;
        }
        return new File(dir, "am").isDirectory()
                || new File(dir, "conf").isDirectory()
                || new File(dir, "graph").isDirectory();
    }

    private static String extractJson(String hypothesis, String key) {
        if (hypothesis == null || hypothesis.length() == 0) {
            return null;
        }
        try {
            JSONObject o = new JSONObject(hypothesis);
            String t = o.optString(key, "");
            return t.trim();
        } catch (Throwable t) {
            String s = hypothesis.trim();
            return s.length() > 0 ? s : null;
        }
    }
}
