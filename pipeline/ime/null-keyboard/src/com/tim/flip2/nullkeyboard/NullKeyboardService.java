package com.tim.flip2.nullkeyboard;

import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.provider.Settings;
import android.util.Log;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;

/**
 * Flip2 Null IME: zero-UI keypad keyboard.
 *
 * Letters   : 2-9 T9 predictive (one press per letter, including a repeated digit)
 * Next word : * tap, while a word is in progress, cycles dictionary candidates
 * Space     : 0 commits the word and adds a space; double-0 (quick) inserts ". "
 * Punct.    : 1 multi-tap (.,?!'";:-)() etc.); . ! ? add trailing space in smart mode
 * Smart     : sentence caps + pronoun I (T9 and dictation)
 * Case      : * tap, when no word is in progress, cycles smart -> lower -> UPPER
 * 123 mode  : # always toggles ABC/123 (in 123, * types *)
 * Symbols   : hold # — built-in emoji + special char picker
 * STT       : hold * — offline Vosk (EN/UK); models via {@code flip2 ime models}
 *             while listening: # cycles EN↔UK and restarts; * stops
 * Embeds:     hardware DEL / BACK / HELP; BACK = clear while text, else back-nav.
 */
public class NullKeyboardService extends InputMethodService {

    private static final long TAP_TIMEOUT_MS = 900L;
    /** Hold threshold for * / # — shorter than system key-repeat start (~400–500ms). */
    private static final long HOLD_MS = 380L;

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** Case modes: 0 = smart sentence, 1 = lower, 2 = UPPER. */
    private static final int CASE_SMART = 0;
    private static final int CASE_LOWER = 1;
    private static final int CASE_UPPER = 2;

    private static final char[][] KEY_ROWS = {
            /* 0 */ null,
            /* 1 */ {'.', ',', '?', '!', '\'', '"', '-', ';', ':', '(', ')'},
            /* 2 */ {'a', 'b', 'c'},
            /* 3 */ {'d', 'e', 'f'},
            /* 4 */ {'g', 'h', 'i'},
            /* 5 */ {'j', 'k', 'l'},
            /* 6 */ {'m', 'n', 'o'},
            /* 7 */ {'p', 'q', 'r', 's'},
            /* 8 */ {'t', 'u', 'v'},
            /* 9 */ {'w', 'x', 'y', 'z'},
    };

    private static final String[] SYMBOLS = {
            ".", ",", "?", "!", "'", "\"", "-", "_", ";", ":", "(", ")",
            "@", "/", "&", "%", "+", "=", "<", ">", "[", "]", "{", "}",
            "*", "#", "$", "~", "^", "|", "\\", "§", "°", "•",
    };

    private static final String[] EMOJIS = {
            "😀", "😂", "🙂", "😉", "😍", "😎", "🤔", "😴",
            "😭", "😡", "😱", "🤗", "🥳", "🥺", "😷", "🫡",
            "👍", "👎", "👏", "🙏", "🤝", "💪", "✌️", "🤞",
            "❤️", "🔥", "✅", "❌", "⭐", "🎉", "🎁", "💡",
            "📞", "✉️", "💬", "📸", "🎵", "🔋", "🚗", "☕",
            "🍕", "⚽", "🏠", "❗", "❓", "💤", "🌙", "😊",
    };

    private int mCaseMode = CASE_SMART;
    private boolean mFieldNumeric = false;   // field says digits (inputType)
    private boolean mToggleNumeric = false;  // user # toggle

    // multi-tap state
    private int mPendingKeyCode = -1;
    private int mPendingIndex = 0;
    private long mPendingStart = 0L;
    /** Chars last inserted by key-1 multi-tap (1 or 2 when smart adds space after . ! ?). */
    private int mPunctVisibleLen;
    private final Runnable mPendingTimeout = this::onPendingTimeout;

    private AlertDialog mSymbolDialog;
    private Toast mToast;
    /** Top-of-screen status chip attached to the IME token; system toasts render
     *  at the bottom edge on A11 (setGravity ignored) where the nav band hides them. */
    private android.app.Dialog mNoticeDialog;
    private TextView mNoticeText;
    private final Runnable mNoticeHide = this::hideNotice;
    private VoskSttHelper mStt;

    // Hold state for * / # — defer tap until UP; fire hold once.
    private int mHoldKeyCode = -1;
    private boolean mHoldFired = false;
    private final Runnable mHoldRunnable = this::onHoldTimeout;

    // T9 predictive (keys 2–9): digit sequence + in-field preview; 0 commits word + space.
    private String mT9Seq = "";
    private int mT9CandidateIndex = 0;
    private List<String> mT9Candidates = new ArrayList<>();
    private int mT9PreviewLen = 0;
    /** Smart caps for current T9 word (in-field preview breaks {@link #atSentenceStart}). */
    private boolean mT9SmartCapFirst;

    /** Saved while IME is active so matrix * / # do not spam DTMF (Settings.System). */
    private Integer mSavedDtmfTone;

    /** BACK down handled as delete/T9 trim — swallow matching UP so chat app does not navigate. */
    private boolean mBackConsumedForEdit;

