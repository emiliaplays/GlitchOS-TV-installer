package com.glitchos.tv;

import android.service.notification.NotificationListenerService;

/**
 * Android's user-enabled access gate for other apps' media sessions.
 * The launcher does not read, store, dismiss, or relay notifications.
 * Notification delivery is disabled by the service's manifest filters.
 */
public final class MediaAccessService extends NotificationListenerService {
}
