package com.ryanheise.audioservice;

import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Looper;
import android.service.notification.StatusBarNotification;

import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;
import androidx.media.app.NotificationCompat.MediaStyle;

import com.mesting.music.TogetherMediaLeaseCoordinator;
import com.mesting.music.R;

/** Narrow bridge to the pinned audio_service 0.18.19 instance.
 *
 * The package is intentionally the dependency's package so its existing
 * package-visible instance can be used without reflection, a second service,
 * another media session or a fake playing event. Public Android service APIs
 * perform the promotion. The notification ID/channel are the pinned plugin's
 * existing values and must be rechecked when that dependency is upgraded.
 */
public final class MestingTogetherMediaLease {
    private static final int NOTIFICATION_ID = 1124;
    private static final String CHANNEL = "com.mesting.music.playback";
    private static final String LEASE_NOTIFICATION = "com.mesting.music.together.mediaLease";
    private static Context applicationContext;
    private static AudioService promotedService;

    private static final TogetherMediaLeaseCoordinator coordinator =
            new TogetherMediaLeaseCoordinator(new TogetherMediaLeaseCoordinator.Port() {
                @Override public boolean isForeground() {
                    if (applicationContext == null) return false;
                    ActivityManager manager = (ActivityManager) applicationContext
                            .getSystemService(Context.ACTIVITY_SERVICE);
                    if (manager == null) return false;
                    // Android restricts this query to the calling app's own
                    // services; cloned accounts remain separate processes.
                    try {
                        for (ActivityManager.RunningServiceInfo info : manager.getRunningServices(32)) {
                            if (AudioService.class.getName().equals(info.service.getClassName())
                                    && info.foreground) return true;
                        }
                    } catch (RuntimeException ignored) { }
                    return false;
                }

                @Override public boolean promote() {
                    AudioService service = AudioService.instance;
                    if (service == null || applicationContext == null) return false;
                    try {
                        NotificationManager manager = (NotificationManager) service
                                .getSystemService(Context.NOTIFICATION_SERVICE);
                        if (manager == null) return false;
                        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
                            NotificationChannel channel = new NotificationChannel(
                                    CHANNEL, "Mesting Music", NotificationManager.IMPORTANCE_LOW);
                            channel.setShowBadge(false);
                            manager.createNotificationChannel(channel);
                        }
                        Intent launch = service.getPackageManager()
                                .getLaunchIntentForPackage(service.getPackageName());
                        PendingIntent content = launch == null ? null : PendingIntent.getActivity(
                                service, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                        Bundle extras = new Bundle();
                        extras.putBoolean(LEASE_NOTIFICATION, true);
                        NotificationCompat.Builder builder = new NotificationCompat.Builder(service, CHANNEL)
                                .setSmallIcon(R.drawable.ic_stat_together)
                                .setContentTitle("一起听")
                                .setContentText("正在同步好友的播放状态")
                                .setContentIntent(content)
                                .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
                                .setOngoing(true).setOnlyAlertOnce(true).setSilent(true)
                                .addExtras(extras);
                        if (service.getSessionToken() != null) {
                            builder.setStyle(new MediaStyle().setMediaSession(service.getSessionToken()));
                        }
                        // The bound AudioService already exists. This does
                        // not start another service or a timed startForegroundService
                        // attempt, and never changes its actual playback state.
                        service.startForeground(NOTIFICATION_ID, builder.build());
                        promotedService = service;
                        return true;
                    } catch (RuntimeException rejected) {
                        // Rejections remain a fixed diagnostic outcome; no
                        // exception text, account data or credentials are logged.
                        return false;
                    }
                }

                @Override public boolean releaseIfOwned() {
                    AudioService service = promotedService;
                    promotedService = null;
                    if (service == null || service.isPlaying()) return false;
                    try {
                        NotificationManager manager = (NotificationManager) service
                                .getSystemService(Context.NOTIFICATION_SERVICE);
                        if (manager == null) return false;
                        for (StatusBarNotification status : manager.getActiveNotifications()) {
                            Notification notification = status.getNotification();
                            if (status.getId() == NOTIFICATION_ID && notification.extras != null
                                    && notification.extras.getBoolean(LEASE_NOTIFICATION, false)) {
                                // Real playback replaces this same ID using the
                                // plugin's notification. Its lack of our marker
                                // is a handover: do not stop/cancel that owner.
                                ServiceCompat.stopForeground(service, Service.STOP_FOREGROUND_REMOVE);
                                return true;
                            }
                        }
                    } catch (RuntimeException ignored) { }
                    return false;
                }
            });

    private MestingTogetherMediaLease() { }

    public static TogetherMediaLeaseCoordinator.Outcome acquire(Context context, Object owner) {
        requireMainThread();
        applicationContext = context.getApplicationContext();
        return coordinator.acquire(owner);
    }

    public static boolean release(Object owner) {
        requireMainThread();
        return coordinator.release(owner);
    }

    private static void requireMainThread() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            throw new IllegalStateException("Together media lease requires the main thread");
        }
    }
}