    /** Second 0 within this window turns the prior lone space into ". " */
    private static final long DOUBLE_ZERO_MS = 480L;
    private long mLastZeroDownMs;
    private boolean mAwaitingDoubleZeroPeriod;

    // ---------- lifecycle ----------

    @Override
    public void onCreate() {
        super.onCreate();
        T9PredictiveHelper.loadWords(this);
        mStt = new VoskSttHelper(this, new VoskSttHelper.Listener() {
            @Override
            public void onListening() {
                String lang = VoskSttHelper.getLang(NullKeyboardService.this);
                toast("Listening (" + lang.toUpperCase() + ") — * stop, # lang");
            }

            @Override
            public void onPartial(String text) {
                // Keep quiet on partials — Flip2 toast would spam.
            }

            @Override
            public void onFinal(String text) {
                commitSttText(text);
            }

            @Override
            public void onError(String message) {
                toast(message);
            }

            @Override
            public void onIdle() {
                hideNoticeIfListening();
            }
        });
    }

    @Override
    public void onDestroy() {
        restoreDtmfTone();
        if (mStt != null) {
            mStt.release();
            mStt = null;
        }
        if (mNoticeDialog != null) {
            try {
                mNoticeDialog.dismiss();
            } catch (Throwable ignored) {
            }
            mNoticeDialog = null;
            mNoticeText = null;
        }
        super.onDestroy();
    }

    @Override
    public void onFinishInput() {
        Log.i("Flip2IME", "onFinishInput");
        hideNotice();
        restoreDtmfTone();
        super.onFinishInput();
    }

    @Override
    public void onStartInput(EditorInfo attribute, boolean restarting) {
        super.onStartInput(attribute, restarting);
        Log.i("Flip2IME", "onStartInput restarting=" + restarting + " inputType=0x"
                + Integer.toHexString(attribute.inputType) + " pkg=" + attribute.packageName);
        muteDtmfTone();
        int cls = attribute.inputType & EditorInfo.TYPE_MASK_CLASS;
        mFieldNumeric = cls == EditorInfo.TYPE_CLASS_NUMBER
                || cls == EditorInfo.TYPE_CLASS_PHONE
                || cls == EditorInfo.TYPE_CLASS_DATETIME;
        cancelPending();
        clearT9();
        mAwaitingDoubleZeroPeriod = false;
        mLastZeroDownMs = 0;
        mBackConsumedForEdit = false;
    }

    @Override
    public View onCreateInputView() {
        View v = new View(this) {
            @Override
            protected void onMeasure(int w, int h) {
                setMeasuredDimension(android.view.View.MeasureSpec.getSize(w), 0);
            }

            @Override
            public boolean onKeyPreIme(int keyCode, KeyEvent event) {
                if (keyCode != KeyEvent.KEYCODE_BACK) {
                    return super.onKeyPreIme(keyCode, event);
                }
                InputConnection ic = getCurrentInputConnection();
                if (ic == null) {
                    return super.onKeyPreIme(keyCode, event);
                }
                if (handleHardwareBack(ic, event.getAction())) {
                    return true;
                }
                return super.onKeyPreIme(keyCode, event);
            }
        };
        v.setFocusableInTouchMode(true);
        return v;
    }

    @Override
    public View onCreateCandidatesView() {
        return null;
    }

    @Override
    public View onCreateExtractTextView() {
        return null;
    }

    @Override
    public boolean onEvaluateFullscreenMode() {
        return false;
    }

    @Override
    public void onWindowShown() {
        super.onWindowShown();
        Log.i("Flip2IME", "onWindowShown");
        try {
            android.app.Dialog d = getWindow();
            if (d != null && d.getWindow() != null) {
                Window w = d.getWindow();
                WindowManager.LayoutParams lp = w.getAttributes();
                if (lp.height != 0) {
                    lp.height = 0;
                    w.setAttributes(lp);
                }
            }
        } catch (Throwable ignored) {
        }
    }

    @Override
    public void onWindowHidden() {
        super.onWindowHidden();
        Log.i("Flip2IME", "onWindowHidden");
    }

    @Override
    public void onComputeInsets(Insets outInsets) {
        outInsets.contentTopInsets = 0;
        outInsets.visibleTopInsets = 0;
        outInsets.touchableInsets = Insets.TOUCHABLE_INSETS_CONTENT;
        outInsets.touchableRegion.setEmpty();
    }

