package com.tim.flip2.nullkeyboard;

/**
 * Common surface of the offline STT engines (Vosk streaming, Whisper batch).
 * The service picks one at construction: Whisper when a ggml model is present
 * and the JNI lib loaded, Vosk otherwise. Both engines read the same
 * {@code stt_lang} preference, so language cycling works across either.
 */
interface SttEngine {

    interface Listener {
        void onListening();

        void onPartial(String text);

        void onFinal(String text);

        void onError(String message);

        void onIdle();
    }

    boolean isListening();

    boolean startListening();

    void stopListening(boolean deliverFinal);

    void switchLangAndListen();

    void release();
}
