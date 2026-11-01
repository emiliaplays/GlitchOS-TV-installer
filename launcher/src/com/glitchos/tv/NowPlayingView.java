package com.glitchos.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** Visible-tab UI only. No network requests, notification contents or playback history. */
final class NowPlayingView extends LinearLayout {
    private static final int WHITE = 0xFFF9FAFC;
    private static final int MUTED = 0xFFBDD0DD;
    private final Activity activity;
    private final NowPlayingController media;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ImageView artwork;
    private final TextView source, title, subtitle, status, elapsed, duration, hint;
    private final ProgressBar progress;
    private final TextView previous, rewind, playPause, forward, next, choose, open, access;
    private boolean running;
    private boolean renderedAccess;
    private Bitmap shownArtwork;
    private String shownIconPackage;
    private AlertDialog chooser;
    private MediaSession.Token preferredToken;

    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (!running) return;
            if (media.hasAccess() != renderedAccess) media.refresh();
            updateProgress();
            handler.postDelayed(this, 1000L);
        }
    };

    NowPlayingView(Activity activity, Runnable browseApps, MediaSession.Token preferredToken) {
        super(activity);
        this.activity = activity;
        this.preferredToken = preferredToken;
        media = new NowPlayingController(activity, this::render);
        setOrientation(VERTICAL);
        setClipChildren(false);
        setClipToPadding(false);

        TextView heading = text("Now Playing", 30, WHITE);
        heading.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        addView(heading);
        TextView intro = text("Your music. Your movies. One place to control them.", 12, MUTED);
        LayoutParams introParams = new LayoutParams(-1, -2);
        introParams.topMargin = dp(6);
        introParams.bottomMargin = dp(18);
        addView(intro, introParams);

        LinearLayout card = new LinearLayout(activity);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(24), dp(22), dp(24), dp(22));
        card.setBackground(new MainActivity.GlassSurfaceDrawable(dp(25), false));
        card.setElevation(dp(6));
        card.setClipChildren(false);
        addView(card, new LayoutParams(-1, dp(252)));

        artwork = new ImageView(activity);
        artwork.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        artwork.setScaleType(ImageView.ScaleType.FIT_CENTER);
        artwork.setBackgroundColor(0x22081328);
        card.addView(artwork, new LayoutParams(dp(176), dp(176)));

        LinearLayout details = new LinearLayout(activity);
        details.setOrientation(VERTICAL);
        details.setGravity(Gravity.CENTER_VERTICAL);
        details.setClipChildren(false);
        LayoutParams detailsParams = new LayoutParams(0, -1, 1);
        detailsParams.leftMargin = dp(24);
        card.addView(details, detailsParams);
        source = text("GLITCHOS TV", 10, 0xFFA9EADB);
        source.setLetterSpacing(0.12f);
        source.setSingleLine(true);
        source.setEllipsize(TextUtils.TruncateAt.END);
        details.addView(source);
        title = text("Nothing playing yet", 25, WHITE);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.setMaxLines(2);
        title.setEllipsize(TextUtils.TruncateAt.END);
        LayoutParams titleParams = new LayoutParams(-1, -2);
        titleParams.topMargin = dp(7);
        details.addView(title, titleParams);
        subtitle = text("Start something in a media app, then return here.", 13, MUTED);
        subtitle.setSingleLine(true);
        subtitle.setEllipsize(TextUtils.TruncateAt.END);
        LayoutParams subtitleParams = new LayoutParams(-1, -2);
        subtitleParams.topMargin = dp(5);
        details.addView(subtitle, subtitleParams);
        status = text("", 10, 0xFFA9EADB);
        LayoutParams statusParams = new LayoutParams(-1, -2);
        statusParams.topMargin = dp(8);
        details.addView(status, statusParams);

        progress = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(1000);
        progress.setProgressTintList(android.content.res.ColorStateList.valueOf(0xFFB0F4DF));
        progress.setProgressBackgroundTintList(android.content.res.ColorStateList.valueOf(0x35FFFFFF));
        LayoutParams progressParams = new LayoutParams(-1, dp(5));
        progressParams.topMargin = dp(12);
        details.addView(progress, progressParams);
        LinearLayout times = new LinearLayout(activity);
        elapsed = text("--:--", 10, MUTED);
        duration = text("--:--", 10, MUTED);
        duration.setGravity(Gravity.RIGHT);
        times.addView(elapsed, new LayoutParams(0, -2, 1));
        times.addView(duration, new LayoutParams(-2, -2));
        LayoutParams timeParams = new LayoutParams(-1, -2);
        timeParams.topMargin = dp(4);
        timeParams.bottomMargin = dp(12);
        details.addView(times, timeParams);

        LinearLayout transport = new LinearLayout(activity);
        transport.setClipChildren(false);
        previous = button("|\u25c0", "Previous track or episode", () -> command(media.previous()));
        rewind = button("\u221210s", "Back 10 seconds", () -> command(media.seekBy(-10000L)));
        playPause = button("\u25b6  Play", "Play", () -> command(media.togglePlayPause()));
        forward = button("+10s", "Forward 10 seconds", () -> command(media.seekBy(10000L)));
        next = button("\u25b6|", "Next track or episode", () -> command(media.next()));
        TextView[] controls = {previous, rewind, playPause, forward, next};
        for (int i = 0; i < controls.length; i++) {
            LayoutParams controlParams = new LayoutParams(0, dp(44), i == 2 ? 1.6f : 1f);
            if (i > 0) controlParams.leftMargin = dp(7);
            transport.addView(controls[i], controlParams);
        }
        details.addView(transport, new LayoutParams(-1, -2));

        LinearLayout actions = new LinearLayout(activity);
        actions.setClipChildren(false);
        LayoutParams actionsParams = new LayoutParams(-1, -2);
        actionsParams.topMargin = dp(18);
        addView(actions, actionsParams);
        choose = button("Switch player", "Choose which app to control", this::chooseSession);
        open = button("Open app", "Return to the selected app", this::openSelectedApp);
        TextView browse = button("Browse apps", "Browse installed apps", browseApps);
        access = button("Media access", "Manage media access", this::openMediaAccess);
        for (TextView action : new TextView[]{choose, open, browse, access}) {
            LayoutParams params = new LayoutParams(-2, dp(40));
            if (action != choose) params.leftMargin = dp(10);
            actions.addView(action, params);
        }
        hint = text("Controls depend on the selected app. Some video apps stop when you leave them.", 11, MUTED);
        LayoutParams hintParams = new LayoutParams(-1, -2);
        hintParams.topMargin = dp(13);
        addView(hint, hintParams);
        render();
    }

    void start() {
        if (running) return;
        running = true;
        media.start();
        if (preferredToken != null) media.select(preferredToken);
        render();
        handler.post(tick);
    }

    void stop() {
        running = false;
        handler.removeCallbacks(tick);
        if (chooser != null) chooser.dismiss();
        chooser = null;
        if (media.getSelected() != null) preferredToken = media.getSelected().getSessionToken();
        media.stop();
        artwork.setImageDrawable(null);
        shownArtwork = null;
        shownIconPackage = null;
    }

    MediaSession.Token getSelectedToken() {
        MediaController selected = media.getSelected();
        return selected == null ? preferredToken : selected.getSessionToken();
    }

    private void render() {
        MediaController selected = media.getSelected();
        boolean allowed = media.hasAccess();
        renderedAccess = allowed;
        MediaMetadata metadata = safeMetadata(selected);
        PlaybackState state = safeState(selected);
        String app = selected == null ? "GLITCHOS TV" : appLabel(selected);
        source.setText(app.toUpperCase(Locale.getDefault()));
        String track = metadataText(metadata, MediaMetadata.METADATA_KEY_DISPLAY_TITLE, MediaMetadata.METADATA_KEY_TITLE);
        String artist = metadataText(metadata, MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE,
                MediaMetadata.METADATA_KEY_ARTIST, MediaMetadata.METADATA_KEY_ALBUM_ARTIST,
                MediaMetadata.METADATA_KEY_ALBUM);
        title.setText(!allowed ? "Connect your media apps" : selected == null ? "Nothing playing yet"
                : track.isEmpty() ? app : track);
        subtitle.setText(!allowed ? "Enable media access to see and control playback."
                : selected == null ? "Start something in a media app, then return here."
                : artist.isEmpty() ? "Playing from " + app : artist);
        status.setText(stateLabel(state, selected != null));
        showArtwork(metadata, selected);

        boolean playing = media.isPlaying();
        playPause.setText(playing ? "\u2161  Pause" : "\u25b6  Play");
        playPause.setContentDescription(playing ? "Pause playback" : "Resume playback");
        enable(previous, media.canPrevious());
        enable(rewind, media.canSeek());
        enable(playPause, media.canPlayPause());
        enable(forward, media.canSeek());
        enable(next, media.canNext());
        enable(choose, !media.getSessions().isEmpty());
        enable(open, selected != null);
        access.setText(allowed ? "Media access" : "Enable controls");
        hint.setText(!allowed
                ? "Android uses notification access for media controls. GlitchOS does not read or save notification contents."
                : "Controls depend on the selected app. Some video apps stop when you leave them.");
        updateProgress();
    }

    private void updateProgress() {
        long length = media.getDurationMs();
        long position = media.getPositionMs();
        boolean knownPosition = media.getSelected() != null && position >= 0;
        int value = length > 0 && knownPosition
                ? (int) Math.max(0, Math.min(1000, position * 1000d / length)) : 0;
        if (progress.getProgress() != value) progress.setProgress(value);
        progress.setAlpha(length > 0 ? 1f : .35f);
        String currentTime = knownPosition ? time(position) : "--:--";
        String totalTime = length > 0 ? time(length) : "--:--";
        if (!TextUtils.equals(elapsed.getText(), currentTime)) elapsed.setText(currentTime);
        if (!TextUtils.equals(duration.getText(), totalTime)) duration.setText(totalTime);
    }

    private void showArtwork(MediaMetadata metadata, MediaController selected) {
        Bitmap bitmap = null;
        if (metadata != null) {
            for (String key : new String[]{MediaMetadata.METADATA_KEY_DISPLAY_ICON,
                    MediaMetadata.METADATA_KEY_ART, MediaMetadata.METADATA_KEY_ALBUM_ART}) {
                try { bitmap = metadata.getBitmap(key); }
                catch (RuntimeException unavailable) { bitmap = null; }
                if (bitmap != null && !bitmap.isRecycled()) break;
                bitmap = null;
            }
        }
        if (bitmap != null) {
            if (shownArtwork != bitmap) artwork.setImageBitmap(bitmap);
            shownArtwork = bitmap;
            shownIconPackage = null;
        } else {
            String pkg = selected == null ? activity.getPackageName() : selected.getPackageName();
            if (shownArtwork != null || !pkg.equals(shownIconPackage)) {
                try { artwork.setImageDrawable(activity.getPackageManager().getApplicationIcon(pkg)); }
                catch (PackageManager.NameNotFoundException | RuntimeException unavailable) {
                    artwork.setImageResource(android.R.drawable.ic_media_play);
                }
            }
            shownArtwork = null;
            shownIconPackage = pkg;
        }
    }

    private void chooseSession() {
        List<MediaController> sessions = new ArrayList<>(media.getSessions());
        if (sessions.isEmpty()) return;
        CharSequence[] labels = new CharSequence[sessions.size()];
        int checked = -1;
        MediaController current = media.getSelected();
        for (int i = 0; i < sessions.size(); i++) {
            MediaController item = sessions.get(i);
            String track = metadataText(safeMetadata(item), MediaMetadata.METADATA_KEY_DISPLAY_TITLE,
                    MediaMetadata.METADATA_KEY_TITLE);
            labels[i] = appLabel(item) + (track.isEmpty() ? "" : " \u00b7 " + track);
            if (current != null && item.getSessionToken().equals(current.getSessionToken())) checked = i;
        }
        chooser = new AlertDialog.Builder(activity).setTitle("Choose a player")
                .setSingleChoiceItems(labels, checked, (dialog, index) -> {
                    media.select(sessions.get(index).getSessionToken());
                    dialog.dismiss();
                }).setNegativeButton("Cancel", null).create();
        chooser.show();
    }

    private void openSelectedApp() {
        MediaController selected = media.getSelected();
        if (selected == null) return;
        try {
            PendingIntent launch = selected.getSessionActivity();
            if (launch != null) { launch.send(); return; }
        } catch (PendingIntent.CanceledException | RuntimeException unavailable) { }
        try {
            PackageManager pm = activity.getPackageManager();
            Intent launch = pm.getLeanbackLaunchIntentForPackage(selected.getPackageName());
            if (launch == null) launch = pm.getLaunchIntentForPackage(selected.getPackageName());
            if (launch != null) { activity.startActivity(launch); return; }
        } catch (RuntimeException unavailable) { }
        Toast.makeText(activity, "Open this app from the Apps tab.", Toast.LENGTH_SHORT).show();
    }

    private void openMediaAccess() {
        new AlertDialog.Builder(activity).setTitle("Media controls")
                .setMessage("Allow GlitchOS media controls in Android's notification-access settings. "
                        + "This enables titles, artwork and playback buttons for compatible apps. "
                        + "GlitchOS does not read or save notification contents. You can turn access off here at any time.")
                .setPositiveButton("Open settings", (dialog, which) -> {
                    if (Build.VERSION.SDK_INT >= 30) {
                        try {
                            activity.startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                                    .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                                            new ComponentName(activity, MediaAccessService.class).flattenToString()));
                            return;
                        } catch (RuntimeException unavailable) { }
                    }
                    try { activity.startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); }
                    catch (RuntimeException unavailable) {
                        new AlertDialog.Builder(activity).setTitle("Media access setup")
                                .setMessage("This TV does not offer the notification-access settings page. "
                                        + "Enable GlitchOS media controls using the ADB setup instructions supplied with the launcher.")
                                .setPositiveButton("Close", null).show();
                    }
                }).setNegativeButton("Cancel", null).show();
    }

    private void command(boolean sent) {
        if (!sent) Toast.makeText(activity, "This app cannot use that control right now.", Toast.LENGTH_SHORT).show();
    }

    private void enable(TextView button, boolean enabled) {
        boolean lostFocus = button.isFocused() && !enabled;
        button.setEnabled(enabled);
        button.setFocusable(enabled);
        button.setFocusableInTouchMode(enabled);
        button.setAlpha(enabled ? 1f : .32f);
        if (lostFocus) access.requestFocus();
    }

    private TextView button(String label, String description, Runnable action) {
        TextView button = text(label, 13, WHITE);
        button.setGravity(Gravity.CENTER);
        button.setPadding(dp(13), 0, dp(13), 0);
        button.setSingleLine(true);
        button.setId(View.generateViewId());
        button.setContentDescription(description);
        button.setFocusable(true);
        button.setFocusableInTouchMode(true);
        button.setClickable(true);
        button.setBackground(new MainActivity.GlassSurfaceDrawable(dp(17), false));
        button.setOnFocusChangeListener((view, focused) -> {
            button.setTextColor(focused ? 0xFF153047 : WHITE);
            button.setBackground(new MainActivity.GlassSurfaceDrawable(dp(17), focused));
            button.setElevation(dp(focused ? 5 : 0));
        });
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private TextView text(String value, float size, int color) {
        TextView view = new TextView(activity);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setIncludeFontPadding(false);
        return view;
    }

    private String appLabel(MediaController controller) {
        try {
            PackageManager pm = activity.getPackageManager();
            return pm.getApplicationLabel(pm.getApplicationInfo(controller.getPackageName(), 0)).toString();
        } catch (PackageManager.NameNotFoundException | RuntimeException unavailable) {
            return controller.getPackageName();
        }
    }

    private static String metadataText(MediaMetadata metadata, String... keys) {
        if (metadata != null) for (String key : keys) {
            CharSequence value;
            try { value = metadata.getText(key); }
            catch (RuntimeException unavailable) { continue; }
            if (!TextUtils.isEmpty(value)) return value.toString();
        }
        return "";
    }

    private static MediaMetadata safeMetadata(MediaController controller) {
        try { return controller == null ? null : controller.getMetadata(); }
        catch (RuntimeException unavailable) { return null; }
    }

    private static PlaybackState safeState(MediaController controller) {
        try { return controller == null ? null : controller.getPlaybackState(); }
        catch (RuntimeException unavailable) { return null; }
    }

    private static String stateLabel(PlaybackState state, boolean selected) {
        if (!selected) return "";
        if (state == null) return "Playback status unavailable";
        switch (state.getState()) {
            case PlaybackState.STATE_PLAYING: return "Playing";
            case PlaybackState.STATE_PAUSED: return "Paused";
            case PlaybackState.STATE_BUFFERING: return "Buffering\u2026";
            case PlaybackState.STATE_CONNECTING: return "Connecting\u2026";
            case PlaybackState.STATE_ERROR: return "Playback unavailable \u00b7 open the app";
            case PlaybackState.STATE_STOPPED: return "Stopped";
            case PlaybackState.STATE_FAST_FORWARDING: return "Fast forwarding";
            case PlaybackState.STATE_REWINDING: return "Rewinding";
            default: return "Ready";
        }
    }

    private static String time(long ms) {
        long seconds = Math.max(0L, ms / 1000L);
        return seconds >= 3600L
                ? String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String.format(Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60);
    }

    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