    // ---------- key handling ----------

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (forwardKey(keyCode, event)) {
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (forwardKey(keyCode, event)) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    /** true = event consumed (do not pass to activity). */
    private boolean handleHardwareBack(InputConnection ic, int action) {
        Log.i("Flip2IME", "hwBack action=" + action);
        if (action == KeyEvent.ACTION_UP) {
            if (mBackConsumedForEdit) {
                mBackConsumedForEdit = false;
                return true;
            }
            return false;
        }
        cancelPending();
        mAwaitingDoubleZeroPeriod = false;
        if (mSymbolDialog != null && mSymbolDialog.isShowing()) {
            Log.i("Flip2IME", "hwBack dismiss symbol dialog");
            mSymbolDialog.dismiss();
            mBackConsumedForEdit = true;
            return true;
        }
        if (mT9Seq.length() > 0) {
            Log.i("Flip2IME", "hwBack trim t9 len=" + mT9Seq.length());
            clearT9Preview(ic);
            mT9Seq = mT9Seq.substring(0, mT9Seq.length() - 1);
            mT9CandidateIndex = 0;
            if (mT9Seq.length() > 0) {
                if (mT9Seq.length() == 1 && mCaseMode == CASE_SMART) {
                    mT9SmartCapFirst = atSentenceStart(ic);
                }
                mT9Candidates = T9PredictiveHelper.candidatesFor(mT9Seq);
                refreshT9Preview(ic);
            } else {
                mT9Candidates = new ArrayList<>();
            }
            mBackConsumedForEdit = true;
            return true;
        }
        clearT9();
        CharSequence before = ic.getTextBeforeCursor(1, 0);
        if (before != null && before.length() > 0) {
            Log.i("Flip2IME", "hwBack delete char");
            ic.deleteSurroundingText(1, 0);
            mBackConsumedForEdit = true;
            return true;
        }
        mBackConsumedForEdit = false;
        Log.i("Flip2IME", "hwBack pass-through");
        return false;
    }

    private void clearDoubleZeroPeriodState() {
        mAwaitingDoubleZeroPeriod = false;
        mLastZeroDownMs = 0;
    }

    private boolean isDigitKey(int keyCode) {
        return keyCode >= KeyEvent.KEYCODE_0 && keyCode <= KeyEvent.KEYCODE_9;
    }

    private boolean isKeyPadKey(int keyCode) {
        return isDigitKey(keyCode)
                || keyCode == KeyEvent.KEYCODE_STAR
                || keyCode == KeyEvent.KEYCODE_POUND;
    }

    private boolean numericMode() {
        return mFieldNumeric ^ mToggleNumeric;
    }

    private void toast(String msg) {
        Log.i("Flip2IME", "notice msg=" + msg);
        showNotice(msg, msg.startsWith("Listening"));
    }

    /** Top-center chip attached to the IME window token — system toasts render at
     *  the bottom edge on A11 (setGravity ignored) where the nav band hides them.
     *  Sticky (Listening) stays until {@link #hideNoticeIfListening()}; others auto-hide. */
    private void showNotice(String msg, boolean sticky) {
        try {
            if (mNoticeDialog == null) {
                TextView tv = new TextView(this);
                tv.setTextSize(14);
                tv.setTextColor(Color.WHITE);
                tv.setPadding(24, 10, 24, 10);
                GradientDrawable bg = new GradientDrawable();
                bg.setColor(0xE6202024);
                bg.setCornerRadius(20);
                tv.setBackground(bg);
                LinearLayout box = new LinearLayout(this);
                box.setGravity(Gravity.CENTER);
                box.addView(tv);
                android.app.Dialog d = new android.app.Dialog(this);
                Window w = d.getWindow();
                w.setType(WindowManager.LayoutParams.TYPE_APPLICATION_ATTACHED_DIALOG);
                w.setBackgroundDrawable(
                        new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
                android.view.WindowManager.LayoutParams lp = w.getAttributes();
                lp.token = getWindow().getWindow().getDecorView().getWindowToken();
                lp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
                lp.y = (int) (40 * getResources().getDisplayMetrics().density);
                lp.width = WindowManager.LayoutParams.WRAP_CONTENT;
                lp.height = WindowManager.LayoutParams.WRAP_CONTENT;
                lp.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE;
                lp.format = android.graphics.PixelFormat.TRANSLUCENT;
                w.setAttributes(lp);
                d.setContentView(box);
                mNoticeDialog = d;
                mNoticeText = tv;
            }
            mNoticeText.setText(msg);
            if (!mNoticeDialog.isShowing()) {
                mNoticeDialog.show();
            }
            MAIN.removeCallbacks(mNoticeHide);
            if (!sticky) {
                MAIN.postDelayed(mNoticeHide, 3200L);
            }
        } catch (Throwable t) {
            Log.i("Flip2IME", "notice failed", t);
            // Stale token after rebind — drop the chip so the next notice re-creates it.
            if (mNoticeDialog != null) {
                try {
                    mNoticeDialog.dismiss();
                } catch (Throwable ignored) {
                }
                mNoticeDialog = null;
                mNoticeText = null;
            }
            if (mToast == null) {
                mToast = Toast.makeText(this, msg, Toast.LENGTH_LONG);
            }
            mToast.setText(msg);
            mToast.setDuration(Toast.LENGTH_LONG);
            mToast.show();
        }
    }

    private void hideNotice() {
        MAIN.removeCallbacks(mNoticeHide);
        if (mNoticeDialog != null && mNoticeDialog.isShowing()) {
            mNoticeDialog.hide();
        }
    }

    /** STT ended: drop the chip only if it is the sticky Listening one (errors stay visible). */
    private void hideNoticeIfListening() {
        if (mNoticeText != null && mNoticeText.getText() != null
                && mNoticeText.getText().toString().startsWith("Listening")) {
            hideNotice();
        }
    }

    /** Flip2 matrix keypad plays DTMF for * / # while typing; mute for IME session. */
    private void muteDtmfTone() {
        try {
            if (mSavedDtmfTone == null) {
                mSavedDtmfTone = Settings.System.getInt(
                        getContentResolver(), Settings.System.DTMF_TONE_WHEN_DIALING, 1);
            }
            if (mSavedDtmfTone != null && mSavedDtmfTone != 0) {
                Settings.System.putInt(getContentResolver(),
                        Settings.System.DTMF_TONE_WHEN_DIALING, 0);
            }
        } catch (Throwable ignored) {
        }
    }

    private void restoreDtmfTone() {
        try {
            if (mSavedDtmfTone != null) {
                Settings.System.putInt(getContentResolver(),
                        Settings.System.DTMF_TONE_WHEN_DIALING, mSavedDtmfTone);
                mSavedDtmfTone = null;
            }
        } catch (Throwable ignored) {
        }
    }

    private void commitSttText(String text) {
        if (text == null || text.length() == 0) {
            return;
        }
        cancelPending();
        clearT9();
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) {
            return;
        }
        text = formatSttForSmartCommit(ic, text);
        CharSequence before = ic.getTextBeforeCursor(1, 0);
        boolean needSpace = before != null && before.length() > 0
                && !Character.isWhitespace(before.charAt(0))
                && text.charAt(0) != ' ';
        ic.commitText(needSpace ? (" " + text) : text, 1);
    }

    private boolean forwardKey(int keyCode, KeyEvent event) {
        if (event.getRepeatCount() == 0) {
            Log.i("Flip2IME", "forwardKey code=" + keyCode + " action=" + event.getAction()
                    + " scan=" + event.getScanCode());
        }
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) {
            Log.i("Flip2IME", "forwardKey ic=null code=" + keyCode);
            return false;
        }
        final int action = event.getAction();

        if (keyCode == KeyEvent.KEYCODE_BACK) {
            return handleHardwareBack(ic, action);
        }

        // Hardware delete keypad and the stray HELP key.
        if (keyCode == KeyEvent.KEYCODE_DEL || keyCode == KeyEvent.KEYCODE_FORWARD_DEL
                || keyCode == KeyEvent.KEYCODE_HELP) {
            cancelPending();
            if (action == KeyEvent.ACTION_DOWN && mT9Seq.length() > 0) {
                clearT9Preview(ic);
                if (mT9Seq.length() > 0) {
                    mT9Seq = mT9Seq.substring(0, mT9Seq.length() - 1);
                    mT9CandidateIndex = 0;
                    mT9Candidates = T9PredictiveHelper.candidatesFor(mT9Seq);
                    if (mT9Seq.length() > 0) {
                        if (mT9Seq.length() == 1 && mCaseMode == CASE_SMART) {
                            mT9SmartCapFirst = atSentenceStart(ic);
                        }
                        refreshT9Preview(ic);
                    } else {
                        mT9Candidates = new ArrayList<>();
                    }
                }
                return true;
            }
            clearT9();
            if (action == KeyEvent.ACTION_DOWN) {
                CharSequence before = ic.getTextBeforeCursor(1, 0);
                Log.i("Flip2IME", "del before=" + (before == null ? "null" : before.length()));
                if (before != null && before.length() > 0) {
                    ic.deleteSurroundingText(1, 0);
                }
            }
            return true;
        }

        if (!isKeyPadKey(keyCode)) {
            // Non-keypad keys: cancel any pending tap cycle, then native-ish routing.
            if (action == KeyEvent.ACTION_DOWN) {
                cancelPending();
            }
            if (action == KeyEvent.ACTION_DOWN && event.isPrintingKey()) {
                int ch = event.getUnicodeChar(event.getMetaState());
                if (ch != 0) {
                    ic.commitText(String.valueOf((char) ch), 1);
                    return true;
                }
            }
            return ic.sendKeyEvent(event);
        }

        // While STT is listening: * stops; # cycles EN↔UK and restarts.
        if (mStt != null && mStt.isListening()) {
            clearHold();
            if (action == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
                if (keyCode == KeyEvent.KEYCODE_STAR) {
                    mStt.stopListening(true);
                    toast("STT stopped");
                    return true;
                }
                if (keyCode == KeyEvent.KEYCODE_POUND) {
                    String next = VoskSttHelper.cycleLang(this);
                    toast("STT lang: " + next.toUpperCase());
                    mStt.switchLangAndListen();
                    return true;
                }
            }
            // Swallow other keypad while listening so multi-tap doesn't fight mic.
            if (isKeyPadKey(keyCode)) {
                return true;
            }
        }

        // * / #: defer tap until UP; fire hold once via timer (no double-fire).
        if (keyCode == KeyEvent.KEYCODE_STAR || keyCode == KeyEvent.KEYCODE_POUND) {
            return handleStarPound(keyCode, event, ic);
        }

        if (action != KeyEvent.ACTION_DOWN) {
            return true; // keypad acts on down only
        }

        // Swallow leftover key-repeats from other keys.
        if (event.getRepeatCount() > 0) {
            return true;
        }
        if (isDigitKey(keyCode) && numericMode()) {
            char d = (char) ('0' + (keyCode - KeyEvent.KEYCODE_0));
            ic.commitText(String.valueOf(d), 1);
            return true;
        }

        // T9 predictive: 2–9 append digits (including repeats); * cycles candidates.
        if (keyCode >= KeyEvent.KEYCODE_2 && keyCode <= KeyEvent.KEYCODE_9) {
            cancelPending();
            clearDoubleZeroPeriodState();
            boolean consumed = handleT9LetterKey(keyCode, ic);
            return consumed;
        }

        // KEYCODE_1: punct multi-tap; smart mode adds space after . ! ?
        if (keyCode == KeyEvent.KEYCODE_1) {
            clearDoubleZeroPeriodState();
            char[] row = KEY_ROWS[1];
            long now = SystemClock.uptimeMillis();
            if (mPendingKeyCode == keyCode && now - mPendingStart < TAP_TIMEOUT_MS) {
                mPendingIndex = (mPendingIndex + 1) % row.length;
                if (mPunctVisibleLen > 0) {
                    ic.deleteSurroundingText(mPunctVisibleLen, 0);
                }
                mPunctVisibleLen = commitPunctuationChar(ic, row[mPendingIndex]);
            } else {
                cancelPending();
                if (mT9Seq.length() > 0) {
                    commitT9Word(ic, false);
                } else {
                    clearT9();
                }
                mPendingKeyCode = keyCode;
                mPendingIndex = 0;
                mPendingStart = now;
                // Punctuation attaches to the previous word; drop the space a 0-commit left.
                CharSequence before = ic.getTextBeforeCursor(1, 0);
                if (before != null && before.length() == 1 && before.charAt(0) == ' ') {
                    ic.deleteSurroundingText(1, 0);
                }
                mPunctVisibleLen = commitPunctuationChar(ic, row[0]);
            }
            MAIN.removeCallbacks(mPendingTimeout);
            MAIN.postDelayed(mPendingTimeout, TAP_TIMEOUT_MS);
            return true;
        }

        // KEYCODE_0: commit T9 + space; lone/trailing space then second 0 → ". "
        if (keyCode == KeyEvent.KEYCODE_0) {
            cancelPendingWithoutFinalize();
            long now = SystemClock.uptimeMillis();
            if (mT9Seq.length() > 0) {
                commitT9Word(ic, true);
                mLastZeroDownMs = now;
                mAwaitingDoubleZeroPeriod = true;
            } else if (mCaseMode == CASE_SMART
                    && mAwaitingDoubleZeroPeriod
                    && mLastZeroDownMs > 0
                    && now - mLastZeroDownMs < DOUBLE_ZERO_MS
                    && loneSpaceBeforeCursor(ic)
                    && wordCharBeforeSpace(ic)) {
                ic.deleteSurroundingText(1, 0);
                ic.commitText(". ", 1);
                clearDoubleZeroPeriodState();
            } else {
                ic.commitText(" ", 1);
                mLastZeroDownMs = now;
                mAwaitingDoubleZeroPeriod = true;
            }
            return true;
        }
        return true;
    }

