package com.glitchos.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.pm.ServiceInfo;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Outline;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.animation.DecelerateInterpolator;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** A small TV home screen using installed apps and the TV's native AirPlay receiver. */
public final class MainActivity extends Activity {
    private static final int WHITE = Color.rgb(249, 250, 252);
    private static final int MUTED = Color.rgb(173, 190, 197);
    private static final String PREFS = "glitchos-home";
    private static final String FAVORITES = "favorites";
    private static final String AIRPLAY_ENABLED = "airplay-enabled";
    private static final ComponentName ORIGINAL_AIRPLAY_SERVICE = new ComponentName(
            "com.homwee.mmp.screenshare", "com.changhong.mmp.airplay.service.AirPlayInitService");
    private static final ComponentName PATCHED_AIRPLAY_SERVICE = new ComponentName(
            "com.glitchos.airplayrepair", "com.changhong.mmp.airplay.service.AirPlayInitService");
    private static final String[] DEFAULT_FAVORITES = {
        "com.google.android.youtube.tv", "com.netflix.ninja",
        "com.amazon.amazonvideo.livingroom", "com.spotify.tv.android",
        "com.crunchyroll.crunchyroid", "de.rtli.tvnow"
    };

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final List<App> apps = new ArrayList<App>();
    private final List<String> favorites = new ArrayList<String>();
    private final Map<String, List<View>> appViews = new LinkedHashMap<String, List<View>>();
    private ScrollView scroll;
    private LinearLayout content;
    private LinearLayout allAppsSection;
    private TextView clock;
    private View firstFavorite;
    private View firstApp;
    private View homeTab;
    private View playingTab;
    private NowPlayingView nowPlayingView;
    private boolean nowPlayingOpen;
    private boolean resumed;
    private android.media.session.MediaSession.Token selectedMediaSession;
    private int columns;
    private int tileWidth;
    private int tileHeight;
    private int gutter;
    private int sidePadding;
    private String query = "";
    private String lastFocusedPackage;
    private boolean lastFocusWasFavorite;
    private boolean creating;
    private boolean airPlayStartupAttempted;
    private boolean airPlayBound;
    private ComponentName airPlayService;
    private ComponentName airPlayBoundService;
    private ServiceConnection airPlayConnection;

