package com.glitchos.tv;

import android.app.NotificationManager;
import android.content.ComponentName;
import android.content.Context;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.KeyEvent;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Activity-owned media controller. All methods and callbacks run on the main thread. */
public final class NowPlayingController {
    private final Context context;
    private final Runnable onChanged;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final MediaSessionManager manager;
    private final ComponentName listenerComponent;
    private final List<MediaController> sessions = new ArrayList<MediaController>();
    private final Map<MediaController, MediaController.Callback> callbacks =
            new LinkedHashMap<MediaController, MediaController.Callback>();
    private MediaSession.Token selectedToken;
    private boolean started;
    private boolean listening;
    private boolean accessDenied;

    private final MediaSessionManager.OnActiveSessionsChangedListener sessionListener =
            controllers -> {
                if (!started) return;
                if (hasAccess()) replaceSessions(controllers);
                else {
                    stopListening();
                    replaceSessions(Collections.emptyList());
                }
                changed();
            };

    public NowPlayingController(Context context, Runnable onChanged) {
        this.context = context.getApplicationContext();
        this.onChanged = onChanged;
        manager = (MediaSessionManager) this.context.getSystemService(Context.MEDIA_SESSION_SERVICE);
        listenerComponent = new ComponentName(this.context, MediaAccessService.class);
    }

    /** Call when the Now Playing tab becomes visible. No foreground service is needed. */
    public void start() {
        if (started) { refresh(); return; }
        started = true;
        refresh();
    }

    /** Release binder callbacks and artwork references whenever the tab is hidden. */
    public void stop() {
        started = false;
        stopListening();
        unregisterControllers();
        sessions.clear();
        handler.removeCallbacksAndMessages(null);
        // Keep the selected token, so returning to this tab does not choose a different app.
    }

    public boolean hasAccess() {
        if (accessDenied) return false;
        try {
            if (Build.VERSION.SDK_INT >= 27) {
                NotificationManager notifications = (NotificationManager)
                        context.getSystemService(Context.NOTIFICATION_SERVICE);
                return notifications != null
                        && notifications.isNotificationListenerAccessGranted(listenerComponent);
            }
            String enabled = Settings.Secure.getString(context.getContentResolver(),
                    "enabled_notification_listeners");
            if (enabled != null) {
                for (String flat : enabled.split(":")) {
                    if (listenerComponent.equals(ComponentName.unflattenFromString(flat))) return true;
                }
            }
        } catch (RuntimeException unavailable) {
            // Some TV firmware does not expose notification access to third-party launchers.
        }
        return false;
    }

    /** Recheck after returning from Android's access settings or a failed command. */
    public void refresh() {
        if (!started) return;
        accessDenied = false;
        if (manager == null || !hasAccess()) {
            stopListening();
            replaceSessions(Collections.emptyList());
            changed();
            return;
        }
        try {
            if (!listening) {
                manager.addOnActiveSessionsChangedListener(sessionListener, listenerComponent, handler);
                listening = true;
            }
            replaceSessions(manager.getActiveSessions(listenerComponent));
        } catch (SecurityException denied) {
            accessDenied = true;
            stopListening();
            replaceSessions(Collections.emptyList());
        } catch (RuntimeException unavailable) {
            replaceSessions(Collections.emptyList());
        }
        changed();
    }

    public List<MediaController> getSessions() {
        return Collections.unmodifiableList(new ArrayList<MediaController>(sessions));
    }

    public MediaController getSelected() {
        if (selectedToken == null) return null;
        for (MediaController controller : sessions) {
            if (selectedToken.equals(controller.getSessionToken())) return controller;
        }
        return null;
    }

    /** Selecting an app only changes which session the controls target. */
    public void select(MediaSession.Token token) {
        if (token == null) return;
        for (MediaController controller : sessions) {
            if (token.equals(controller.getSessionToken())) {
                selectedToken = token;
                changed();
                return;
            }
        }
    }

    public boolean isPlaying() { return isActive(getPlaybackState()); }

    public boolean canPlayPause() {
        PlaybackState state = getPlaybackState();
        if (state == null) return false;
        long explicit = isActive(state) ? PlaybackState.ACTION_PAUSE : PlaybackState.ACTION_PLAY;
        return (state.getActions() & (explicit | PlaybackState.ACTION_PLAY_PAUSE)) != 0;
    }

    public boolean canPrevious() { return supports(PlaybackState.ACTION_SKIP_TO_PREVIOUS); }
    public boolean canNext() { return supports(PlaybackState.ACTION_SKIP_TO_NEXT); }
    public boolean canSeek() {
        return supports(PlaybackState.ACTION_SEEK_TO) && getPositionMs() >= 0;
    }

    /** Unknown position remains -1, rather than pretending that live content starts at zero. */
    public long getPositionMs() {
        PlaybackState state = getPlaybackState();
        if (state == null || state.getPosition() < 0) return -1;
        long position = state.getPosition();
        int status = state.getState();
        long updated = state.getLastPositionUpdateTime();
        if (updated > 0 && (status == PlaybackState.STATE_PLAYING
                || status == PlaybackState.STATE_FAST_FORWARDING
                || status == PlaybackState.STATE_REWINDING)) {
            long elapsed = Math.max(0, SystemClock.elapsedRealtime() - updated);
            position += (long) (elapsed * state.getPlaybackSpeed());
        }
        long duration = getDurationMs();
        return Math.max(0, duration > 0 ? Math.min(position, duration) : position);
    }

