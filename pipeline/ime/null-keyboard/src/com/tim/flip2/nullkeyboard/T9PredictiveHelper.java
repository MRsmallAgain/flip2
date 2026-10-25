package com.tim.flip2.nullkeyboard;

import android.content.Context;
import android.view.KeyEvent;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Classic T9: one press per letter (2–9); dictionary ranks completions for the digit sequence.
 */
final class T9PredictiveHelper {

    private static final String[][] LETTERS = {
            null, null,
            {"a", "b", "c"},
            {"d", "e", "f"},
            {"g", "h", "i"},
            {"j", "k", "l"},
            {"m", "n", "o"},
            {"p", "q", "r", "s"},
            {"t", "u", "v"},
            {"w", "x", "y", "z"},
    };

    private static final Map<String, Integer> FREQ = new HashMap<>();
    private static final Map<String, List<String>> BY_SEQ = new HashMap<>();
    private static volatile boolean sLoaded;

    private T9PredictiveHelper() {
    }

    /** Load frequency-ordered words from {@code res/raw/en_words.txt} (once). */
    static void loadWords(Context context) {
        if (sLoaded || context == null) {
            return;
        }
        synchronized (T9PredictiveHelper.class) {
            if (sLoaded) {
                return;
            }
            try {
                int id = context.getResources().getIdentifier("en_words", "raw", context.getPackageName());
                if (id == 0) {
                    indexBuiltinFallback();
                    sLoaded = true;
                    return;
                }
                InputStream in = context.getResources().openRawResource(id);
                BufferedReader br = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8));
                String line;
                int rank = 0;
                while ((line = br.readLine()) != null) {
                    String w = line.trim().toLowerCase();
                    if (w.isEmpty() || !w.matches("[a-z]+")) {
                        continue;
                    }
                    if (!FREQ.containsKey(w)) {
                        FREQ.put(w, rank++);
                        indexWord(w);
                    }
                }
                br.close();
                sortAllBySeq();
            } catch (Throwable ignored) {
                indexBuiltinFallback();
            }
            sLoaded = true;
        }
    }

    private static void indexWord(String w) {
        String seq = encodeWord(w);
        if (seq == null) {
            return;
        }
        List<String> list = BY_SEQ.get(seq);
        if (list == null) {
            list = new ArrayList<>();
            BY_SEQ.put(seq, list);
        }
        if (!list.contains(w)) {
            list.add(w);
        }
    }

    private static void indexBuiltinFallback() {
        String[] words = {
                "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
                "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
                "hello", "thanks", "please", "yes", "ok", "call", "good", "home", "food", "cool",
        };
        for (int i = 0; i < words.length; i++) {
            String w = words[i];
            FREQ.put(w, i);
            indexWord(w);
        }
        sortAllBySeq();
    }

    private static void sortAllBySeq() {
        for (List<String> list : BY_SEQ.values()) {
            Collections.sort(list, freqComparator());
        }
    }

    private static Comparator<String> freqComparator() {
        return new Comparator<String>() {
            @Override
            public int compare(String a, String b) {
                int ra = FREQ.containsKey(a) ? FREQ.get(a) : 9999;
                int rb = FREQ.containsKey(b) ? FREQ.get(b) : 9999;
                if (ra != rb) {
                    return ra - rb;
                }
                return a.compareTo(b);
            }
        };
    }

    static String keyCodeToDigit(int keyCode) {
        if (keyCode >= KeyEvent.KEYCODE_2 && keyCode <= KeyEvent.KEYCODE_9) {
            return String.valueOf((char) ('0' + (keyCode - KeyEvent.KEYCODE_0)));
        }
        return null;
    }

    static String encodeWord(String word) {
        if (word == null || word.isEmpty()) {
            return null;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < word.length(); i++) {
            char c = Character.toLowerCase(word.charAt(i));
            if (c < 'a' || c > 'z') {
                return null;
            }
            int digit = letterToDigit(c);
            if (digit < 0) {
                return null;
            }
            sb.append(digit);
        }
        return sb.toString();
    }

    private static int letterToDigit(char c) {
        for (int d = 2; d <= 9; d++) {
            for (String s : LETTERS[d]) {
                if (s.charAt(0) == c) {
                    return d;
                }
            }
        }
        return -1;
    }

    static List<String> candidatesFor(String seq) {
        if (seq == null || seq.length() == 0) {
            return Collections.emptyList();
        }
        List<String> exact = BY_SEQ.get(seq);
        if (exact != null && !exact.isEmpty()) {
            return new ArrayList<>(exact);
        }
        List<String> out = new ArrayList<>();
        for (Map.Entry<String, List<String>> e : BY_SEQ.entrySet()) {
            if (e.getKey().startsWith(seq)) {
                out.addAll(e.getValue());
            }
        }
        Collections.sort(out, new Comparator<String>() {
            @Override
            public int compare(String a, String b) {
                int ra = FREQ.containsKey(a) ? FREQ.get(a) : 9999;
                int rb = FREQ.containsKey(b) ? FREQ.get(b) : 9999;
                if (ra != rb) {
                    return ra - rb;
                }
                int la = encodeWord(a).length();
                int lb = encodeWord(b).length();
                if (la != lb) {
                    return la - lb;
                }
                return a.compareTo(b);
            }
        });
        List<String> deduped = new ArrayList<>();
        for (String w : out) {
            if (!deduped.contains(w)) {
                deduped.add(w);
            }
        }
        return deduped.size() > 12 ? deduped.subList(0, 12) : deduped;
    }

    static String pick(List<String> candidates, int index) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        int i = index % candidates.size();
        if (i < 0) {
            i += candidates.size();
        }
        return candidates.get(i);
    }

    /** Fallback when no dict match: first letter of each key in the sequence. */
    static String fallbackLetters(String seq) {
        if (seq == null || seq.length() == 0) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < seq.length(); i++) {
            char last = seq.charAt(i);
            int d = last - '0';
            if (d < 2 || d > 9) {
                continue;
            }
            sb.append(LETTERS[d][0].charAt(0));
        }
        return sb.toString();
    }
}
