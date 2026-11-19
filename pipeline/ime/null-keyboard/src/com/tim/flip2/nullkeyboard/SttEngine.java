package com.tim.flip2.nullkeyboard;

/**
 * Common surface of the offline STT engines (Vosk streaming, Whisper batch).
 * The service picks one at construction: Whisper when a ggml model is present
 * and the JNI lib loaded, Vosk otherwise. Both engines read the same
 * {@code stt_lang} preference, so language cycling works across either.
 */
interface SttEngine {

    interface Listener {
        /** Mic preroll / model load — not yet decoding. */
        void onPreparing();

        /** Capture and recognizer are active. */
        void onListening();

        void onPartial(String text);

        /** Mic off or decode running before {@link #onFinal} (release * → commit). */
        void onProcessing();

        void onFinal(String text);

        void onError(String message);

        /** Session hit max listen time; about to stop and commit. */
        void onListenEnding();

        void onIdle();
    }

    boolean isListening();

    boolean startListening();

    void stopListening(boolean deliverFinal);

    void switchLangAndListen();

    /** Background NeMo load so first * in chat is not a multi-second cold start. */
    void warmOfflineInBackground(String lang);

    void release();
}
