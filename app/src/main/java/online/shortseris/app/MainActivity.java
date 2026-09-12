package online.shortseris.app;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.util.Locale;

public class MainActivity extends Activity {
    static final String BASE = "https://shortseris.online";
    WebView web;
    ProgressBar progress;
    LinearLayout topBar, bottomBar;
    FrameLayout fullscreen;
    View customView;
    String lang;

    final int bg = Color.rgb(7,8,12);
    final int surface = Color.rgb(13,17,24);
    final int text = Color.rgb(247,249,252);
    final int muted = Color.rgb(154,164,180);

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        lang = Locale.getDefault().getLanguage().equals("ar") ? "ar" : "en";
        getWindow().setStatusBarColor(bg);
        getWindow().setNavigationBarColor(bg);
        buildUi();
        setupWeb();
        if (state != null) web.restoreState(state);
        else web.loadUrl(launchUrl(getIntent()));
    }

    void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(bg);

        topBar = new LinearLayout(this);
        topBar.setGravity(Gravity.CENTER_VERTICAL);
        topBar.setPadding(dp(12),dp(6),dp(8),dp(6));
        topBar.setBackgroundColor(surface);
        root.addView(topBar,new LinearLayout.LayoutParams(-1,dp(58)));

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.brand_logo);
        logo.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        topBar.addView(logo,new LinearLayout.LayoutParams(dp(42),dp(42)));

        TextView title = new TextView(this);
        title.setText("SHORT SERIES"); title.setTextColor(text); title.setTextSize(16); title.setTypeface(title.getTypeface(),1);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(0,-2,1f); tlp.setMargins(dp(8),0,dp(6),0);
        topBar.addView(title,tlp);

        ImageButton search = new ImageButton(this);
        search.setImageResource(R.drawable.ic_search); search.setColorFilter(text); search.setBackgroundColor(Color.TRANSPARENT);
        search.setOnClickListener(v -> loadPath("/search"));
        topBar.addView(search,new LinearLayout.LayoutParams(dp(44),dp(44)));

        Button language = new Button(this);
        language.setText(lang.equals("ar")?"EN":"AR"); language.setTextColor(text); language.setTextSize(11); language.setAllCaps(false);
        language.setOnClickListener(v -> { lang=lang.equals("ar")?"en":"ar"; language.setText(lang.equals("ar")?"EN":"AR"); rebuildBottom(); loadPath(""); });
        topBar.addView(language,new LinearLayout.LayoutParams(dp(48),dp(42)));

        FrameLayout body = new FrameLayout(this);
        root.addView(body,new LinearLayout.LayoutParams(-1,0,1f));
        web = new WebView(this); web.setBackgroundColor(bg); body.addView(web,new FrameLayout.LayoutParams(-1,-1));
        progress = new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); progress.setMax(100); body.addView(progress,new FrameLayout.LayoutParams(-1,dp(3),Gravity.TOP));
        fullscreen = new FrameLayout(this); fullscreen.setBackgroundColor(Color.BLACK); fullscreen.setVisibility(View.GONE); body.addView(fullscreen,new FrameLayout.LayoutParams(-1,-1));

        bottomBar = new LinearLayout(this); bottomBar.setGravity(Gravity.CENTER); bottomBar.setBackgroundColor(surface);
        root.addView(bottomBar,new LinearLayout.LayoutParams(-1,dp(66))); rebuildBottom();
        setContentView(root);
    }

    void setupWeb() {
        WebSettings s=web.getSettings();
        s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setDatabaseEnabled(true); s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE); s.setUseWideViewPort(true); s.setLoadWithOverviewMode(true);
        CookieManager.getInstance().setAcceptCookie(true); CookieManager.getInstance().setAcceptThirdPartyCookies(web,true);
        web.setWebViewClient(new AppWebClient(this)); web.setWebChromeClient(new AppChromeClient(this));
    }

    void rebuildBottom() {
        bottomBar.removeAllViews(); boolean ar=lang.equals("ar");
        nav(R.drawable.ic_home,ar?"الرئيسية":"Home",""); nav(R.drawable.ic_movies,ar?"أفلام":"Movies","/movies"); nav(R.drawable.ic_series,ar?"مسلسلات":"Series","/series"); nav(R.drawable.ic_shorts,ar?"قصيرة":"Shorts","/short-series"); nav(R.drawable.ic_tv,ar?"تلفاز":"TV","/tv");
    }

    void nav(int icon,String label,String path) {
        LinearLayout item=new LinearLayout(this); item.setOrientation(LinearLayout.VERTICAL); item.setGravity(Gravity.CENTER);
        ImageView iv=new ImageView(this); iv.setImageResource(icon); iv.setColorFilter(text); item.addView(iv,new LinearLayout.LayoutParams(dp(23),dp(23)));
        TextView tv=new TextView(this); tv.setText(label); tv.setTextColor(muted); tv.setTextSize(9); tv.setGravity(Gravity.CENTER); item.addView(tv,new LinearLayout.LayoutParams(-1,-2));
        item.setOnClickListener(v -> loadPath(path)); bottomBar.addView(item,new LinearLayout.LayoutParams(0,-1,1f));
    }

    void loadPath(String path) { web.loadUrl(BASE+"/"+lang+path); }
    String launchUrl(Intent intent) { if(intent!=null&&Intent.ACTION_VIEW.equals(intent.getAction())&&intent.getData()!=null)return intent.getData().toString(); return BASE+"/"+lang; }
    int dp(int v){return Math.round(v*getResources().getDisplayMetrics().density);}

    boolean online(){ ConnectivityManager cm=(ConnectivityManager)getSystemService(Context.CONNECTIVITY_SERVICE); if(cm==null)return false; if(Build.VERSION.SDK_INT>=23){NetworkCapabilities c=cm.getNetworkCapabilities(cm.getActiveNetwork()); return c!=null&&c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);} android.net.NetworkInfo i=cm.getActiveNetworkInfo(); return i!=null&&i.isConnected(); }

    void showFullscreen(View v){ customView=v; fullscreen.addView(v,new FrameLayout.LayoutParams(-1,-1)); fullscreen.setVisibility(View.VISIBLE); web.setVisibility(View.GONE); topBar.setVisibility(View.GONE); bottomBar.setVisibility(View.GONE); getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); }
    void hideFullscreen(){ if(customView==null)return; fullscreen.removeAllViews(); fullscreen.setVisibility(View.GONE); customView=null; web.setVisibility(View.VISIBLE); topBar.setVisibility(View.VISIBLE); bottomBar.setVisibility(View.VISIBLE); getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); }

    @Override public void onBackPressed(){ if(customView!=null)hideFullscreen(); else if(web.canGoBack())web.goBack(); else super.onBackPressed(); }
    @Override protected void onSaveInstanceState(Bundle out){web.saveState(out);super.onSaveInstanceState(out);}
}
