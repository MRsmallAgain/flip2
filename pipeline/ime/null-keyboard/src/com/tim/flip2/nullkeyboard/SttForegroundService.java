package com.tim.flip2.nullkeyboard;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

/**
 * Holds a microphone-type foreground service for the duration of one dictation.
 *
 * Android 11 only grants while-in-use RECORD_AUDIO access to a uid that has a
 * foreground component. An IME process stays IMPORTANT_BACKGROUND even while its
 * window has focus, so AudioPolicyService refuses the input stream with
 * "recording not allowed for uid/pid". A foreground service of type microphone
 * lifts the uid to PROCESS_STATE_FOREGROUND_SERVICE, which satisfies the check.
 *
 * Started from {@link SherpaSttHelper} before the AudioRecord is created and
 * stopped as soon as capture ends.
 */
public final class SttForegroundService extends Service {

    private static final String TAG = "Flip2STT";
    private static final String CHANNEL_ID = "flip2_stt";
    private static final int NOTIF_ID = 7311;

    static void start(Context ctx) {
        if (ctx == null) return;
        try {
            ctx.startForegroundService(new Intent(ctx, SttForegroundService.class));
        } catch (Throwable t) {
            Log.e(TAG, "fg start failed", t);
        }
    }

    static void stop(Context ctx) {
        if (ctx == null) return;
        try {
            ctx.stopService(new Intent(ctx, SttForegroundService.class));
        } catch (Throwable ignored) {
        }
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        try {
            Notification n = buildNotification(this);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
            } else {
                startForeground(NOTIF_ID, n);
            }
            Log.i(TAG, "fg service up");
        } catch (Throwable t) {
            // Most likely a SecurityException: without the foreground state the
            // mic would be denied anyway, so give up instead of leaving a zombie.
            Log.e(TAG, "startForeground failed", t);
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "fg service down");
        try {
            stopForeground(true);
        } catch (Throwable ignored) {
        }
        super.onDestroy();
    }

    private static Notification buildNotification(Context ctx) {
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm != null) {
            NotificationChannel ch = nm.getNotificationChannel(CHANNEL_ID);
            if (ch == null) {
                // MIN: no sound, no peek. The IME shows its own status chip.
                ch = new NotificationChannel(CHANNEL_ID, "Dictation", NotificationManager.IMPORTANCE_MIN);
                ch.setShowBadge(false);
                ch.setSound(null, null);
                ch.enableVibration(false);
                nm.createNotificationChannel(ch);
            }
        }
        Intent open = new Intent(ctx, SttForegroundService.class);
        PendingIntent pi = PendingIntent.getService(ctx, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle("Dictation")
                .setContentText("Listening for speech")
                .setOngoing(true)
                .setShowWhen(false)
                .setContentIntent(pi)
                .build();
    }
}
