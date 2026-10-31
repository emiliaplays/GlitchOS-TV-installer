package com.glitchos.tv;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.os.SystemClock;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;

/** Redirects only the stock Google TV home activity; never reads window contents. */
public final class HomeRedirectService extends AccessibilityService {
    private static final String GOOGLE_HOME_PACKAGE = "com.google.android.apps.tv.launcherx";
    private static final String GOOGLE_HOME_ACTIVITY = GOOGLE_HOME_PACKAGE + ".home.HomeActivity";
    private static final String GOOGLE_APPS_ONLY_ACTIVITY = GOOGLE_HOME_PACKAGE + ".home.VanillaModeHomeActivity";
    private static final long DEBOUNCE_MS = 500L;
    private long lastRedirectAt;

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        if (!GOOGLE_HOME_PACKAGE.contentEquals(event.getPackageName() == null ? "" : event.getPackageName())) return;
        CharSequence activity = event.getClassName();
        if (activity == null || (!GOOGLE_HOME_ACTIVITY.contentEquals(activity)
                && !GOOGLE_APPS_ONLY_ACTIVITY.contentEquals(activity))) return;

        long now = SystemClock.uptimeMillis();
        if (lastRedirectAt != 0L && now - lastRedirectAt < DEBOUNCE_MS) return;
        lastRedirectAt = now;
        Intent home = new Intent(this, MainActivity.class);
        home.setAction(Intent.ACTION_MAIN);
        home.addCategory(Intent.CATEGORY_HOME);
        home.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(home);
        } catch (RuntimeException unavailable) {
            Log.w("GlitchOSHome", "Unable to open the home screen", unavailable);
        }
    }

    @Override public void onInterrupt() {
        // No ongoing work, window access, or key interception to stop.
    }
}