    /** Case handling: UPPER == upper; lower == lower; smart == sentence-start heuristic. */
    private char applyCase(int keyCode, InputConnection ic, char c) {
        if (Character.isDigit(c) || c == ' ') {
            return c;
        }
        boolean upper;
        switch (mCaseMode) {
            case CASE_UPPER:
                upper = true;
                break;
            case CASE_LOWER:
                upper = false;
                break;
            default:
                upper = atSentenceStart(ic);
                break;
        }
        return upper ? Character.toUpperCase(c) : Character.toLowerCase(c);
    }

    private boolean atSentenceStart(InputConnection ic) {
        CharSequence before = ic.getTextBeforeCursor(128, 0);
        if (before == null || before.length() == 0) {
            return true;
        }
        int i = before.length() - 1;
        while (i >= 0 && Character.isWhitespace(before.charAt(i))) {
            i--;
        }
        if (i < 0) {
            return true;
        }
        char c = before.charAt(i);
        if (c == '\n') {
            return true;
        }
        if (c == '.' || c == '!' || c == '?') {
            return true;
        }
        if (c == '…' || c == '\u2026') {
            return true;
        }
        if (c == '"' || c == '\'' || c == ')' || c == ']') {
            int j = i - 1;
            while (j >= 0 && Character.isWhitespace(before.charAt(j))) {
                j--;
            }
            if (j >= 0) {
                char p = before.charAt(j);
                return p == '.' || p == '!' || p == '?' || p == '\n';
            }
            return true;
        }
        return false;
    }