    private final Runnable clockTick = new Runnable() {
        @Override public void run() {
            if (clock != null) {
                java.text.DateFormat format = android.text.format.DateFormat.getTimeFormat(MainActivity.this);
                clock.setText(format.format(new Date()));
                clock.setContentDescription("Time, " + clock.getText());
            }
            handler.postDelayed(this, 30000L);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        if (state != null) {
            query = state.getString("query", "");
            lastFocusedPackage = state.getString("focus");
            lastFocusWasFavorite = state.getBoolean("favoriteFocus", true);
            nowPlayingOpen = state.getBoolean("nowPlaying", false);
            selectedMediaSession = state.getParcelable("mediaSession");
        }
        readFavorites();
        apps.addAll(discoverApps());
        buildScreen();
    }

    @Override protected void onStart() {
        super.onStart();
        if (isAirPlayEnabled()) bindAirPlayReceiver();
    }

    @Override protected void onResume() {
        super.onResume();
        resumed = true;
        // Recheck after an install/update without restarting the receiver on every Home press.
        selectAirPlayReceiver();
        if (!airPlayStartupAttempted) {
            airPlayStartupAttempted = true;
            if (isAirPlayEnabled()) startAirPlayReceiver(false);
        }
        handler.removeCallbacks(clockTick);
        handler.post(clockTick);
        List<App> refreshed = discoverApps();
        if (!fingerprint(apps).equals(fingerprint(refreshed))) {
            int oldScroll = scroll == null ? 0 : scroll.getScrollY();
            apps.clear();
            apps.addAll(refreshed);
            buildScreen();
            scroll.post(() -> scroll.scrollTo(0, oldScroll));
        }
        if (nowPlayingView != null) nowPlayingView.start();
    }

    @Override protected void onPause() {
        resumed = false;
        if (nowPlayingView != null) nowPlayingView.stop();
        handler.removeCallbacks(clockTick);
        super.onPause();
    }

    @Override protected void onStop() {
        releaseAirPlayBinding();
        super.onStop();
    }

    @Override protected void onDestroy() {
        releaseAirPlayBinding();
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        out.putString("query", query);
        out.putString("focus", lastFocusedPackage);
        out.putBoolean("favoriteFocus", lastFocusWasFavorite);
        out.putBoolean("nowPlaying", nowPlayingOpen);
        if (nowPlayingView != null && nowPlayingView.getSelectedToken() != null)
            selectedMediaSession = nowPlayingView.getSelectedToken();
        out.putParcelable("mediaSession", selectedMediaSession);
        super.onSaveInstanceState(out);
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (intent.hasCategory(Intent.CATEGORY_HOME)) goHome();
    }

    @Override public void onBackPressed() { goHome(); }

    @Override public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_SEARCH) {
            if (event.getRepeatCount() == 0) showSearch();
            return true;
        }
        if (!nowPlayingOpen && keyCode == KeyEvent.KEYCODE_MENU && lastFocusedPackage != null) {
            if (event.getRepeatCount() == 0) {
                for (App app : apps) {
                    if (app.packageName.equals(lastFocusedPackage)) {
                        showAppActions(app);
                        break;
                    }
                }
            }
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void buildScreen() {
        creating = true;
        if (nowPlayingView != null) {
            if (nowPlayingView.getSelectedToken() != null)
                selectedMediaSession = nowPlayingView.getSelectedToken();
            nowPlayingView.stop();
        }
        nowPlayingView = null;
        appViews.clear();
        firstFavorite = null;
        firstApp = null;
        allAppsSection = null;
        float density = getResources().getDisplayMetrics().density;
        int widthDp = (int) (getResources().getDisplayMetrics().widthPixels / density);
        sidePadding = dp(widthDp >= 1000 ? 50 : 36);
        gutter = dp(14);
        columns = widthDp >= 800 ? 6 : 5;
        tileWidth = (getResources().getDisplayMetrics().widthPixels - 2 * sidePadding - dp(32)
                - (columns - 1) * gutter) / columns;
        tileHeight = Math.round(tileWidth * 9f / 16f);

        FrameLayout root = new FrameLayout(this);
        root.setBackground(new LandscapeDrawable());
        root.setClipChildren(false);
        scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setVerticalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        scroll.setClipToPadding(false);
        scroll.setClipChildren(false);
        scroll.setDescendantFocusability(ViewGroup.FOCUS_AFTER_DESCENDANTS);
        root.addView(scroll, new FrameLayout.LayoutParams(-1, -1));

        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(sidePadding, dp(22), sidePadding, dp(32));
        content.setClipChildren(false);
        content.setClipToPadding(false);
        scroll.addView(content, new ScrollView.LayoutParams(-1, -2));
        addHeader();
        if (nowPlayingOpen) {
            nowPlayingView = new NowPlayingView(this, this::goToApps, selectedMediaSession);
            LinearLayout.LayoutParams playerParams = new LinearLayout.LayoutParams(-1, -2);
            playerParams.topMargin = dp(20);
            content.addView(nowPlayingView, playerParams);
        } else {
        addHero();
        if (query.isEmpty()) addFavorites();
        addAllApps();
        TextView hint = text("Hold OK on an app to make it a favorite", 11, 0xFF93A7AD);
        LinearLayout.LayoutParams hintParams = new LinearLayout.LayoutParams(-1, -2);
        hintParams.topMargin = dp(19);
        content.addView(hint, hintParams);
        }
        setContentView(root);
        creating = false;
        if (resumed && nowPlayingView != null) nowPlayingView.start();
        content.post(() -> {
            if (nowPlayingView != null) {
                playingTab.requestFocus();
                scroll.scrollTo(0, 0);
                return;
            }
            View focus = findPreviousFocus();
            if (focus == null) focus = firstFavorite != null ? firstFavorite : firstApp;
            if (focus == null) focus = homeTab;
            if (focus != null) focus.requestFocus();
        });
    }

    private void addHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setClipChildren(false);
        content.addView(header, new LinearLayout.LayoutParams(-1, dp(54)));

        TextView brand = text("GlitchOS", 24, WHITE);
        brand.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        brand.setLetterSpacing(-0.035f);
        brand.setContentDescription("GlitchOS TV Edition");
        header.addView(brand, new LinearLayout.LayoutParams(-2, -2));
        TextView tv = text("TV EDITION", 8, 0xFFD2E7E8);
        tv.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        tv.setLetterSpacing(0.12f);
        tv.setGravity(Gravity.CENTER);
        tv.setBackground(new GlassSurfaceDrawable(dp(8), false));
        LinearLayout.LayoutParams tvParams = new LinearLayout.LayoutParams(dp(66), dp(22));
        tvParams.leftMargin = dp(8);
        header.addView(tv, tvParams);

        View leftSpace = new View(this);
        header.addView(leftSpace, new LinearLayout.LayoutParams(0, 1, 1));
        LinearLayout navigation = new LinearLayout(this);
        navigation.setGravity(Gravity.CENTER_VERTICAL);
        navigation.setPadding(dp(5), dp(5), dp(5), dp(5));
        navigation.setBackground(new GlassSurfaceDrawable(dp(26), false));
        navigation.setElevation(dp(7));
        navigation.setClipChildren(false);
        navigation.setClipToPadding(false);
        header.addView(navigation, new LinearLayout.LayoutParams(-2, dp(48)));
        homeTab = navButton("Home", this::goHome);
        navigation.addView(homeTab);
        playingTab = navButton("Now Playing", this::goToNowPlaying);
        navigation.addView(playingTab);
        navigation.addView(navButton("Apps", this::goToApps));
        navigation.addView(navButton("Search", this::showSearch));
        navigation.addView(navButton("Inputs", () -> openSettings(true)));
        navigation.addView(navButton("AirPlay", this::showAirPlay));
        navigation.addView(navButton("Settings", () -> openSettings(false)));
        View rightSpace = new View(this);
        header.addView(rightSpace, new LinearLayout.LayoutParams(0, 1, 1));

        clock = text(android.text.format.DateFormat.getTimeFormat(this).format(new Date()), 16, WHITE);
        clock.setGravity(Gravity.CENTER);
        clock.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        clock.setBackground(new GlassSurfaceDrawable(dp(23), false));
        clock.setElevation(dp(5));
        header.addView(clock, new LinearLayout.LayoutParams(dp(76), dp(44)));
    }

