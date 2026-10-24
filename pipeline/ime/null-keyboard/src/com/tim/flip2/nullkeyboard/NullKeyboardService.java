package com.tim.flip2.nullkeyboard;

import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.UserHandle;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;

/**
 * Flip2 Null IME: zero-UI keypad keyboard.
 *
 * Letters   : 2-9 multi-tap (tap cycles a/b/c; committing replaces with next cycle)
 * Space     : 0 (each press)
 * Punct.    : 1 multi-tap (.,?!'";:-)() etc.)
 * Case      : * tap cycles smart(sentence) -> lower -> UPPER
 * 123 mode  : # toggle (digits raw; * types *, # types #)
 * Symbols   : hold # (in either mode) — built-in emoji + special char picker
 * Embeds:     hardware DEL / BACK / deleted keypad HELP key all handled; BACK
 *             = clear while text, back-nav when empty (v1.9 behavior).
 *
 * Holds reserved: hold * = STT hookpoint (engine TBD; ROM ships no recognizer).
 */
public class NullKeyboardService extends InputMethodService {

    private static final long TAP_TIMEOUT_MS = 900L;

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
    private final Runnable mPendingTimeout = this::onPendingTimeout;

    private AlertDialog mSymbolDialog;
    private Toast mToast;

    // ---------- lifecycle ----------

    @Override
    public void onStartInput(EditorInfo attribute, boolean restarting) {
        super.onStartInput(attribute, restarting);
        int cls = attribute.inputType & EditorInfo.TYPE_MASK_CLASS;
        mFieldNumeric = cls == EditorInfo.TYPE_CLASS_NUMBER
                || cls == EditorInfo.TYPE_CLASS_PHONE
                || cls == EditorInfo.TYPE_CLASS_DATETIME;
        cancelPending();
    }

    @Override
    public View onCreateInputView() {
        // Zero measured height: the framework's show animation must settle at 0, otherwise
        // the IME window reserves real pixels (apps cache the height as keyboard height).
        View v = new View(this) {
            @Override
            protected void onMeasure(int w, int h) {
                setMeasuredDimension(android.view.View.MeasureSpec.getSize(w), 0);
            }
        };
        v.setBackgroundColor(Color.TRANSPARENT);
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
        // Pin the IME window to zero height — the default IMS decorations measure ~54px
        // even with a zero-height input view, which apps cache as "keyboard height".
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
        if (mToast == null) {
            mToast = Toast.makeText(this, msg, Toast.LENGTH_SHORT);
        }
        mToast.setText(msg);
        mToast.show();
    }

    private boolean forwardKey(int keyCode, KeyEvent event) {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) {
            return false;
        }
        final int action = event.getAction();

        // Back = clear while text, else fall through (hides IME / navigates back).
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            cancelPending();
            if (action == KeyEvent.ACTION_DOWN) {
                CharSequence before = ic.getTextBeforeCursor(1, 0);
                if (before != null && before.length() > 0) {
                    ic.deleteSurroundingText(1, 0);
                    return true;
                }
            }
            return false;
        }

        // Hardware delete keypad and the stray HELP key.
        if (keyCode == KeyEvent.KEYCODE_DEL || keyCode == KeyEvent.KEYCODE_FORWARD_DEL
                || keyCode == KeyEvent.KEYCODE_HELP) {
            cancelPending();
            if (action == KeyEvent.ACTION_DOWN) {
                CharSequence before = ic.getTextBeforeCursor(1, 0);
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

        // Held-key release fallback: long taps open the picker even without
        // repeat events from the injection path (real holds get repeats too).
        if (keyCode == KeyEvent.KEYCODE_POUND || keyCode == KeyEvent.KEYCODE_STAR) {
            if (action == KeyEvent.ACTION_UP && event.getRepeatCount() == 0
                    && event.getEventTime() - event.getDownTime() >= 400L
                    && (mSymbolDialog == null || !mSymbolDialog.isShowing())) {
                showSymbolsDialog();
                return true;
            }
        }

        if (action != KeyEvent.ACTION_DOWN) {
            return true; // keypad acts on down only
        }

        if (event.getRepeatCount() > 0) {
            // Held # → symbol/emoji picker; held * reserved for STT (fallback: picker).
            boolean heldSharp = keyCode == KeyEvent.KEYCODE_POUND;
            boolean heldStar = keyCode == KeyEvent.KEYCODE_STAR;
            if (event.getRepeatCount() == 2 && (heldSharp || heldStar)
                    && (mSymbolDialog == null || !mSymbolDialog.isShowing())) {
                showSymbolsDialog();
            }
            return true;
        }

        // '1'..9 letters / # star meta handled here.
        if (keyCode == KeyEvent.KEYCODE_STAR) {
            if (numericMode()) {
                ic.commitText("*", 1);
                return true;
            }
            mCaseMode = (mCaseMode + 1) % 3;
            return true;
        }
        if (keyCode == KeyEvent.KEYCODE_POUND) {
            if (event.isShiftPressed()) {
                // never; toggle below
            }
            mToggleNumeric = !mToggleNumeric;
            return true;
        }
        if (isDigitKey(keyCode) && numericMode()) {
            char d = (char) ('0' + (keyCode - KeyEvent.KEYCODE_0));
            ic.commitText(String.valueOf(d), 1);
            return true;
        }

        // Letters/punct multi-tap.
        char[] row = keyCode == KeyEvent.KEYCODE_0 ? null : KEY_ROWS[keyCode - KeyEvent.KEYCODE_0];
        long now = SystemClock.uptimeMillis();
        if (row != null) {
            if (mPendingKeyCode == keyCode && now - mPendingStart < TAP_TIMEOUT_MS) {
                mPendingIndex = (mPendingIndex + 1) % row.length;
                if (mPendingIndex == 0) {
                    // cycled past the end — keep it as a fresh letter (a,b,c,a,...)
                }
                ic.deleteSurroundingText(1, 0);
                ic.commitText(String.valueOf(applyCase(keyCode, ic, row[mPendingIndex])), 1);
            } else {
                cancelPending();
                mPendingKeyCode = keyCode;
                mPendingIndex = 0;
                mPendingStart = now;
                ic.commitText(String.valueOf(applyCase(keyCode, ic, row[0])), 1);
            }
            MAIN.removeCallbacks(mPendingTimeout);
            MAIN.postDelayed(mPendingTimeout, TAP_TIMEOUT_MS);
            return true;
        }

        // KEYCODE_0: space (each press), also resets pending.
        cancelPending();
        ic.commitText(" ", 1);
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
        CharSequence before = ic.getTextBeforeCursor(2, 0);
        if (before == null || before.length() == 0) {
            return true;
        }
        int n = before.length();
        char last = before.charAt(n - 1);
        if (last != ' ' && last != '\n') {
            return false;
        }
        for (int i = n - 2; i >= 0; i--) {
            char c = before.charAt(i);
            if (c == ' ' || c == '\t') {
                continue;
            }
            return c == '.' || c == '!' || c == '?' || c == ':' || c == '\n';
        }
        return true;
    }

    private void onPendingTimeout() {
        mPendingKeyCode = -1;
        mPendingIndex = 0;
    }

    private void cancelPending() {
        mPendingKeyCode = -1;
        mPendingIndex = 0;
        MAIN.removeCallbacks(mPendingTimeout);
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
            if (w != null) {
                w.setType(WindowManager.LayoutParams.TYPE_INPUT_METHOD_DIALOG);
            }
            d.show();
        } catch (Throwable t) {
            toast(("Symbols"));
        }
    }
}