    private static boolean isSentenceEndPunct(char c) {
        return c == '.' || c == '!' || c == '?';
    }

    /** One visible char per tap; smart trailing space is added in {@link #onPendingTimeout}. */
    private int commitPunctuationChar(InputConnection ic, char ch) {
        ic.commitText(String.valueOf(ch), 1);
        return 1;
    }

    private void finalizePendingPunctuation() {
        if (mPendingKeyCode != KeyEvent.KEYCODE_1 || mCaseMode != CASE_SMART) {
            return;
        }
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) {
            return;
        }
        char[] row = KEY_ROWS[1];
        if (mPendingIndex < 0 || mPendingIndex >= row.length) {
            return;
        }
        char ch = row[mPendingIndex];
        if (!isSentenceEndPunct(ch)) {
            return;
        }
        CharSequence before = ic.getTextBeforeCursor(4, 0);
        if (before == null || before.length() == 0) {
            ic.commitText(" ", 1);
            return;
        }
        char last = before.charAt(before.length() - 1);
        if (Character.isWhitespace(last)) {
            return;
        }
        if (last != ch) {
            return;
        }
        ic.commitText(" ", 1);
    }

    /** True when cursor is right after a space (double-0 replaces that space only). */
    private boolean loneSpaceBeforeCursor(InputConnection ic) {
        CharSequence before = ic.getTextBeforeCursor(1, 0);
        return before != null && before.length() == 1 && before.charAt(0) == ' ';
    }

    /** True when the char before that lone space is a letter/digit — double-0 → ". " only after words,
     *  not after the smart trailing space a . ! ? already added. At field start (only the space in
     *  the buffer) the old double-0 → ". " behavior is preserved. */
    private boolean wordCharBeforeSpace(InputConnection ic) {
        CharSequence before = ic.getTextBeforeCursor(2, 0);
        if (before == null) {
            return false;
        }
        if (before.length() < 2) {
            return before.length() == 1;
        }
        return Character.isLetterOrDigit(before.charAt(0));
    }

    private String applySmartWordCase(InputConnection ic, String word) {
        if (word == null || word.isEmpty()) {
            return word;
        }
        String lower = word.toLowerCase();
        if ("i".equals(lower)) {
            return "I";
        }
        if (atSentenceStart(ic)) {
            return Character.toUpperCase(lower.charAt(0)) + lower.substring(1);
        }
        return lower;
    }

    /** Smart case for T9 preview/commit using cap decision from word start (preview in buffer). */
    private String applySmartWordCaseT9(String word) {
        if (word == null || word.isEmpty()) {
            return word;
        }
        String lower = word.toLowerCase();
        if ("i".equals(lower)) {
            return "I";
        }
        if (mT9SmartCapFirst) {
            return Character.toUpperCase(lower.charAt(0)) + lower.substring(1);
        }
        return lower;
    }

    private String formatSttForSmartCommit(InputConnection ic, String text) {
        if (text == null || text.length() == 0 || mCaseMode != CASE_SMART) {
            return text;
        }
        StringBuilder out = new StringBuilder(text.length());
        boolean capNext = atSentenceStart(ic);
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (Character.isLetter(c)) {
                if (capNext) {
                    out.append(Character.toUpperCase(c));
                    capNext = false;
                } else if (c == 'i' || c == 'I') {
                    char prev = out.length() > 0 ? out.charAt(out.length() - 1) : ' ';
                    char next = i + 1 < text.length() ? text.charAt(i + 1) : ' ';
                    if (!Character.isLetter(prev) && !Character.isLetter(next)) {
                        out.append('I');
                    } else {
                        out.append(Character.toLowerCase(c));
                    }
                } else {
                    out.append(Character.toLowerCase(c));
                }
            } else {
                out.append(c);
                if (isSentenceEndPunct(c)) {
                    capNext = true;
                } else if (!Character.isWhitespace(c) && c != '\'') {
                    capNext = false;
                }
            }
        }
        return out.toString();
    }

    private void onPendingTimeout() {
        finalizePendingPunctuation();
        mPendingKeyCode = -1;
        mPendingIndex = 0;
        mPunctVisibleLen = 0;
    }

    private void cancelPending() {
        if (mPendingKeyCode == KeyEvent.KEYCODE_1) {
            finalizePendingPunctuation();
        }
        cancelPendingWithoutFinalize();
    }

    /** Drop multi-tap state without smart trailing space (e.g. before inserting space from 0). */
    private void cancelPendingWithoutFinalize() {
        mPendingKeyCode = -1;
        mPendingIndex = 0;
        mPunctVisibleLen = 0;
        MAIN.removeCallbacks(mPendingTimeout);
    }

    private void clearT9Preview(InputConnection ic) {
        if (mT9PreviewLen > 0 && ic != null) {
            ic.deleteSurroundingText(mT9PreviewLen, 0);
            mT9PreviewLen = 0;
        }
    }

    private void clearT9() {
        InputConnection ic = getCurrentInputConnection();
        clearT9Preview(ic);
        mT9Seq = "";
        mT9CandidateIndex = 0;
        mT9Candidates = new ArrayList<>();
    }

    private String applyCaseToWord(InputConnection ic, String word) {
        if (word == null || word.isEmpty()) {
            return word;
        }
        switch (mCaseMode) {
            case CASE_UPPER:
                return word.toUpperCase();
            case CASE_LOWER:
                return word.toLowerCase();
            default:
                if (mT9Seq.length() > 0) {
                    return applySmartWordCaseT9(word);
                }
                return applySmartWordCase(ic, word);
        }
    }

    private void refreshT9Preview(InputConnection ic) {
        clearT9Preview(ic);
        String word = T9PredictiveHelper.pick(mT9Candidates, mT9CandidateIndex);
        if (word == null) {
            word = T9PredictiveHelper.fallbackLetters(mT9Seq);
        }
        if (word == null || word.isEmpty()) {
            return;
        }
        word = applyCaseToWord(ic, word);
        ic.commitText(word, 1);
        mT9PreviewLen = word.length();
    }

    private boolean handleT9LetterKey(int keyCode, InputConnection ic) {
        String digit = T9PredictiveHelper.keyCodeToDigit(keyCode);
        if (digit == null) {
            return true;
        }
        if (mT9Seq.length() == 0 && mCaseMode == CASE_SMART) {
            mT9SmartCapFirst = atSentenceStart(ic);
        }
        mT9Seq = mT9Seq + digit;
        mT9CandidateIndex = 0;
        mT9Candidates = T9PredictiveHelper.candidatesFor(mT9Seq);
        refreshT9Preview(ic);
        int n = mT9Candidates.size();
        if (n > 1) {
            String hint = T9PredictiveHelper.pick(mT9Candidates, 0);
            toast(hint + "  1/" + n + "  — tap * for next word");
        }
        return true;
    }

    /** Commit in-field T9 preview; optional trailing space (0 key). */
    private void commitT9Word(InputConnection ic, boolean addSpace) {
        if (ic == null || mT9Seq.length() == 0) {
            clearT9();
            return;
        }
        clearT9Preview(ic);
        String word = T9PredictiveHelper.pick(mT9Candidates, mT9CandidateIndex);
        if (word == null) {
            word = T9PredictiveHelper.fallbackLetters(mT9Seq);
        }
        if (word != null && word.length() > 0) {
            word = applyCaseToWord(ic, word);
            ic.commitText(addSpace ? (word + " ") : word, 1);
        } else if (addSpace) {
            ic.commitText(" ", 1);
        }
        mT9Seq = "";
        mT9CandidateIndex = 0;
        mT9Candidates = new ArrayList<>();
        mT9PreviewLen = 0;
    }

    /** Defer * / # tap until key-up; one hold action at {@link #HOLD_MS}. Swallow repeats (no DTMF spam). */
    private boolean handleStarPound(int keyCode, KeyEvent event, InputConnection ic) {
        final int action = event.getAction();
        if (action == KeyEvent.ACTION_DOWN) {
            if (event.getRepeatCount() > 0) {
                return true;
            }
            cancelPending();
            if (mHoldKeyCode != keyCode) {
                clearHold();
                mHoldKeyCode = keyCode;
                mHoldFired = false;
                MAIN.postDelayed(mHoldRunnable, HOLD_MS);
            }
            return true;
        }
        if (action == KeyEvent.ACTION_UP) {
            MAIN.removeCallbacks(mHoldRunnable);
            int held = mHoldKeyCode;
            boolean fired = mHoldFired;
            clearHold();
            if (held == keyCode && !fired) {
                applyStarPoundTap(keyCode, ic);
            }
            return true;
        }
        return true;
    }

    private void onHoldTimeout() {
        if (mHoldKeyCode != KeyEvent.KEYCODE_STAR && mHoldKeyCode != KeyEvent.KEYCODE_POUND) {
            return;
        }
        mHoldFired = true;
        fireHoldAction(mHoldKeyCode);
    }

    private void clearHold() {
        MAIN.removeCallbacks(mHoldRunnable);
        mHoldKeyCode = -1;
        mHoldFired = false;
    }

    private void fireHoldAction(int keyCode) {
        if (keyCode == KeyEvent.KEYCODE_STAR) {
            InputConnection ic = getCurrentInputConnection();
            if (ic != null && mT9Seq.length() > 0) {
                commitT9Word(ic, false);
            }
            if (mStt != null) {
                mStt.startListening();
            }
        } else if (keyCode == KeyEvent.KEYCODE_POUND) {
            showSymbolsDialog();
        }
    }

    private void applyStarPoundTap(int keyCode, InputConnection ic) {
        if (keyCode == KeyEvent.KEYCODE_POUND) {
            Log.i("Flip2IME", "poundTap toggle " + mToggleNumeric + " -> " + !mToggleNumeric
                    + " t9len=" + mT9Seq.length() + " fieldNumeric=" + mFieldNumeric);
            clearT9();
            mToggleNumeric = !mToggleNumeric;
            toast(mToggleNumeric ? "123 — digits on keypad" : "ABC — T9 letters");
            return;
        }
        if (numericMode()) {
            ic.commitText("*", 1);
            return;
        }
        if (keyCode == KeyEvent.KEYCODE_STAR && mT9Seq.length() > 0) {
            if (mT9Candidates.isEmpty()) {
                mT9Candidates = T9PredictiveHelper.candidatesFor(mT9Seq);
            }
            if (!mT9Candidates.isEmpty()) {
                mT9CandidateIndex = (mT9CandidateIndex + 1) % mT9Candidates.size();
                refreshT9Preview(ic);
                String word = T9PredictiveHelper.pick(mT9Candidates, mT9CandidateIndex);
                int n = mT9Candidates.size();
                toast(word + "  " + (mT9CandidateIndex + 1) + "/" + n + "  — * again for next");
            } else {
            }
            return;
        }
        if (keyCode == KeyEvent.KEYCODE_STAR) {
            mCaseMode = (mCaseMode + 1) % 3;
            switch (mCaseMode) {
                case CASE_SMART:
                    toast("Case: Smart (sentence caps)");
                    break;
                case CASE_LOWER:
                    toast("Case: lower");
                    break;
                default:
                    toast("Case: UPPER");
                    break;
            }
        }
    }

    // ---------- symbol / emoji picker ----------

    private TextView makeItem(final String text, float textSize, boolean emoji) {
        final TextView tv = new TextView(this);
        tv.setText(text);
        tv.setGravity(Gravity.CENTER);
        tv.setTextSize(textSize);
        if (!emoji) {
            tv.setTypeface(Typeface.MONOSPACE);
        }
        tv.setTextColor(Color.rgb(28, 28, 30));
        tv.setBackgroundResource(android.R.drawable.list_selector_background);
        tv.setClickable(true);
        tv.setFocusable(true);
        tv.setMinHeight(52);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.rgb(245, 245, 245));
        bg.setStroke(1, Color.rgb(190, 190, 195));
        tv.setBackground(bg);
        tv.setOnClickListener(v -> {
            InputConnection ic = getCurrentInputConnection();
            if (ic != null) {
                ic.commitText(text, 1);
            }
            if (mSymbolDialog != null) {
                mSymbolDialog.dismiss();
            }
        });
        return tv;
    }

    private LinearLayout row(TextView[] items) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (View it : items) {
            LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
                    0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
            p.setMargins(2, 2, 2, 2);
            it.setLayoutParams(p);
            row.addView(it);
        }
        return row;
    }

    private void showSymbolsDialog() {
        cancelPending();
        if (mSymbolDialog != null && mSymbolDialog.isShowing()) {
            return;
        }
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(245, 245, 245));

        TextView title = new TextView(this);
        title.setText(("Symbols & emoji"));
        title.setTextSize(15);
        title.setPadding(12, 10, 12, 4);
        title.setTextColor(Color.rgb(28, 28, 30));
        root.addView(title);

        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        int pos = 0;
        TextView[] buf = new TextView[6];
        for (String s : SYMBOLS) {
            buf[pos % 6] = makeItem(s, 14, false);
            pos++;
            if (pos % 6 == 0) {
                grid.addView(row(buf));
            }
        }
        if (pos % 6 != 0) {
            for (int i = pos % 6; i < 6; i++) {
                buf[i] = makeItem(" ", 14, false);
            }
            grid.addView(row(buf));
        }

        for (int e = 0; e < EMOJIS.length; e += 6) {
            TextView[] r = new TextView[6];
            for (int j = 0; j < 6 && e + j < EMOJIS.length; j++) {
                r[j] = makeItem(EMOJIS[e + j], 18, true);
            }
            grid.addView(row(r));
        }

        ScrollView sv = new ScrollView(this);
        sv.addView(grid);
        root.addView(sv);

        AlertDialog.Builder b = new AlertDialog.Builder(this,
                AlertDialog.THEME_DEVICE_DEFAULT_DARK);
        b.setView(root);
        b.setCancelable(true);
        AlertDialog d = b.create();
        mSymbolDialog = d;
        try {
            Window w = d.getWindow();
            // Type 2012 (INPUT_METHOD_DIALOG) is permission-denied on A11 even with the
            // IME token; TYPE_APPLICATION_ATTACHED_DIALOG (1003) is a sub-window that any
            // process may attach to its own parent window token.
            View imeDecor = getWindow().getWindow().getDecorView();
            android.os.IBinder token = imeDecor != null ? imeDecor.getWindowToken() : null;
            Log.i("Flip2IME", "symbolsDialog token=" + (token != null));
            if (token != null) {
                android.view.WindowManager.LayoutParams lp = w.getAttributes();
                lp.type = WindowManager.LayoutParams.TYPE_APPLICATION_ATTACHED_DIALOG;
                lp.token = token;
                w.setAttributes(lp);
            } else {
                w.setType(WindowManager.LayoutParams.TYPE_INPUT_METHOD_DIALOG);
            }
            d.show();
            Log.i("Flip2IME", "symbolsDialog shown");
        } catch (Throwable t) {
            Log.i("Flip2IME", "symbolsDialog failed", t);
            toast(("Symbols"));
        }
    }
}