    private View navButton(String title, Runnable action) {
        TextView view = text(title, 13, 0xFFD8E3E7);
        view.setGravity(Gravity.CENTER);
        view.setPadding(dp(12), 0, dp(12), 0);
        view.setFocusable(true);
        view.setFocusableInTouchMode(true);
        view.setClickable(true);
        view.setContentDescription(title);
        boolean isHome = nowPlayingOpen ? "Now Playing".equals(title) : "Home".equals(title);
        view.setBackground(rounded(isHome ? 0x28FFFFFF : Color.TRANSPARENT, dp(19), 0, 0));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-2, dp(38));
        params.leftMargin = dp(1);
        params.rightMargin = dp(1);
        view.setLayoutParams(params);
        view.setOnFocusChangeListener((v, focus) -> {
            view.setTextColor(focus ? 0xFF153047 : WHITE);
            view.setBackground(focus ? new GlassSurfaceDrawable(dp(20), true)
                    : rounded(isHome ? 0x28FFFFFF : Color.TRANSPARENT, dp(19), 0, 0));
            view.setElevation(dp(focus ? 5 : 0));
            view.animate().scaleX(focus ? 1.04f : 1f).scaleY(focus ? 1.04f : 1f)
                    .setDuration(160).start();
        });
        view.setOnClickListener(v -> action.run());
        return view;
    }

    private void addHero() {
        LinearLayout hero = new LinearLayout(this);
        hero.setOrientation(LinearLayout.VERTICAL);
        hero.setGravity(Gravity.CENTER_VERTICAL);
        hero.setPadding(dp(16), 0, dp(16), 0);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(query.isEmpty() ? 109 : 103));
        params.topMargin = dp(7);
        content.addView(hero, params);
        TextView date = text(new SimpleDateFormat("EEEE, MMMM d", Locale.getDefault())
                .format(new Date()).toUpperCase(Locale.getDefault()), 10, 0xFFB2CCC6);
        date.setLetterSpacing(0.16f);
        date.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        hero.addView(date);
        TextView headline = text(query.isEmpty() ? "Your evening. Your screen." : "Find your next favorite.", 32, WHITE);
        headline.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        headline.setLetterSpacing(-0.035f);
        headline.setShadowLayer(dp(10), 0, dp(2), 0x35040C20);
        LinearLayout.LayoutParams headlineParams = new LinearLayout.LayoutParams(-1, -2);
        headlineParams.topMargin = dp(8);
        hero.addView(headline, headlineParams);
        TextView subline = text(query.isEmpty() ? "All your favorites, beautifully together." : "Search your installed apps.", 12, 0xFFCDDFE8);
        LinearLayout.LayoutParams sublineParams = new LinearLayout.LayoutParams(-1, -2);
        sublineParams.topMargin = dp(6);
        hero.addView(subline, sublineParams);
    }

    private void addFavorites() {
        List<App> pinned = new ArrayList<App>();
        for (String packageName : favorites) {
            for (App app : apps) {
                if (app.packageName.equals(packageName)) { pinned.add(app); break; }
            }
        }
        LinearLayout shelf = new LinearLayout(this);
        shelf.setOrientation(LinearLayout.VERTICAL);
        shelf.setPadding(dp(16), dp(14), dp(16), dp(8));
        shelf.setBackground(new GlassSurfaceDrawable(dp(25), false));
        shelf.setElevation(dp(8));
        shelf.setClipChildren(false);
        shelf.setClipToPadding(false);
        LinearLayout.LayoutParams shelfParams = new LinearLayout.LayoutParams(-1, -2);
        shelfParams.topMargin = dp(7);
        content.addView(shelf, shelfParams);
        sectionTitle(shelf, "Favorites", "Hold OK to make it yours");
        if (pinned.isEmpty()) {
            TextView empty = text("Hold OK on any app below to add it here.", 13, MUTED);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(54));
            empty.setGravity(Gravity.CENTER_VERTICAL);
            shelf.addView(empty, params);
            return;
        }
        addGrid(shelf, pinned, true);
    }

    private void addAllApps() {
        allAppsSection = new LinearLayout(this);
        allAppsSection.setOrientation(LinearLayout.VERTICAL);
        allAppsSection.setClipChildren(false);
        allAppsSection.setClipToPadding(false);
        allAppsSection.setPadding(dp(16), 0, dp(16), 0);
        LinearLayout.LayoutParams sectionParams = new LinearLayout.LayoutParams(-1, -2);
        sectionParams.topMargin = dp(query.isEmpty() ? 22 : 0);
        content.addView(allAppsSection, sectionParams);

        List<App> visible = new ArrayList<App>();
        String normalized = query.toLowerCase(Locale.ROOT);
        for (App app : apps) {
            if (query.isEmpty() || app.label.toLowerCase(Locale.ROOT).contains(normalized)) visible.add(app);
        }
        LinearLayout titleRow = new LinearLayout(this);
        titleRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = text(query.isEmpty() ? "Your apps" : "Results for \u201c" + query + "\u201d", 19, WHITE);
        title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        titleRow.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        TextView count = text(visible.size() + (visible.size() == 1 ? " app" : " apps"), 11, MUTED);
        titleRow.addView(count);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(-1, -2);
        titleParams.bottomMargin = dp(14);
        allAppsSection.addView(titleRow, titleParams);
        if (visible.isEmpty()) {
            TextView empty = text("No apps found. Try a different search.", 15, MUTED);
            empty.setPadding(0, dp(15), 0, dp(35));
            allAppsSection.addView(empty);
        } else {
            addGrid(allAppsSection, visible, false);
        }
    }

    private void sectionTitle(LinearLayout parent, String title, String subtitle) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView heading = text(title, 19, WHITE);
        heading.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        row.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));
        TextView detail = text(subtitle, 10, 0xFFD0DFE7);
        row.addView(detail);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.bottomMargin = dp(14);
        parent.addView(row, params);
    }

    private void addGrid(LinearLayout parent, List<App> items, boolean favoriteRow) {
        LinearLayout row = null;
        List<View> cells = new ArrayList<View>();
        for (int i = 0; i < items.size(); i++) {
            if (i % columns == 0) {
                row = new LinearLayout(this);
                row.setOrientation(LinearLayout.HORIZONTAL);
                row.setClipChildren(false);
                row.setClipToPadding(false);
                LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(-1, -2);
                rowParams.bottomMargin = dp(favoriteRow ? 4 : 18);
                parent.addView(row, rowParams);
            }
            View card = appCard(items.get(i), favoriteRow);
            LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(tileWidth, tileHeight + dp(29));
            if (i % columns != 0) cardParams.leftMargin = gutter;
            row.addView(card, cardParams);
            cells.add(card);
            if (favoriteRow && firstFavorite == null) firstFavorite = card;
            if (!favoriteRow && firstApp == null) firstApp = card;
        }
        // Keep left/right navigation within a row. Up/down remains natural between sections.
        for (int i = 0; i < cells.size(); i++) {
            View cell = cells.get(i);
            if (i % columns == 0) cell.setNextFocusLeftId(cell.getId());
            if (i % columns == columns - 1 || i == cells.size() - 1) cell.setNextFocusRightId(cell.getId());
        }
    }

    private View appCard(App app, boolean favoriteRow) {
        LinearLayout card = new LinearLayout(this);
        card.setId(View.generateViewId());
        card.setOrientation(LinearLayout.VERTICAL);
        card.setFocusable(true);
        card.setFocusableInTouchMode(true);
        card.setClickable(true);
        card.setLongClickable(true);
        card.setClipChildren(false);
        card.setClipToPadding(false);
        card.setContentDescription(app.label + (favorites.contains(app.packageName) ? ", favorite" : "")
                + ". Press OK to open. Hold OK for options.");
        FrameLayout art = new FrameLayout(this);
        int color = appColor(app.packageName);
        art.setBackground(rounded(color, dp(14), 0, 0));
        art.setClipToOutline(true);
        art.setElevation(dp(4));
        card.addView(art, new LinearLayout.LayoutParams(-1, tileHeight));
        Drawable banner = null;
        try { banner = app.resolve.activityInfo.loadBanner(getPackageManager()); } catch (RuntimeException ignored) { }
        if (banner == null) {
            try { banner = getPackageManager().getApplicationBanner(app.packageName); }
            catch (PackageManager.NameNotFoundException | RuntimeException ignored) { }
        }
        ImageView image = new ImageView(this);
        image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        if (banner != null) {
            image.setImageDrawable(banner);
            image.setScaleType(ImageView.ScaleType.FIT_CENTER);
            art.addView(image, new FrameLayout.LayoutParams(-1, -1));
        } else {
            try { image.setImageDrawable(app.resolve.loadIcon(getPackageManager())); }
            catch (RuntimeException ignored) { }
            image.setScaleType(ImageView.ScaleType.FIT_CENTER);
            int iconSize = Math.round(tileHeight * 0.63f);
            art.addView(image, new FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER));
        }
        View outline = new View(this);
        outline.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        outline.setBackground(new TileGlassDrawable(dp(14), false));
        art.addView(outline, new FrameLayout.LayoutParams(-1, -1));

        TextView label = text(app.label, 11, 0xFFCDDAE4);
        label.setSingleLine(true);
        label.setEllipsize(android.text.TextUtils.TruncateAt.END);
        label.setGravity(Gravity.CENTER);
        label.setPadding(dp(2), dp(7), dp(2), 0);
        card.addView(label, new LinearLayout.LayoutParams(-1, dp(29)));
        card.setOnFocusChangeListener((v, focus) -> {
            card.animate().scaleX(focus ? 1.065f : 1f).scaleY(focus ? 1.065f : 1f)
                    .translationY(focus ? -dp(3) : 0)
                    .setDuration(180).setInterpolator(new DecelerateInterpolator()).start();
            art.setElevation(dp(focus ? 16 : 4));
            card.setTranslationZ(dp(focus ? 8 : 0));
            outline.setBackground(new TileGlassDrawable(dp(14), focus));
            label.setTextColor(focus ? WHITE : 0xFFCDDAE4);
            if (focus) {
                lastFocusedPackage = app.packageName;
                lastFocusWasFavorite = favoriteRow;
            }
        });
        card.setOnClickListener(v -> launchApp(app));
        card.setOnLongClickListener(v -> { showAppActions(app); return true; });
        List<View> views = appViews.get(app.packageName);
        if (views == null) {
            views = new ArrayList<View>();
            appViews.put(app.packageName, views);
        }
        views.add(card);
        return card;
    }

    private void launchApp(App app) {
        try {
            Intent intent = new Intent(Intent.ACTION_MAIN);
            intent.addCategory(app.isLeanback ? Intent.CATEGORY_LEANBACK_LAUNCHER : Intent.CATEGORY_LAUNCHER);
            intent.setComponent(new ComponentName(app.packageName, app.resolve.activityInfo.name));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            startActivity(intent);
        } catch (RuntimeException e) {
            Toast.makeText(this, "This app could not open. Try again from Settings.", Toast.LENGTH_LONG).show();
        }
    }

    private void showAppActions(App app) {
        boolean pinned = favorites.contains(app.packageName);
        new AlertDialog.Builder(this)
                .setTitle(app.label)
                .setItems(new String[]{pinned ? "Remove from favorites" : "Add to favorites", "App info"},
                    (dialog, which) -> {
                        if (which == 0) {
                            if (pinned) favorites.remove(app.packageName);
                            else favorites.add(app.packageName);
                            saveFavorites();
                            lastFocusedPackage = app.packageName;
                            lastFocusWasFavorite = !pinned;
                            buildScreen();
                        } else {
                            try {
                                startActivity(new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        android.net.Uri.parse("package:" + app.packageName)));
                            } catch (RuntimeException e) { openSettings(false); }
                        }
                    }).setNegativeButton("Cancel", null).show();
    }

    private void showSearch() {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_TEXT);
        input.setText(query);
        input.setSelectAllOnFocus(true);
        input.setHint("App name");
        input.setContentDescription("Search installed apps");
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setPadding(dp(24), dp(8), dp(24), dp(8));
        wrapper.addView(input, new LinearLayout.LayoutParams(-1, -2));
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Search apps").setView(wrapper)
                .setPositiveButton("Search", (d, which) -> {
                    nowPlayingOpen = false;
                    query = input.getText().toString().trim();
                    lastFocusedPackage = null;
                    buildScreen();
                })
                .setNeutralButton("Show all", (d, which) -> {
                    nowPlayingOpen = false;
                    query = "";
                    lastFocusedPackage = null;
                    buildScreen();
                    content.post(this::goToApps);
                })
                .setNegativeButton("Cancel", null).create();
        input.setOnEditorActionListener((v, actionId, event) -> {
            if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
                    || actionId == android.view.inputmethod.EditorInfo.IME_ACTION_DONE) {
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick();
                return true;
            }
            return false;
        });
        input.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH);
        dialog.show();
        input.requestFocus();
    }

    private void openSettings(boolean inputs) {
        Intent intent = new Intent(inputs ? "com.android.tv.action.VIEW_INPUTS" : android.provider.Settings.ACTION_SETTINGS);
        try {
            startActivity(intent);
        } catch (RuntimeException e) {
            if (inputs) {
                try {
                    startActivity(new Intent(android.provider.Settings.ACTION_SETTINGS));
                    return;
                } catch (RuntimeException fallbackUnavailable) { }
            }
            Toast.makeText(this, "Open Settings with your TV remote.", Toast.LENGTH_LONG).show();
        }
    }

    private boolean isAirPlayEnabled() {
        return getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(AIRPLAY_ENABLED, true);
    }

    private boolean isAirPlayServiceAvailable(ComponentName component) {
        try {
            ServiceInfo receiver = getPackageManager().getServiceInfo(component, 0);
            return receiver.enabled && receiver.exported && receiver.applicationInfo.enabled;
        } catch (PackageManager.NameNotFoundException | RuntimeException unavailable) {
            return false;
        }
    }

    private ComponentName findAirPlayReceiver() {
        if (isAirPlayServiceAvailable(PATCHED_AIRPLAY_SERVICE)) return PATCHED_AIRPLAY_SERVICE;
        if (isAirPlayServiceAvailable(ORIGINAL_AIRPLAY_SERVICE)) return ORIGINAL_AIRPLAY_SERVICE;
        return null;
    }

    private ComponentName selectAirPlayReceiver() {
        ComponentName selected = findAirPlayReceiver();
        if (selected == null ? airPlayService != null : !selected.equals(airPlayService)) {
            releaseAirPlayBinding();
            airPlayService = selected;
            airPlayStartupAttempted = false;
        }
        return selected;
    }

    private Intent airPlayIntent(ComponentName component) {
        return new Intent().setComponent(component)
                .putExtra("allow_backgroud", true)
                .putExtra("airplay", true)
                .putExtra("dlna_config", true);
    }

    private void bindAirPlayReceiver() {
        ComponentName selected = selectAirPlayReceiver();
        if (selected == null) return;
        if (PATCHED_AIRPLAY_SERVICE.equals(selected)) {
            try {
                // Both receivers advertise the same TV and use the same ports.
                stopService(new Intent().setComponent(ORIGINAL_AIRPLAY_SERVICE));
            } catch (RuntimeException unavailable) {
                android.util.Log.w("GlitchOSAirPlay", "Unable to stop the original TV receiver", unavailable);
            }
        }
        if (airPlayBound && selected.equals(airPlayBoundService)) return;
        releaseAirPlayBinding();
        int flags = Context.BIND_AUTO_CREATE;
        if (Build.VERSION.SDK_INT >= 34) flags |= Context.BIND_ALLOW_ACTIVITY_STARTS;
        ServiceConnection connection = new ServiceConnection() {
            @Override public void onServiceConnected(ComponentName name, IBinder service) {
                // This binding grants the visible client relationship; no binder API is needed.
            }

            @Override public void onNullBinding(ComponentName name) {
                // Retain the registration even though the native receiver returns a null binder.
            }

            @Override public void onServiceDisconnected(ComponentName name) {
                // Keep the registration; a later visible cycle can start a recreated service.
                if (airPlayConnection == this) airPlayStartupAttempted = false;
            }

            @Override public void onBindingDied(ComponentName name) {
                // An obsolete connection must not release a newly selected receiver's binding.
                if (airPlayConnection != this) return;
                releaseAirPlayBinding();
                airPlayStartupAttempted = false;
                // Retry only on a later visible cycle or an explicit Enable action.
            }
        };
        airPlayConnection = connection;
        airPlayBoundService = selected;
        try {
            // Track bindService's result, including native services that return a null binder.
            airPlayBound = bindService(new Intent().setComponent(selected), connection, flags);
        } catch (RuntimeException unavailable) {
            airPlayBound = false;
            android.util.Log.w("GlitchOSAirPlay", "Unable to bind the TV AirPlay receiver", unavailable);
        }
        if (!airPlayBound) {
            airPlayConnection = null;
            airPlayBoundService = null;
        }
    }

    private void releaseAirPlayBinding() {
        ServiceConnection connection = airPlayConnection;
        boolean wasBound = airPlayBound;
        airPlayBound = false;
        airPlayConnection = null;
        airPlayBoundService = null;
        if (!wasBound || connection == null) return;
        try {
            unbindService(connection);
        } catch (RuntimeException unavailable) {
            android.util.Log.w("GlitchOSAirPlay", "Unable to release the TV AirPlay binding", unavailable);
        }
    }

    private boolean startAirPlayReceiver(boolean showError) {
        try {
            bindAirPlayReceiver();
            if (airPlayService == null) throw new IllegalStateException("TV receiver unavailable");
            ComponentName started = startForegroundService(airPlayIntent(airPlayService));
            if (started == null) throw new IllegalStateException("TV receiver did not start");
            airPlayStartupAttempted = true;
            return true;
        } catch (RuntimeException unavailable) {
            android.util.Log.w("GlitchOSAirPlay", "Unable to start the TV AirPlay receiver", unavailable);
            if (showError) Toast.makeText(this, "AirPlay could not start. Try again from this menu.",
                    Toast.LENGTH_LONG).show();
            return false;
        }
    }

    private void showAirPlay() {
        ComponentName receiver = findAirPlayReceiver();
        if (receiver == null) {
            new AlertDialog.Builder(this).setTitle("AirPlay")
                    .setMessage("This TV's AirPlay receiver is unavailable.")
                    .setPositiveButton("Close", null).show();
            return;
        }
        boolean enabled = isAirPlayEnabled();
        String receiverName = "SmartTV(D245)";
        try {
            String savedName = android.provider.Settings.Global.getString(getContentResolver(), "tvmac");
            if (savedName != null && !savedName.trim().isEmpty()) receiverName = savedName;
        } catch (RuntimeException unavailable) {
            // Use the firmware's default sharing name if the setting cannot be read.
        }
        String message = (enabled ? "AirPlay enabled. Connect while GlitchOS is on screen."
                : "AirPlay disabled. GlitchOS will not start the TV receiver.")
                + "\n\nConnect your iPhone or iPad to the same Wi-Fi as this TV, open Control Center, "
                + "then choose Screen Mirroring and select " + receiverName + ".";
        new AlertDialog.Builder(this).setTitle("AirPlay")
                .setMessage(message)
                .setPositiveButton(enabled ? "Disable AirPlay" : "Enable AirPlay", (dialog, which) -> {
                    if (!enabled) {
                        if (!startAirPlayReceiver(true)) {
                            releaseAirPlayBinding();
                            return;
                        }
                    } else {
                        try {
                            if (isAirPlayServiceAvailable(PATCHED_AIRPLAY_SERVICE)) {
                                stopService(new Intent().setComponent(PATCHED_AIRPLAY_SERVICE));
                            }
                            if (isAirPlayServiceAvailable(ORIGINAL_AIRPLAY_SERVICE)) {
                                stopService(new Intent().setComponent(ORIGINAL_AIRPLAY_SERVICE));
                            }
                            releaseAirPlayBinding();
                            airPlayStartupAttempted = false;
                        } catch (RuntimeException unavailable) {
                            Toast.makeText(this, "AirPlay could not stop. Try again.", Toast.LENGTH_LONG).show();
                            return;
                        }
                    }
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                            .putBoolean(AIRPLAY_ENABLED, !enabled).apply();
                    Toast.makeText(this, !enabled ? "AirPlay enabled" : "AirPlay disabled", Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("Close", null).show();
    }

    private void goHome() {
        if (creating) return;
        if (!query.isEmpty() || nowPlayingOpen) {
            nowPlayingOpen = false;
            query = "";
            lastFocusedPackage = null;
            buildScreen();
        }
        View target = firstFavorite != null ? firstFavorite : firstApp;
        if (target != null) target.requestFocus();
        if (scroll != null) scroll.smoothScrollTo(0, 0);
    }

    private void goToApps() {
        if (!query.isEmpty() || nowPlayingOpen) {
            nowPlayingOpen = false;
            query = "";
            lastFocusedPackage = null;
            buildScreen();
            content.post(this::goToApps);
            return;
        }
        if (firstApp != null) firstApp.requestFocus();
        if (allAppsSection != null) scroll.smoothScrollTo(0, Math.max(0, allAppsSection.getTop() - dp(28)));
    }

    private void goToNowPlaying() {
        if (nowPlayingOpen) return;
        nowPlayingOpen = true;
        buildScreen();
    }

    private View findPreviousFocus() {
        if (lastFocusedPackage == null) return null;
        List<View> matches = appViews.get(lastFocusedPackage);
        if (matches == null || matches.isEmpty()) return null;
        return lastFocusWasFavorite ? matches.get(0) : matches.get(matches.size() - 1);
    }

    private List<App> discoverApps() {
        PackageManager pm = getPackageManager();
        Map<String, App> found = new LinkedHashMap<String, App>();
        String[] categories = {Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER};
        for (int pass = 0; pass < categories.length; pass++) {
            Intent intent = new Intent(Intent.ACTION_MAIN).addCategory(categories[pass]);
            List<ResolveInfo> results = pm.queryIntentActivities(intent, 0);
            for (ResolveInfo result : results) {
                if (result.activityInfo == null || !result.activityInfo.exported) continue;
                String pkg = result.activityInfo.packageName;
                if (pkg.equals(getPackageName()) || found.containsKey(pkg)) continue;
                if (pass == 1 && (result.activityInfo.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                        && !pkg.equals("com.android.vending")) continue;
                App app = new App();
                app.packageName = pkg;
                app.resolve = result;
                app.isLeanback = pass == 0;
                CharSequence label;
                try { label = result.loadLabel(pm); }
                catch (RuntimeException unavailableResource) { label = pkg; }
                app.label = label == null ? pkg : label.toString();
                found.put(pkg, app);
            }
        }
        List<App> result = new ArrayList<App>(found.values());
        Collections.sort(result, Comparator.comparing(a -> a.label.toLowerCase(Locale.getDefault())));
        return result;
    }

    private String fingerprint(List<App> list) {
        StringBuilder out = new StringBuilder();
        for (App app : list) {
            out.append(app.packageName).append(':').append(app.label).append(':')
                    .append(app.resolve.activityInfo.name).append(':').append(app.isLeanback).append(';');
        }
        return out.toString();
    }

    private void readFavorites() {
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        String saved = prefs.getString(FAVORITES, null);
        favorites.clear();
        if (saved == null) favorites.addAll(Arrays.asList(DEFAULT_FAVORITES));
        else if (!saved.isEmpty()) favorites.addAll(Arrays.asList(saved.split(",")));
    }

    private void saveFavorites() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putString(FAVORITES, android.text.TextUtils.join(",", favorites)).apply();
    }

    private int appColor(String pkg) {
        if (pkg.contains("netflix")) return 0xFF080808;
        if (pkg.contains("youtube")) return 0xFFF1F1F1;
        if (pkg.contains("amazonvideo")) return 0xFF132439;
        if (pkg.contains("spotify")) return 0xFF141B18;
        if (pkg.contains("crunchyroll")) return 0xFFF47920;
        if (pkg.contains("rtli")) return 0xFF27202E;
        if (pkg.contains("roblox")) return 0xFF24262C;
        if (pkg.contains("nvidia")) return 0xFF18221A;
        return 0xFF25343F;
    }

    private TextView text(String value, float size, int color) {
        TextView result = new TextView(this);
        result.setText(value);
        result.setTextSize(size);
        result.setTextColor(color);
        result.setIncludeFontPadding(false);
        result.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
        return result;
    }

    private GradientDrawable rounded(int color, float radius, int stroke, int strokeColor) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(radius);
        if (stroke > 0) shape.setStroke(stroke, strokeColor);
        return shape;
    }

    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    private static final class App {
        String packageName;
        String label;
        ResolveInfo resolve;
        boolean isLeanback;
    }

    /** Small static gradients suggest depth without sampling or blurring the screen. */
    static final class GlassSurfaceDrawable extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF shape = new RectF();
        private final RectF inner = new RectF();
        private final float radius;
        private final boolean focused;
        private Shader body;
        private Shader edge;
        private Shader glint;

        GlassSurfaceDrawable(float radius, boolean focused) {
            this.radius = radius;
            this.focused = focused;
        }

        @Override protected void onBoundsChange(android.graphics.Rect bounds) {
            super.onBoundsChange(bounds);
            shape.set(bounds.left + 1f, bounds.top + 1f, bounds.right - 1f, bounds.bottom - 1f);
            inner.set(shape);
            inner.inset(1.6f, 1.6f);
            body = new LinearGradient(shape.left, shape.top, shape.right * .65f, shape.bottom,
                    focused ? new int[]{0xE6ECFAFF, 0xC4D0E7F5, 0xB2ADC9E7}
                            : new int[]{0x49C0EBF5, 0x2698AECF, 0x3A526D94},
                    new float[]{0f, .48f, 1f}, Shader.TileMode.CLAMP);
            edge = new LinearGradient(shape.left, shape.top, shape.right, shape.bottom,
                    focused ? new int[]{0xEFFFFFFF, 0x55DAF5FF, 0xB1D3E4FF}
                            : new int[]{0xA0E8FCFF, 0x16E8F9FF, 0x62C7D6FF},
                    new float[]{0f, .56f, 1f}, Shader.TileMode.CLAMP);
            glint = new LinearGradient(shape.left, 0, shape.right, 0,
                    new int[]{0x00FFFFFF, focused ? 0xDFFFFFFF : 0x9CFFFFFF, 0x00FFFFFF},
                    new float[]{0f, .24f, 1f}, Shader.TileMode.CLAMP);
        }

        @Override public void draw(Canvas canvas) {
            if (shape.isEmpty()) return;
            // The inner stroke changes Paint alpha; reset it for every redraw.
            paint.setAlpha(255);
            paint.setStyle(Paint.Style.FILL);
            paint.setShader(body);
            canvas.drawRoundRect(shape, radius, radius, paint);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(focused ? 1.7f : 1.2f);
            paint.setShader(edge);
            canvas.drawRoundRect(shape, radius, radius, paint);
            paint.setShader(null);
            paint.setStrokeWidth(1f);
            paint.setColor(focused ? 0x40FFFFFF : 0x15FFFFFF);
            canvas.drawRoundRect(inner, Math.max(0f, radius - 1.6f), Math.max(0f, radius - 1.6f), paint);
            paint.setAlpha(255);
            paint.setShader(glint);
            canvas.drawLine(shape.left + radius, shape.top + 1.2f,
                    shape.right - radius, shape.top + 1.2f, paint);
            paint.setShader(null);
            paint.setStyle(Paint.Style.FILL);
        }

        @Override public void getOutline(Outline outline) {
            outline.setRoundRect(getBounds(), radius);
            outline.setAlpha(.45f);
        }
        @Override public void setAlpha(int alpha) { }
        @Override public void setColorFilter(ColorFilter filter) { }
        @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
    }

    /** Transparent gloss preserves the app's original colors and recognizable artwork. */
    private static final class TileGlassDrawable extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF shape = new RectF();
        private final Path reflection = new Path();
        private final float radius;
        private final boolean focused;
        private Shader sheen;
        private Shader edge;

        TileGlassDrawable(float radius, boolean focused) {
            this.radius = radius;
            this.focused = focused;
        }

        @Override protected void onBoundsChange(android.graphics.Rect bounds) {
            super.onBoundsChange(bounds);
            shape.set(bounds.left + 1.1f, bounds.top + 1.1f, bounds.right - 1.1f, bounds.bottom - 1.1f);
            sheen = new LinearGradient(0, shape.top, shape.width() * .18f, shape.bottom,
                    new int[]{focused ? 0x47FFFFFF : 0x21FFFFFF, 0x00FFFFFF, 0x05061E39},
                    new float[]{0f, .48f, 1f}, Shader.TileMode.CLAMP);
            edge = new LinearGradient(shape.left, shape.top, shape.right, shape.bottom,
                    focused ? new int[]{0xFFFFFFFF, 0xA4E7F5FF, 0xE7E5DCFF}
                            : new int[]{0x86FFFFFF, 0x11E8F6FF, 0x44C8D6F5},
                    new float[]{0f, .58f, 1f}, Shader.TileMode.CLAMP);
            reflection.reset();
            reflection.moveTo(shape.left, shape.top);
            reflection.lineTo(shape.right, shape.top);
            reflection.cubicTo(shape.right * .87f, shape.bottom * .18f,
                    shape.width() * .45f, shape.bottom * .15f, shape.left, shape.bottom * .47f);
            reflection.close();
        }

        @Override public void draw(Canvas canvas) {
            paint.setStyle(Paint.Style.FILL);
            paint.setShader(sheen);
            canvas.drawRoundRect(shape, radius, radius, paint);
            paint.setShader(null);
            paint.setColor(focused ? 0x14FFFFFF : 0x08FFFFFF);
            canvas.drawPath(reflection, paint);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(focused ? 2.5f : 1f);
            paint.setShader(edge);
            canvas.drawRoundRect(shape, radius, radius, paint);
            paint.setShader(null);
            paint.setStyle(Paint.Style.FILL);
        }
        @Override public void setAlpha(int alpha) { }
        @Override public void setColorFilter(ColorFilter filter) { }
        @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
    }

    private static final class LandscapeDrawable extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path ribbon = new Path();
        @Override public void draw(Canvas canvas) {
            float w = getBounds().width();
            float h = getBounds().height();
            if (w <= 0 || h <= 0) return;
            paint.setShader(new LinearGradient(0, 0, w, h,
                    new int[]{0xFF214C5C, 0xFF243A60, 0xFF15213C}, null, Shader.TileMode.CLAMP));
            canvas.drawRect(getBounds(), paint);
            paint.setShader(new RadialGradient(w * .07f, h * .12f, w * .60f,
                    new int[]{0xC04DBCA9, 0x3D3A9C9F, 0x003A9C9F},
                    new float[]{0f, .48f, 1f}, Shader.TileMode.CLAMP));
            canvas.drawRect(getBounds(), paint);
            paint.setShader(new RadialGradient(w * .89f, h * .13f, w * .53f,
                    new int[]{0xBB9A8EC9, 0x355A66B6, 0x005A66B6},
                    new float[]{0f, .55f, 1f}, Shader.TileMode.CLAMP));
            canvas.drawRect(getBounds(), paint);
            ribbon.reset();
            ribbon.moveTo(-w * .08f, h * .75f);
            ribbon.cubicTo(w * .18f, -h * .05f, w * .64f, h * .83f, w * 1.08f, h * .12f);
            ribbon.lineTo(w * 1.08f, h * .45f);
            ribbon.cubicTo(w * .57f, h * .98f, w * .27f, h * .24f, -w * .08f, h * .96f);
            ribbon.close();
            paint.setShader(new LinearGradient(0, h * .20f, w, h * .83f,
                    new int[]{0x357DE4CC, 0x1E83B3DC, 0x1ABCB4F3}, null, Shader.TileMode.CLAMP));
            canvas.drawPath(ribbon, paint);
            paint.setShader(new RadialGradient(w * .28f, h * .92f, w * .43f,
                    new int[]{0x663087A0, 0x003087A0}, null, Shader.TileMode.CLAMP));
            canvas.drawRect(getBounds(), paint);
            paint.setShader(new LinearGradient(0, h * .20f, 0, h,
                    new int[]{0x00081529, 0xA60B152C}, null, Shader.TileMode.CLAMP));
            canvas.drawRect(getBounds(), paint);
            paint.setShader(null);
        }
        @Override public void setAlpha(int alpha) { }
        @Override public void setColorFilter(ColorFilter filter) { }
        @Override public int getOpacity() { return PixelFormat.OPAQUE; }
    }
}
