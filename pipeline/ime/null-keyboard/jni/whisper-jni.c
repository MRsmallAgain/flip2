/* Minimal JNI bridge between WhisperSttHelper.java and libwhisper.so
 * (whisper.cpp v1.5.5, cross-compiled for armeabi-v7a with static OpenMP).
 *
 * The model is loaded once per language (nativeInit) and reused for every
 * transcription; PCM arrives as 16-bit mono 16 kHz and is widened to the
 * float[-1,1) range whisper_full expects. All calls are serialized by the
 * Java side (single-thread executor), so no native locking is needed.
 */
#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>

#include "whisper.h"

#define TAG "Flip2Whisper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)

JNIEXPORT jlong JNICALL
Java_com_tim_flip2_nullkeyboard_WhisperSttHelper_nativeInit(
        JNIEnv *env, jobject thiz, jstring model_path) {
    (void) thiz;
    const char *path = (*env)->GetStringUTFChars(env, model_path, NULL);
    if (!path) {
        return 0;
    }

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false; /* CPU-only on this SoC */

    struct whisper_context *ctx = whisper_init_from_file_with_params(path, cparams);
    (*env)->ReleaseStringUTFChars(env, model_path, path);
    if (ctx == NULL) {
        LOGW("whisper_init_from_file failed");
        return 0;
    }
    LOGI("whisper model loaded from %s", path);
    return (jlong) (intptr_t) ctx;
}

JNIEXPORT void JNICALL
Java_com_tim_flip2_nullkeyboard_WhisperSttHelper_nativeFree(
        JNIEnv *env, jobject thiz, jlong ctx_ptr) {
    (void) env;
    (void) thiz;
    struct whisper_context *ctx = (struct whisper_context *) (intptr_t) ctx_ptr;
    if (ctx) {
        whisper_free(ctx);
        LOGI("whisper model freed");
    }
}

/**
 * Transcribe PCM. Returns the concatenated segment text (may be empty), or
 * NULL on failure. lang is "en"/"uk"/... (never "auto" — the IME always
 * records with a known language selected).
 */
JNIEXPORT jstring JNICALL
Java_com_tim_flip2_nullkeyboard_WhisperSttHelper_nativeTranscribe(
        JNIEnv *env, jobject thiz, jlong ctx_ptr,
        jshortArray pcm_java, jstring lang_java, jint n_threads) {
    (void) thiz;
    struct whisper_context *ctx = (struct whisper_context *) (intptr_t) ctx_ptr;
    if (!ctx || !pcm_java) {
        return NULL;
    }

    const jsize n_short = (*env)->GetArrayLength(env, pcm_java);
    if (n_short <= 0) {
        return (*env)->NewStringUTF(env, "");
    }
    jshort *pcm = (*env)->GetShortArrayElements(env, pcm_java, NULL);
    if (!pcm) {
        return NULL;
    }

    float *samples = malloc(sizeof(float) * (size_t) n_short);
    if (!samples) {
        (*env)->ReleaseShortArrayElements(env, pcm_java, pcm, JNI_ABORT);
        return NULL;
    }
    for (jsize i = 0; i < n_short; i++) {
        samples[i] = pcm[i] / 32768.0f;
    }
    (*env)->ReleaseShortArrayElements(env, pcm_java, pcm, JNI_ABORT);

    const char *lang = "en";
    if (lang_java) {
        const char *l = (*env)->GetStringUTFChars(env, lang_java, NULL);
        if (l) {
            lang = l;
        }
    }

    struct whisper_full_params params =
            whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = n_threads > 0 ? n_threads : 2;
    params.language = lang;
    params.detect_language = false;
    params.translate = false;
    params.no_context = true;
    params.print_special = false;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;

    int ret = whisper_full(ctx, params, samples, n_short);
    free(samples);
    if (lang_java) {
        (*env)->ReleaseStringUTFChars(env, lang_java, lang);
    }
    if (ret != 0) {
        LOGW("whisper_full failed: %d", ret);
        return NULL;
    }

    /* Concatenate segment texts, collapsing duplicate separators. */
    size_t cap = 256, len = 0;
    char *out = malloc(cap);
    if (!out) {
        return NULL;
    }
    out[0] = '\0';
    int n_seg = whisper_full_n_segments(ctx);
    for (int i = 0; i < n_seg; i++) {
        const char *text = whisper_full_get_segment_text(ctx, i);
        if (!text) {
            continue;
        }
        size_t need = strlen(text) + 2;
        while (len + need > cap) {
            cap *= 2;
            char *tmp = realloc(out, cap);
            if (!tmp) {
                free(out);
                return NULL;
            }
            out = tmp;
        }
        if (len > 0 && out[len - 1] != ' ') {
            out[len++] = ' ';
        }
        strcpy(out + len, text);
        len += strlen(text);
    }

    /* Trim surrounding whitespace/newlines. */
    char *start = out;
    while (*start == ' ' || *start == '\n' || *start == '\t' || *start == '\r') start++;
    char *end = start + strlen(start);
    while (end > start && (end[-1] == ' ' || end[-1] == '\n' || end[-1] == '\t' || end[-1] == '\r')) end--;
    *end = '\0';

    jstring result = (*env)->NewStringUTF(env, start);
    free(out);
    return result;
}