    /** Zero means that the app has not provided a finite duration. */
    public long getDurationMs() {
        MediaController controller = getSelected();
        if (controller == null) return 0;
        try {
            MediaMetadata metadata = controller.getMetadata();
            return metadata == null ? 0 : Math.max(0,
                    metadata.getLong(MediaMetadata.METADATA_KEY_DURATION));
        } catch (RuntimeException unavailable) { return 0; }
    }

    /** A true result means that the request was sent, not that the player has obeyed it. */
    public boolean togglePlayPause() {
        MediaController controller = commandTarget();
        PlaybackState state = getPlaybackState();
        if (controller == null || state == null || !canPlayPause()) return false;
        try {
            boolean pause = isActive(state);
            long explicit = pause ? PlaybackState.ACTION_PAUSE : PlaybackState.ACTION_PLAY;
            if ((state.getActions() & explicit) != 0) {
                if (pause) controller.getTransportControls().pause();
                else controller.getTransportControls().play();
                return true;
            }
            // Some players advertise only PLAY_PAUSE, which is a media-button action.
            long now = SystemClock.uptimeMillis();
            boolean sent = controller.dispatchMediaButtonEvent(new KeyEvent(now, now,
                    KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 0));
            controller.dispatchMediaButtonEvent(new KeyEvent(now, now,
                    KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 0));
            return sent;
        } catch (RuntimeException unavailable) { refresh(); return false; }
    }

    public boolean previous() {
        MediaController controller = commandTarget();
        if (controller == null || !canPrevious()) return false;
        try { controller.getTransportControls().skipToPrevious(); return true; }
        catch (RuntimeException unavailable) { refresh(); return false; }
    }

    public boolean next() {
        MediaController controller = commandTarget();
        if (controller == null || !canNext()) return false;
        try { controller.getTransportControls().skipToNext(); return true; }
        catch (RuntimeException unavailable) { refresh(); return false; }
    }

    public boolean seekBy(long deltaMs) {
        MediaController controller = commandTarget();
        long position = getPositionMs();
        if (controller == null || !canSeek() || position < 0) return false;
        long duration = getDurationMs();
        long target = deltaMs > 0 && position > Long.MAX_VALUE - deltaMs
                ? Long.MAX_VALUE : Math.max(0, position + deltaMs);
        if (duration > 0) target = Math.min(target, duration);
        try { controller.getTransportControls().seekTo(target); return true; }
        catch (RuntimeException unavailable) { refresh(); return false; }
    }

    private MediaController commandTarget() {
        if (!started || !hasAccess()) { refresh(); return null; }
        return getSelected();
    }

    private PlaybackState getPlaybackState() {
        MediaController controller = getSelected();
        if (controller == null) return null;
        try { return controller.getPlaybackState(); }
        catch (RuntimeException unavailable) { return null; }
    }

    private boolean supports(long action) {
        PlaybackState state = getPlaybackState();
        return state != null && (state.getActions() & action) != 0;
    }

    private static boolean isActive(PlaybackState state) {
        if (state == null) return false;
        switch (state.getState()) {
            case PlaybackState.STATE_PLAYING:
            case PlaybackState.STATE_FAST_FORWARDING:
            case PlaybackState.STATE_REWINDING:
            case PlaybackState.STATE_BUFFERING:
            case PlaybackState.STATE_CONNECTING:
            case PlaybackState.STATE_SKIPPING_TO_NEXT:
            case PlaybackState.STATE_SKIPPING_TO_PREVIOUS:
            case PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM:
                return true;
            default: return false;
        }
    }

    private void replaceSessions(List<MediaController> controllers) {
        unregisterControllers();
        sessions.clear();
        if (controllers != null) {
            for (MediaController controller : controllers) {
                if (controller == null) continue;
                MediaController.Callback callback = new MediaController.Callback() {
                    @Override public void onMetadataChanged(MediaMetadata metadata) { changed(); }
                    @Override public void onPlaybackStateChanged(PlaybackState state) { changed(); }
                    @Override public void onSessionDestroyed() {
                        MediaController.Callback registered = callbacks.remove(controller);
                        if (registered != null) {
                            try { controller.unregisterCallback(registered); }
                            catch (RuntimeException unavailable) { /* Session is already gone. */ }
                        }
                        sessions.remove(controller);
                        ensureSelection();
                        changed();
                    }
                };
                try {
                    controller.registerCallback(callback, handler);
                    callbacks.put(controller, callback);
                    sessions.add(controller);
                } catch (RuntimeException unavailable) {
                    // A session can disappear between the system snapshot and registration.
                }
            }
        }
        ensureSelection();
    }

    private void ensureSelection() {
        if (getSelected() != null) return;
        selectedToken = null;
        // Android provides priority order; prefer an actively playing session on first entry.
        for (MediaController controller : sessions) {
            try {
                if (isActive(controller.getPlaybackState())) {
                    selectedToken = controller.getSessionToken();
                    return;
                }
            } catch (RuntimeException unavailable) { /* Try the next still-live session. */ }
        }
        if (!sessions.isEmpty()) selectedToken = sessions.get(0).getSessionToken();
    }

    private void unregisterControllers() {
        for (Map.Entry<MediaController, MediaController.Callback> entry : callbacks.entrySet()) {
            try { entry.getKey().unregisterCallback(entry.getValue()); }
            catch (RuntimeException unavailable) { /* A dead remote app needs no cleanup. */ }
        }
        callbacks.clear();
    }

    private void stopListening() {
        if (listening && manager != null) {
            try { manager.removeOnActiveSessionsChangedListener(sessionListener); }
            catch (RuntimeException unavailable) { /* The system service may have restarted. */ }
        }
        listening = false;
    }

    private void changed() {
        if (started && onChanged != null) onChanged.run();
    }
}
