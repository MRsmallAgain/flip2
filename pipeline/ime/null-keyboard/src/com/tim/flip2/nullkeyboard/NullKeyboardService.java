package com.tim.flip2.nullkeyboard;

import android.graphics.Color;
import android.inputmethodservice.InputMethodService;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

/** Zero-UI IME for Flip2: hardware keys forwarded to the focused field, no visible keyboard. */
public class NullKeyboardService extends InputMethodService {

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
    public void onStartInput(EditorInfo attribute, boolean restarting) {
        super.onStartInput(attribute, restarting);
        setExtractViewShown(false);
        setCandidatesViewShown(false);
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

    private boolean forwardKey(int keyCode, KeyEvent event) {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) {
            return false;
        }
        // Hardware delete keypad and BACK both mean "clear" on a flip phone:
        // delete while there is text, otherwise let BACK fall through (hides IME,
        // next press navigates back natively).
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                CharSequence before = ic.getTextBeforeCursor(1, 0);
                if (before != null && before.length() > 0) {
                    ic.deleteSurroundingText(1, 0);
                    return true;
                }
            }
            return false;
        }
        // TCL Flip2 keypad has no KEY_BACKSPACE; the physical backspace key emits KEY_HELP.
        if (keyCode == KeyEvent.KEYCODE_DEL || keyCode == KeyEvent.KEYCODE_FORWARD_DEL
                || keyCode == KeyEvent.KEYCODE_HELP) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                CharSequence before = ic.getTextBeforeCursor(1, 0);
                if (before != null && before.length() > 0) {
                    ic.deleteSurroundingText(1, 0);
                }
            }
            return true;
        }
        if (event.getAction() == KeyEvent.ACTION_DOWN && event.isPrintingKey()) {
            int ch = event.getUnicodeChar(event.getMetaState());
            if (ch != 0) {
                ic.commitText(String.valueOf((char) ch), 1);
                return true;
            }
        }
        return ic.sendKeyEvent(event);
    }
}
