package com.egytube.rebuilt;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.content.SharedPreferences;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.*;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import androidx.work.WorkManager;
import androidx.work.WorkInfo;
import androidx.work.Data;
import androidx.work.OneTimeWorkRequest;
import androidx.work.Constraints;
import androidx.work.NetworkType;
import java.util.UUID;

import org.json.JSONArray;
import org.json.JSONObject;
import org.schabi.newpipe.extractor.InfoItem;
import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.search.SearchInfo;
import org.schabi.newpipe.extractor.stream.StreamInfoItem;

import java.net.HttpURLConnection;
import java.net.URL;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.*;

public class MainActivity extends Activity {
  private static final String[] TABS={"الرئيسية","الاشتراكات","المكتبة","حسابي"};
  private static final String APP_PAGE="https://egyshow.com/egytube/";
  private static final String OFFICIAL_UPDATE_JSON=APP_PAGE+"latest.json";
  private static final String FALLBACK_UPDATE_JSON=
    "https://raw.githubusercontent.com/facemasr/ShortSeriesAndroid/egytube-v083-download-stability/public-downloads/latest.json";
  private static final String[] ICONS={"⌂","▣","▤","◉"};
  // Existing page identifiers remain stable, only Shorts is removed from navigation.
  private static final int[] TAB_PAGE_IDS={0,2,3,4};
  private final int WHITE=0xffffffff, DARK=0xff171717, RED=0xffe62135, GREY=0xff696969, LIGHT=0xfff4f4f4;
  private final ExecutorService pool=Executors.newFixedThreadPool(5);
  private final Map<String,Bitmap> images=Collections.synchronizedMap(new LinkedHashMap<>());
  private final ArrayList<Video> list=new ArrayList<>();
  private final LinkedHashMap<String,Video> knownVideos=new LinkedHashMap<>();
  private LinearLayout app,feed,bottom;
  private FrameLayout shell;
  private NativeWatchView watchView;
  private EditText searchInput;
  private ScrollView scroll;
  private LinearLayout miniBar;
  private FrameLayout miniVideoHost;
  private View miniVideoTap;
  private TextView miniTitle,miniPlay;
  private boolean miniVisible=false;
  private boolean restoreMiniAfterPip=false;
  private SharedPreferences prefs;
  private int selected=0,requestId=0;
  private String currentQuery="";
  private boolean loading=false,loadingNextPage=false,manualRetryNeeded=false;
  private int displayedVideoCount=0,emptyPageCount=0;
  private org.schabi.newpipe.extractor.Page nextSearchPage;
  private final LinkedHashSet<String> currentVideoIds=new LinkedHashSet<>();
  private TextView pageStatus;
  private static final int CHOOSE_DOWNLOAD_FOLDER=902;
  private String[] pendingDownload;
  private boolean downloadsVisible=false;
  private int downloadsScreenToken=0;
  private LinearLayout downloadItems;
  private final Handler downloadsUi=new Handler(Looper.getMainLooper());
  private final Runnable downloadsRefresh=new Runnable(){
    @Override public void run(){
      if(!downloadsVisible||isFinishing()||isDestroyed())return;
      renderDownloadItems();
      downloadsUi.postDelayed(this,2400);
    }
  };

  static class Video {
    String title,url,id,image,uploader,uploaderUrl;
    long duration;
    Video(String t,String u,String img,String author,String authorUrl,long seconds) {
      title=t;url=u;id=idFrom(u);image=img;uploader=author;uploaderUrl=authorUrl;duration=seconds;
    }
    JSONObject json() {
      JSONObject o=new JSONObject();
      try{o.put("title",title);o.put("url",url);o.put("image",image);o.put("uploader",uploader);o.put("uploaderUrl",uploaderUrl);o.put("duration",duration);}
      catch(Exception ignored){}
      return o;
    }
    static Video parse(JSONObject o){
      return new Video(o.optString("title"),o.optString("url"),o.optString("image"),o.optString("uploader"),o.optString("uploaderUrl"),o.optLong("duration",0));
    }
  }
  static String idFrom(String u){
    if(u==null)return null;
    Matcher m=Pattern.compile("(?:[?&]v=|youtu\\.be/|/shorts/|/embed/)([A-Za-z0-9_-]{11})").matcher(u);
    if(m.find())return m.group(1);
    return u.matches("[A-Za-z0-9_-]{11}")?u:null;
  }
  private int dp(int n){return (int)(getResources().getDisplayMetrics().density*n+.5f);}
  private GradientDrawable background(int color,int round){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(round));return d;}
  private TextView text(String s,int size,int color,boolean bold){
    TextView t=new TextView(this);t.setText(s);t.setTextColor(color);t.setTextSize(size);
    if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
    t.setGravity(Gravity.CENTER_VERTICAL);return t;
  }
  private LinearLayout linear(int orientation){LinearLayout l=new LinearLayout(this);l.setOrientation(orientation);return l;}
  private void pad(View v,int a,int b,int c,int d){v.setPadding(dp(a),dp(b),dp(c),dp(d));}
  @Override public void onCreate(Bundle saved){
    super.onCreate(saved);
    prefs=getSharedPreferences("EGYTUBE_ONLY",MODE_PRIVATE);
    getWindow().setStatusBarColor(WHITE);getWindow().setNavigationBarColor(WHITE);
    getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    try{NewPipe.init(new HttpDownloader());}catch(Exception ignored){}
    app=linear(LinearLayout.VERTICAL);app.setBackgroundColor(WHITE);app.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
    shell=new FrameLayout(this);shell.addView(app,new FrameLayout.LayoutParams(-1,-1));setContentView(shell);
    setupHeader();
    scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setVerticalScrollBarEnabled(false);
    feed=linear(LinearLayout.VERTICAL);scroll.addView(feed);app.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
    scroll.setOnScrollChangeListener((View view,int sx,int sy,int oldX,int oldY)->{
      // Prefetch while the user is near the bottom; no polling or concurrent loads.
      if(sy>oldY && feed.getHeight()-sy-scroll.getHeight()<dp(780))loadNextPage();
    });
    setupMiniPlayer();
    bottom=linear(LinearLayout.HORIZONTAL);bottom.setBackgroundColor(WHITE);pad(bottom,4,4,4,5);
    app.addView(bottom,new LinearLayout.LayoutParams(-1,dp(61)));
    View line=new View(this);line.setBackgroundColor(0xffeeeeee);app.addView(line,new LinearLayout.LayoutParams(-1,dp(1)));
    String shared=getIntent()==null?null:getIntent().getStringExtra(Intent.EXTRA_TEXT);
    show(0);
    if(shared!=null&&idFrom(shared)!=null)play(new Video("فيديو يوتيوب",shared,"","","",0));
    else restoreWatchAfterBackground();
    checkAppUpdate(false);
  }
  private void setupMiniPlayer(){
    miniBar=linear(LinearLayout.HORIZONTAL);
    miniBar.setGravity(Gravity.CENTER_VERTICAL);
    miniBar.setBackgroundColor(0xff171a20);
    miniBar.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
    miniBar.setElevation(dp(5));
    miniBar.setVisibility(View.GONE);
    miniBar.setContentDescription("مشغّل مصغّر للفيديو الحالي");
    miniVideoHost=new FrameLayout(this);
    miniVideoHost.setBackgroundColor(Color.BLACK);
    miniVideoTap=new View(this);
    miniVideoTap.setContentDescription("فتح مشغّل الفيديو الكامل");
    miniVideoTap.setClickable(true);
    miniVideoTap.setOnClickListener(v->expandMiniPlayer());
    miniBar.addView(miniVideoHost,new LinearLayout.LayoutParams(dp(130),dp(73)));
    LinearLayout info=linear(LinearLayout.VERTICAL);
    info.setGravity(Gravity.CENTER_VERTICAL);
    pad(info,10,3,11,3);
    miniTitle=text("",14,WHITE,true);
    miniTitle.setMaxLines(2);
    miniTitle.setEllipsize(TextUtils.TruncateAt.END);
    info.addView(miniTitle);
    TextView helper=text("انقر للعودة إلى المشغّل",11,0xffaab0bc,false);
    info.addView(helper);
    miniBar.addView(info,new LinearLayout.LayoutParams(0,dp(73),1));
    info.setOnClickListener(v->expandMiniPlayer());
    miniPlay=text("Ⅱ",23,WHITE,true);
    miniPlay.setGravity(Gravity.CENTER);
    miniPlay.setContentDescription("تشغيل أو إيقاف الفيديو مؤقتًا");
    miniBar.addView(miniPlay,new LinearLayout.LayoutParams(dp(43),dp(73)));
    miniPlay.setOnClickListener(v->{
      if(watchView!=null)watchView.toggleMiniPlayback();
    });
    TextView close=text("×",29,WHITE,false);
    close.setGravity(Gravity.CENTER);
    close.setContentDescription("إغلاق الفيديو المصغّر");
    miniBar.addView(close,new LinearLayout.LayoutParams(dp(43),dp(73)));
    close.setOnClickListener(v->closeWatch());
    miniBar.setOnClickListener(v->expandMiniPlayer());
    app.addView(miniBar,new LinearLayout.LayoutParams(-1,dp(73)));
  }
  void onMiniPlaybackChanged(boolean playing){
    if(miniPlay!=null)miniPlay.setText(playing?"Ⅱ":"▶");
  }
  private void dockMiniPlayer(){
    if(watchView==null || miniVisible || !watchView.hasVideo())return;
    if(watchView.isFullScreen())watchView.exitFullScreen();
    miniTitle.setText(watchView.currentVideoTitle());
    watchView.dockIntoMini(miniVideoHost);
    miniVideoHost.bringChildToFront(miniVideoTap);
    if(miniVideoTap.getParent()!=miniVideoHost){
      miniVideoHost.addView(miniVideoTap,new FrameLayout.LayoutParams(-1,-1));
    }
    miniVideoTap.bringToFront();
    miniVisible=true;
    miniBar.setVisibility(View.VISIBLE);
    watchView.setVisibility(View.GONE);
    onMiniPlaybackChanged(watchView.isPlayingVideo());
    getWindow().getDecorView().setSystemUiVisibility(
      View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    getWindow().setStatusBarColor(WHITE);
    getWindow().setNavigationBarColor(WHITE);
  }
  private void expandMiniPlayer(){
    if(watchView==null || !miniVisible)return;
    miniVisible=false;
    watchView.setVisibility(View.VISIBLE);
    watchView.restoreFromMini();
    miniBar.setVisibility(View.GONE);
  }
  void prepareWatchForPip(){
    if(miniVisible){
      restoreMiniAfterPip=true;
      expandMiniPlayer();
    }
  }
  private void setupHeader(){
    LinearLayout h=linear(LinearLayout.HORIZONTAL);h.setGravity(Gravity.CENTER_VERTICAL);pad(h,15,7,12,6);
    ImageView logo=new ImageView(this);logo.setImageResource(R.drawable.ic_app);
    logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
    h.addView(logo,new LinearLayout.LayoutParams(dp(36),dp(43)));
    TextView title=text("EGYTUBE",23,DARK,true);title.setSingleLine(true);
    android.text.SpannableString brand=new android.text.SpannableString("EGYTUBE");
    brand.setSpan(new android.text.style.ForegroundColorSpan(RED),3,7,0);
    title.setText(brand);
    title.setLetterSpacing(0.015f);
    LinearLayout.LayoutParams titleLp=new LinearLayout.LayoutParams(0,dp(46),1);
    titleLp.rightMargin=dp(6);
    h.addView(title,titleLp);
    TextView cast=text("▣",21,GREY,false);cast.setGravity(Gravity.CENTER);
    cast.setContentDescription("تحديث النتائج");
    h.addView(cast,new LinearLayout.LayoutParams(dp(39),dp(46)));
    cast.setOnClickListener(v->show(selected==5?0:selected));
    TextView find=text("⌕",27,DARK,true);find.setGravity(Gravity.CENTER);
    h.addView(find,new LinearLayout.LayoutParams(dp(41),dp(46)));
    find.setOnClickListener(v->show(5));
    TextView account=text("◉",22,DARK,true);account.setGravity(Gravity.CENTER);
    account.setBackground(background(0xfff4f4f4,24));
    LinearLayout.LayoutParams alp=new LinearLayout.LayoutParams(dp(37),dp(37));alp.leftMargin=dp(4);
    h.addView(account,alp);account.setOnClickListener(v->show(4));
    account.setContentDescription("الملف الشخصي");
    app.addView(h);
  }
  private void askLink(){
    EditText field=new EditText(this);field.setHint("https://youtu.be/...");field.setSingleLine(true);pad(field,16,6,16,6);
    new AlertDialog.Builder(this).setTitle("رابط فيديو").setView(field).setPositiveButton("تشغيل",(d,w)->{
      String u=field.getText().toString().trim();if(idFrom(u)!=null)play(new Video("فيديو يوتيوب",u,"","","",0));else notice("الرابط ليس رابط فيديو يوتيوب صالحًا");
    }).setNegativeButton("إلغاء",null).show();
  }
  private void buildNav(){
    bottom.removeAllViews();
    bottom.setBackgroundColor(WHITE);
    bottom.setElevation(dp(4));
    for(int i=0;i<TABS.length;i++){
      final int tab=TAB_PAGE_IDS[i];
      final boolean active=tab==selected;
      LinearLayout wrap=linear(LinearLayout.VERTICAL);
      wrap.setGravity(Gravity.CENTER);
      wrap.setContentDescription(TABS[i]);
      TextView glyph=text(ICONS[i],24,active?RED:GREY,active);
      glyph.setGravity(Gravity.CENTER);
      if(active)glyph.setBackground(background(0xffffeef0,22));
      wrap.addView(glyph,new LinearLayout.LayoutParams(dp(59),dp(32)));
      TextView label=text(TABS[i],12,active?DARK:GREY,active);
      label.setGravity(Gravity.CENTER);
      LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(22));
      lp.topMargin=dp(2);
      wrap.addView(label,lp);
      bottom.addView(wrap,new LinearLayout.LayoutParams(0,-1,1));
      wrap.setOnClickListener(v->show(tab));
    }
  }
  private void show(int tab){
    downloadsVisible=false;
    downloadsUi.removeCallbacks(downloadsRefresh);
    selected=tab;requestId++;resetSearchState();buildNav();feed.removeAllViews();list.clear();currentQuery="";
    scroll.smoothScrollTo(0,0);
    if(tab==0){
      addHeading("اكتشف فيديوهات تناسبك");
      load("مقاطع فيديو جديدة 2026",false,requestId);
    }else if(tab==2)subscriptionsScreen();
    else if(tab==3)libraryScreen();
    else if(tab==4)profileScreen();
    else searchScreen();
  }
  private void resetSearchState(){
    loading=false;loadingNextPage=false;manualRetryNeeded=false;
    displayedVideoCount=0;emptyPageCount=0;
    nextSearchPage=null;pageStatus=null;currentVideoIds.clear();
  }
  private void addHeading(String label){
    TextView h=text(label,21,DARK,true);
    h.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
    pad(h,16,14,16,8);feed.addView(h);
  }
  private void addSubheading(String label){
    TextView h=text(label,18,DARK,true);
    h.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
    pad(h,16,18,16,9);feed.addView(h);
  }
  private TextView actionChip(String value,Runnable action){
    TextView t=text(value,14,DARK,true);t.setGravity(Gravity.CENTER);
    t.setBackground(background(LIGHT,19));pad(t,15,9,15,9);
    t.setOnClickListener(v->action.run());return t;
  }
  private void categoryChips(){
    HorizontalScrollView lane=new HorizontalScrollView(this);lane.setHorizontalScrollBarEnabled(false);
    LinearLayout row=linear(LinearLayout.HORIZONTAL);pad(row,14,1,14,2);
    String[][] categories={{"الكل","مقاطع فيديو جديدة 2026"},{"موسيقى","موسيقى عربية جديدة"},
      {"أفلام","مقاطع أفلام"},{"تقنية","أحدث التقنية"},{"رياضة","ملخص مباريات"},
      {"ألعاب","ألعاب فيديو"},{"تعليم","تعلم مهارات جديدة"}};
    for(String[] category:categories){
      TextView chip=actionChip(category[0],()->queryVideos(category[1],false));
      LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-2,dp(42));lp.leftMargin=dp(8);
      row.addView(chip,lp);
    }
    lane.addView(row);feed.addView(lane);
  }
  private void queryVideos(String q,boolean shorts){
    selected=5;buildNav();requestId++;resetSearchState();feed.removeAllViews();list.clear();
    currentQuery=q;
    addHeading("نتائج البحث: "+q);
    load(q,false,requestId);
  }
  private void hero(Video video){
    if(video.image==null||video.image.isEmpty())return;
    FrameLayout banner=new FrameLayout(this);
    banner.setBackground(background(0xff1e1e1e,20));
    banner.setClipToOutline(true);
    ImageView cover=new ImageView(this);
    cover.setScaleType(ImageView.ScaleType.CENTER_CROP);
    banner.addView(cover,new FrameLayout.LayoutParams(-1,-1));
    showImage(video.image,cover);
    android.graphics.drawable.GradientDrawable shade=new android.graphics.drawable.GradientDrawable(
      android.graphics.drawable.GradientDrawable.Orientation.BOTTOM_TOP,
      new int[]{0xe6000000,0x10000000}
    );
    View overlay=new View(this);overlay.setBackground(shade);
    banner.addView(overlay,new FrameLayout.LayoutParams(-1,-1));
    LinearLayout copy=linear(LinearLayout.VERTICAL);pad(copy,18,8,18,15);
    TextView featured=text("▶  فيديو مميز",13,WHITE,true);
    TextView headline=text(video.title,21,WHITE,true);
    headline.setMaxLines(2);
    TextView name=text(video.uploader+"  ·  شاهد الآن",13,0xffeeeeee,false);
    copy.addView(featured);copy.addView(headline);copy.addView(name);
    FrameLayout.LayoutParams textLp=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);
    banner.addView(copy,textLp);
    FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(-1,dp(196));
    LinearLayout.LayoutParams rowLp=new LinearLayout.LayoutParams(-1,dp(196));
    rowLp.setMargins(dp(13),dp(7),dp(13),dp(9));
    feed.addView(banner,rowLp);
    banner.setOnClickListener(v->play(video));
  }
  private void remember(Video video){
    if(video==null || video.url==null || video.url.isEmpty())return;
    knownVideos.remove(video.url);
    knownVideos.put(video.url,video);
    while(knownVideos.size()>130)knownVideos.remove(knownVideos.keySet().iterator().next());
  }
  private ArrayList<Video> collection(String kind,int limit){
    ArrayList<Video> results=new ArrayList<>();
    JSONArray arr=new JSONArray();
    try{arr=new JSONArray(prefs.getString(kind,"[]"));}catch(Exception ignored){}
    for(int i=0;i<arr.length()&&results.size()<limit;i++){
      JSONObject obj=arr.optJSONObject(i);
      if(obj!=null)results.add(Video.parse(obj));
    }
    return results;
  }
  private TextView circleAvatar(String value,int diameter){
    String letter=(value==null||value.trim().isEmpty())?"▶":value.trim().substring(0,1);
    TextView avatar=text(letter,23,RED,true);avatar.setGravity(Gravity.CENTER);
    GradientDrawable bg=background(0xfffaf0f1,diameter);
    bg.setStroke(dp(2),RED);
    avatar.setBackground(bg);
    return avatar;
  }
  private void sectionHead(String title,Runnable action){
    LinearLayout bar=linear(LinearLayout.HORIZONTAL);bar.setGravity(Gravity.CENTER_VERTICAL);
    pad(bar,14,8,14,8);
    TextView heading=text(title,21,DARK,true);
    heading.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
    bar.addView(heading,new LinearLayout.LayoutParams(0,dp(42),1));
    if(action!=null){
      TextView all=text("عرض الكل ‹",13,RED,true);
      all.setGravity(Gravity.LEFT|Gravity.CENTER_VERTICAL);
      bar.addView(all,new LinearLayout.LayoutParams(dp(100),dp(42)));
      all.setOnClickListener(v->action.run());
    }
    feed.addView(bar);
  }
  private View miniCard(Video video,int width){
    LinearLayout card=linear(LinearLayout.VERTICAL);
    int w=dp(width),h=(int)(w*9.0/16);
    FrameLayout cover=new FrameLayout(this);
    cover.setBackground(background(LIGHT,13));cover.setClipToOutline(true);
    ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    cover.addView(image,new FrameLayout.LayoutParams(-1,-1));showImage(video.image,image);
    if(video.duration>0){
      TextView duration=text(formatted(video.duration),12,WHITE,true);
      duration.setBackground(background(0xcc000000,6));pad(duration,4,1,4,1);
      FrameLayout.LayoutParams t=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.RIGHT);
      t.setMargins(0,0,dp(6),dp(7));cover.addView(duration,t);
    }
    card.addView(cover,new LinearLayout.LayoutParams(w,h));
    TextView title=text(video.title,13,DARK,true);
    title.setMaxLines(2);title.setEllipsize(TextUtils.TruncateAt.END);
    pad(title,3,6,3,2);card.addView(title,new LinearLayout.LayoutParams(w,dp(45)));
    TextView maker=text(video.uploader,12,GREY,false);pad(maker,3,0,3,2);
    maker.setSingleLine(true);maker.setEllipsize(TextUtils.TruncateAt.END);
    card.addView(maker,new LinearLayout.LayoutParams(w,dp(22)));
    cover.setOnClickListener(v->play(video));
    card.setOnClickListener(v->play(video));
    card.setOnLongClickListener(v->{menu(video);return true;});
    return card;
  }
  private void horizontalRail(java.util.List<Video> videos,int width){
    if(videos.isEmpty())return;
    HorizontalScrollView scrollX=new HorizontalScrollView(this);
    scrollX.setHorizontalScrollBarEnabled(false);
    LinearLayout row=linear(LinearLayout.HORIZONTAL);pad(row,13,3,13,9);
    for(Video video:videos){
      View tile=miniCard(video,width);
      LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(width),-2);
      lp.leftMargin=dp(11);row.addView(tile,lp);
    }
    scrollX.addView(row);feed.addView(scrollX);
  }
  private void compactRow(Video video){
    LinearLayout row=linear(LinearLayout.HORIZONTAL);pad(row,13,7,13,8);
    row.setGravity(Gravity.CENTER_VERTICAL);
    LinearLayout info=linear(LinearLayout.VERTICAL);pad(info,7,0,7,0);
    TextView title=text(video.title,15,DARK,true);title.setMaxLines(3);
    title.setEllipsize(TextUtils.TruncateAt.END);
    info.addView(title);
    TextView subtitle=text(video.uploader,12,GREY,false);pad(subtitle,0,7,0,0);
    info.addView(subtitle);
    TextView menu=text("⋮",24,DARK,true);menu.setGravity(Gravity.CENTER);
    row.addView(menu,new LinearLayout.LayoutParams(dp(28),dp(90)));
    menu.setOnClickListener(v->menu(video));
    row.addView(info,new LinearLayout.LayoutParams(0,-2,1));
    FrameLayout photo=new FrameLayout(this);
    photo.setBackground(background(LIGHT,12));photo.setClipToOutline(true);
    ImageView img=new ImageView(this);img.setScaleType(ImageView.ScaleType.CENTER_CROP);
    photo.addView(img,new FrameLayout.LayoutParams(-1,-1));showImage(video.image,img);
    if(video.duration>0){
      TextView dur=text(formatted(video.duration),12,WHITE,true);
      dur.setBackground(background(0xc9000000,5));pad(dur,3,1,3,1);
      FrameLayout.LayoutParams durationLp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.RIGHT);
      durationLp.bottomMargin=dp(5);durationLp.rightMargin=dp(5);
      photo.addView(dur,durationLp);
    }
    row.addView(photo,new LinearLayout.LayoutParams(dp(152),dp(91)));
    row.setOnClickListener(v->play(video));
    feed.addView(row);
    View div=new View(this);div.setBackgroundColor(0xfff4f4f4);
    feed.addView(div,new LinearLayout.LayoutParams(-1,dp(1)));
  }
  private void notice(String s){new AlertDialog.Builder(this).setMessage(s).setPositiveButton("موافق",null).show();}
  private void placeholder(String s){
    TextView t=text(s,14,GREY,false);pad(t,18,14,18,14);feed.addView(t);
  }
  private void searchScreen(){
    addHeading("ابحث في EGYTUBE");
    LinearLayout line=linear(LinearLayout.HORIZONTAL);pad(line,14,8,14,8);
    searchInput=new EditText(this);searchInput.setSingleLine(true);searchInput.setTextSize(16);
    searchInput.setHint("ابحث عن فيديو، قناة أو رابط");
    searchInput.setBackground(background(LIGHT,17));
    searchInput.setImeOptions(EditorInfo.IME_ACTION_SEARCH);pad(searchInput,15,4,15,4);
    line.addView(searchInput,new LinearLayout.LayoutParams(0,dp(52),1));
    TextView go=text("⌕",27,WHITE,true);go.setGravity(Gravity.CENTER);go.setBackground(background(RED,16));
    LinearLayout.LayoutParams gp=new LinearLayout.LayoutParams(dp(53),dp(52));gp.leftMargin=dp(9);
    line.addView(go,gp);feed.addView(line);
    go.setOnClickListener(v->startSearch());
    searchInput.setOnEditorActionListener((v,a,e)->{
      if(a==EditorInfo.IME_ACTION_SEARCH){startSearch();return true;}return false;
    });
    addSubheading("بحث سريع");
    categoryChips();
    String recent=prefs.getString("search_terms","");
    if(!recent.trim().isEmpty()){
      addSubheading("عمليات البحث الأخيرة");
      for(String term:recent.split("\\n")){
        if(term.isEmpty())continue;
        TextView item=actionChip("◷  "+term,()->queryVideos(term,false));
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(47));
        lp.setMargins(dp(14),0,dp(14),dp(8));feed.addView(item,lp);
      }
    }
    placeholder("نتائج حقيقية من يوتيوب، بدون تسجيل دخول.");
  }
  private void startSearch(){
    String q=searchInput==null?"":searchInput.getText().toString().trim();
    if(q.isEmpty()){if(searchInput!=null)searchInput.setError("أدخل كلمات البحث");return;}
    String id=idFrom(q);if(id!=null){play(new Video("يوتيوب",q,"","","",0));return;}
    String existing=prefs.getString("search_terms","");
    LinkedHashSet<String> terms=new LinkedHashSet<>();terms.add(q);
    terms.addAll(Arrays.asList(existing.split("\\n")));
    ArrayList<String> clean=new ArrayList<>();for(String term:terms)
      if(term!=null&&!term.trim().isEmpty()&&clean.size()<10)clean.add(term);
    prefs.edit().putString("search_terms",TextUtils.join("\n",clean)).apply();
    queryVideos(q,false);
  }

  // NewPipeExtractor v0.26.5 uses SearchInfo.getNextPage() and
  // SearchInfo.getMoreItems(service, queryHandler, page) for real continuation.
  private ArrayList<Video> playableResults(java.util.List<InfoItem> items){
    ArrayList<Video> result=new ArrayList<>();
    if(items==null)return result;
    for(InfoItem item:items){
      if(!(item instanceof StreamInfoItem))continue;
      StreamInfoItem video=(StreamInfoItem)item;
      if(video.getStreamType()!=null &&
         video.getStreamType().name().toUpperCase(Locale.ROOT).contains("LIVE"))continue;
      Video candidate=new Video(video.getName(),video.getUrl(),
        video.getThumbnails().isEmpty()?"":video.getThumbnails().get(0).getUrl(),
        video.getUploaderName(),video.getUploaderUrl(),video.getDuration());
      if(candidate.id!=null)result.add(candidate);
    }
    return result;
  }
  private void addUniqueVideos(ArrayList<Video> rows,boolean firstPage){
    ArrayList<Video> unique=new ArrayList<>();
    for(Video video:rows){
      if(video.id==null || !currentVideoIds.add(video.id))continue;
      unique.add(video);list.add(video);remember(video);
    }
    if(firstPage && selected==0){
      if(!unique.isEmpty())hero(unique.get(0));
      if(unique.size()>1){
        sectionHead("مقترحة لك",()->queryVideos("فيديوهات متنوعة",false));
        horizontalRail(unique.subList(1,Math.min(unique.size(),6)),176);
      }
      ArrayList<Video> watched=collection("history",12);
      if(!watched.isEmpty()){
        sectionHead("متابعة المشاهدة",()->show(3));
        horizontalRail(watched,175);
      }
      sectionHead("أحدث الفيديوهات",null);
    }
    for(int i=0;i<unique.size();i++){
      Video video=unique.get(i);
      // The first video is featured and the next five appear in the horizontal
      // row, so don't repeat their cards below on the home screen.
      if(!(firstPage && selected==0 && i<6)){
        if(selected==0 && displayedVideoCount<4)addCard(video,false);
        else compactRow(video);
      }
      displayedVideoCount++;
      if(displayedVideoCount==8)addAd(AdSlots.NATIVE_300x250);
      else if(displayedVideoCount==14)addAd(AdSlots.AADS_320x100);
      else if(displayedVideoCount==20)addAd(AdSlots.NETWORK_WIDE_468x60);
      else if(displayedVideoCount==27)addAd(AdSlots.NETWORK_SCRIPT);
      else if(displayedVideoCount==34)addAd(AdSlots.SPONSORED_LINK);
      else if(displayedVideoCount>35 && displayedVideoCount%45==0)
        addAd(AdSlots.BONEPA_4);
    }
    if(unique.isEmpty())emptyPageCount++;
    else emptyPageCount=0;
  }
  private void setPageStatus(String text,boolean tappable){
    if(pageStatus!=null){
      feed.removeView(pageStatus);
      pageStatus=null;
    }
    if(text==null || text.isEmpty())return;
    pageStatus=text(text,14,tappable?RED:GREY,tappable);
    pageStatus.setGravity(Gravity.CENTER);
    pad(pageStatus,14,18,14,23);
    feed.addView(pageStatus,new LinearLayout.LayoutParams(-1,dp(66)));
    if(tappable)pageStatus.setOnClickListener(v->{
      manualRetryNeeded=false;
      loadNextPage();
    });
  }
  private void load(String query,boolean unusedShorts,int token){
    currentQuery=query;
    loading=true;
    placeholder("جارٍ تحميل فيديوهات يوتيوب...");
    pool.execute(()->{
      ArrayList<Video> rows=new ArrayList<>();
      org.schabi.newpipe.extractor.Page next=null;
      String failure=null;
      try{
        SearchInfo results=SearchInfo.getInfo(NewPipe.getService(0),
          NewPipe.getService(0).getSearchQHFactory().fromQuery(query));
        rows=playableResults(results.getRelatedItems());
        next=results.getNextPage();
      }catch(Exception error){failure=error.getMessage();}
      final ArrayList<Video> resultRows=rows;
      final org.schabi.newpipe.extractor.Page nextCursor=next;
      final String issue=failure;
      runOnUiThread(()->{
        if(isFinishing() || isDestroyed() || requestId!=token)return;
        loading=false;
        nextSearchPage=nextCursor;
        feed.removeAllViews();
        if(selected==0)categoryChips();
        else sectionHead("نتائج البحث: "+query,null);
        if(issue!=null)placeholder("تعذر تحميل النتائج. تحقق من الاتصال ثم أعد المحاولة.");
        addUniqueVideos(resultRows,true);
        if(list.isEmpty() && issue==null && nextSearchPage==null)
          placeholder("لا توجد نتائج لهذا البحث.");
        if(issue!=null){
          TextView retry=actionChip("↻  إعادة المحاولة",()->{
            requestId++;resetSearchState();feed.removeAllViews();
            load(query,false,requestId);
          });
          feed.addView(retry,new LinearLayout.LayoutParams(-1,dp(51)));
        }else{
          if(nextSearchPage!=null)setPageStatus("مرّر للأسفل لعرض المزيد من الفيديوهات",false);
          else if(!list.isEmpty())setPageStatus("تم عرض جميع النتائج المتاحة",false);
          // Fetch the next page if the first page doesn't fill the screen.
          scroll.post(()->{
            if(requestId==token && nextSearchPage!=null &&
              feed.getHeight()<=scroll.getHeight()+dp(300))loadNextPage();
          });
        }
      });
    });
  }
  private void loadNextPage(){
    if(loading || loadingNextPage || manualRetryNeeded || nextSearchPage==null)return;
    if(selected!=0 && selected!=5)return;
    final int token=requestId;
    final String query=currentQuery;
    final org.schabi.newpipe.extractor.Page page=nextSearchPage;
    nextSearchPage=null;
    loadingNextPage=true;
    setPageStatus("جارٍ تحميل المزيد...",false);
    pool.execute(()->{
      ArrayList<Video> rows=new ArrayList<>();
      org.schabi.newpipe.extractor.Page subsequent=null;
      String error=null;
      try{
        org.schabi.newpipe.extractor.ListExtractor.InfoItemsPage<InfoItem> result=
          SearchInfo.getMoreItems(NewPipe.getService(0),
            NewPipe.getService(0).getSearchQHFactory().fromQuery(query),page);
        rows=playableResults(result.getItems());
        subsequent=result.getNextPage();
      }catch(Exception e){error=e.getMessage();}
      final ArrayList<Video> resultRows=rows;
      final org.schabi.newpipe.extractor.Page cursor=subsequent;
      final String failure=error;
      runOnUiThread(()->{
        if(isFinishing()||isDestroyed()||requestId!=token)return;
        loadingNextPage=false;
        if(failure!=null){
          nextSearchPage=page;
          manualRetryNeeded=true;
          setPageStatus("تعذر جلب المزيد — اضغط لإعادة المحاولة",true);
          return;
        }
        // Remove status before appending, then keep it at the bottom.
        if(pageStatus!=null){feed.removeView(pageStatus);pageStatus=null;}
        addUniqueVideos(resultRows,false);
        nextSearchPage=emptyPageCount>=3?null:cursor;
        if(nextSearchPage!=null)setPageStatus("مرّر للأسفل لعرض المزيد من الفيديوهات",false);
        else setPageStatus("تم عرض جميع الفيديوهات المتاحة",false);
        if(nextSearchPage!=null && feed.getHeight()<=scroll.getHeight()+dp(250))
          scroll.post(()->{if(requestId==token)loadNextPage();});
      });
    });
  }
  private void addCard(Video video,boolean isShort){
    LinearLayout box=linear(LinearLayout.VERTICAL);pad(box,0,0,0,12);
    box.setBackground(background(WHITE,17));
    ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    image.setBackgroundColor(0xffe7e7e7);
    int h=(getResources().getDisplayMetrics().widthPixels*9)/16;
    if(isShort)h=Math.min(dp(310),getResources().getDisplayMetrics().heightPixels/2);
    FrameLayout thumb=new FrameLayout(this);
    thumb.setBackground(background(LIGHT,16));thumb.setClipToOutline(true);
    thumb.addView(image,new FrameLayout.LayoutParams(-1,h));
    TextView playButton=text("▶",23,WHITE,true);playButton.setGravity(Gravity.CENTER);
    playButton.setBackground(background(0x96000000,28));
    thumb.addView(playButton,new FrameLayout.LayoutParams(dp(55),dp(55),Gravity.CENTER));
    if(video.duration>0){
      TextView clock=text(formatted(video.duration),12,WHITE,true);
      clock.setBackground(background(0xcc000000,5));pad(clock,5,1,5,1);
      FrameLayout.LayoutParams badge=new FrameLayout.LayoutParams(-2,dp(22),Gravity.RIGHT|Gravity.BOTTOM);
      badge.setMargins(0,0,dp(10),dp(9));thumb.addView(clock,badge);
    }
    LinearLayout.LayoutParams coverParams=new LinearLayout.LayoutParams(-1,h);
    coverParams.setMargins(dp(12),0,dp(12),0);
    box.addView(thumb,coverParams);
    showImage(video.image,image);
    thumb.setOnClickListener(v->play(video));
    LinearLayout detail=linear(LinearLayout.HORIZONTAL);detail.setGravity(Gravity.CENTER_VERTICAL);pad(detail,16,7,16,6);
    TextView avatar=text(video.uploader.isEmpty()?"▶":video.uploader.substring(0,1),17,WHITE,true);
    avatar.setGravity(Gravity.CENTER);avatar.setBackground(background(RED,35));
    detail.addView(avatar,new LinearLayout.LayoutParams(dp(42),dp(42)));
    avatar.setOnClickListener(v->searchUploader(video));
    LinearLayout labels=linear(LinearLayout.VERTICAL);pad(labels,12,0,12,0);
    TextView title=text(video.title,16,DARK,true);title.setMaxLines(2);title.setEllipsize(TextUtils.TruncateAt.END);
    labels.addView(title);
    String text=video.uploader+(video.duration>0?" · "+formatted(video.duration):"");
    TextView meta=text(text,12,GREY,false);labels.addView(meta);pad(meta,0,5,0,2);
    detail.addView(labels,new LinearLayout.LayoutParams(0,-2,1));
    TextView more=text("⋮",24,DARK,false);more.setGravity(Gravity.CENTER);
    detail.addView(more,new LinearLayout.LayoutParams(dp(38),dp(46)));
    more.setOnClickListener(v->menu(video));
    labels.setOnClickListener(v->play(video));
    box.addView(detail);
    feed.addView(box);
  }
  private String formatted(long dur){
    if(dur>=3600)return String.format(Locale.US,"%d:%02d:%02d",dur/3600,(dur/60)%60,dur%60);
    return String.format(Locale.US,"%d:%02d",dur/60,dur%60);
  }
  private void menu(Video video){
    String sub=video.uploader==null?"":video.uploader;
    String follow=isFollowing(sub)?"إلغاء متابعة القناة":"متابعة القناة";
    new AlertDialog.Builder(this).setTitle(video.title).setItems(new String[]{
      "تشغيل الفيديو","عرض القناة",follow,"المفضلة","المشاهدة لاحقًا","مشاركة الفيديو"
    },(d,which)->{
      if(which==0)play(video);
      if(which==1)channelScreen(video);
      if(which==2)toggleFollow(sub,video.uploaderUrl);
      if(which==3){archive("favorites",video);Toast.makeText(this,"أضيف إلى المفضلة",Toast.LENGTH_SHORT).show();}
      if(which==4){archive("watch_later",video);Toast.makeText(this,"أضيف للمشاهدة لاحقًا",Toast.LENGTH_SHORT).show();}
      if(which==5){Intent i=new Intent(Intent.ACTION_SEND);i.setType("text/plain");
        i.putExtra(Intent.EXTRA_TEXT,video.url);startActivity(Intent.createChooser(i,"مشاركة"));}
    }).show();
  }
  private void searchUploader(Video v){channelScreen(v);}
  private void channelScreen(Video video){
    requestId++;resetSearchState();feed.removeAllViews();scroll.smoothScrollTo(0,0);
    LinearLayout header=linear(LinearLayout.VERTICAL);
    header.setBackground(background(0xfffff1f2,17));pad(header,17,16,17,19);
    LinearLayout avatarLine=linear(LinearLayout.HORIZONTAL);
    avatarLine.setGravity(Gravity.CENTER_VERTICAL);
    TextView avatar=circleAvatar(video.uploader,78);
    avatarLine.addView(avatar,new LinearLayout.LayoutParams(dp(78),dp(78)));
    LinearLayout labels=linear(LinearLayout.VERTICAL);pad(labels,15,0,7,0);
    TextView title=text(video.uploader,25,DARK,true);labels.addView(title);
    labels.addView(text("قناة يوتيوب · معلومات من الفيديو المتاح",13,GREY,false));
    avatarLine.addView(labels,new LinearLayout.LayoutParams(0,-2,1));
    header.addView(avatarLine);
    TextView follow=actionChip(isFollowing(video.uploader)?"✓  تتابع هذه القناة":"⊕  متابعة القناة",()->{
      toggleFollow(video.uploader,video.uploaderUrl);
      channelScreen(video);
    });
    follow.setBackground(background(RED,20));follow.setTextColor(WHITE);
    LinearLayout.LayoutParams flp=new LinearLayout.LayoutParams(-1,dp(46));
    flp.topMargin=dp(16);header.addView(follow,flp);
    LinearLayout.LayoutParams hlp=new LinearLayout.LayoutParams(-1,-2);
    hlp.setMargins(dp(14),dp(12),dp(14),dp(12));feed.addView(header,hlp);
    sectionHead("الفيديوهات",()->queryVideos(video.uploader,false));
    int count=0;
    for(Video item:knownVideos.values()){
      if(!video.uploader.isEmpty() && video.uploader.equalsIgnoreCase(item.uploader)){
        compactRow(item);count++;if(count>=8)break;
      }
    }
    if(count==0)compactRow(video);
    screenRow("عرض المزيد من فيديوهات القناة","البحث عن نتائج حديثة",()->queryVideos(video.uploader,false));
  }
  private void play(Video v){
    if(v.id==null){notice("رابط فيديو غير مدعوم");return;}
    prefs.edit().putString("bg_video_id",v.id)
      .putString("bg_video_title",v.title)
      .putString("bg_video_channel",v.uploader)
      .putBoolean("bg_resume_requested",true).apply();
    archive("history",v);
    if(watchView==null){
      watchView=new NativeWatchView(this, ()->dockMiniPlayer());
      shell.addView(watchView,new FrameLayout.LayoutParams(-1,-1));
    } else if(miniVisible){
      expandMiniPlayer();
    }
    miniTitle.setText(v.title);
    watchView.openVideo(v.id,v.title,v.uploader,false);
  }
  void playFromWatch(String url,String title,String uploader){
    play(new Video(title,url,"",uploader,"",0));
  }
  // Called by the watch surface when the related list is exhausted.
  // Search results remain in their original order even after pagination.
  boolean playNextFromFeed(String currentId,java.util.Set<String> visited){
    int currentIndex=-1;
    for(int i=0;i<list.size();i++){
      if(currentId.equals(list.get(i).id)){currentIndex=i;break;}
    }
    for(int i=currentIndex+1;i<list.size();i++){
      Video candidate=list.get(i);
      if(candidate.id!=null && !candidate.id.equals(currentId) &&
          !visited.contains(candidate.id)){
        play(candidate);return true;
      }
    }
    for(Video candidate:knownVideos.values()){
      if(candidate.id!=null && !candidate.id.equals(currentId) &&
          !visited.contains(candidate.id)){
        play(candidate);return true;
      }
    }
    return false;
  }
  private void closeWatch(){
    if(watchView==null)return;
    // Only explicit Close discards automatic resume; Back/Home never do.
    prefs.edit().putBoolean("bg_resume_requested",false)
      .putBoolean("bg_was_playing",false)
      .remove("bg_video_id").remove("bg_video_title")
      .remove("bg_video_channel").apply();
    restoreMiniAfterPip=false;
    miniVisible=false;
    miniBar.setVisibility(View.GONE);
    watchView.release(true);
    shell.removeView(watchView);
    watchView=null;
    getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    getWindow().setStatusBarColor(WHITE);
    getWindow().setNavigationBarColor(WHITE);
  }
  private void restoreWatchAfterBackground(){
    if(watchView!=null || !prefs.getBoolean("bg_resume_requested",false))return;
    String storedId=prefs.getString("bg_video_id","");
    if(storedId==null || !storedId.matches("[A-Za-z0-9_-]{11}"))return;
    androidx.media3.exoplayer.ExoPlayer active=PlaybackCore.INSTANCE.peek();
    String title=prefs.getString("bg_video_title","فيديو يوتيوب");
    String channel=prefs.getString("bg_video_channel","");
    if(active!=null && active.getCurrentMediaItem()!=null &&
       storedId.equals(active.getCurrentMediaItem().mediaId) &&
       active.getPlaybackState()!=androidx.media3.common.Player.STATE_ENDED &&
       active.getPlayerError()==null){
      // The service already owns this ExoPlayer. Reattach the player view in
      // place without recreating HTTP streams or losing the buffered position.
      watchView=new NativeWatchView(this,()->dockMiniPlayer());
      shell.addView(watchView,new FrameLayout.LayoutParams(-1,-1));
      miniTitle.setText(title);
      watchView.reconnectExisting(storedId,title==null?"فيديو يوتيوب":title,
        channel==null?"":channel);
    }else{
      // Android may kill a paused media service after long inactivity.
      // Recover the selected video and seek to its saved position, but don't
      // start audio unexpectedly if the user had deliberately paused it.
      String restoreTitle=title==null?"فيديو يوتيوب":title;
      String restoreChannel=channel==null?"":channel;
      if(prefs.getBoolean("bg_was_playing",false)){
        play(new Video(restoreTitle,"https://www.youtube.com/watch?v="+storedId,
          "",restoreChannel,"",0));
      }else{
        watchView=new NativeWatchView(this,()->dockMiniPlayer());
        shell.addView(watchView,new FrameLayout.LayoutParams(-1,-1));
        miniTitle.setText(restoreTitle);
        watchView.openVideo(storedId,restoreTitle,restoreChannel,true);
      }
    }
  }
  @Override protected void onResume(){
    super.onResume();
    // Return to regular video decoding only when the watch Activity is visible.
    PlaybackCore.INSTANCE.setAudioOnlyBackground(false);
    if(watchView!=null)watchView.onReturnedToForeground();
  }
  @Override protected void onStop(){
    if(watchView!=null){
      watchView.savePlaybackPosition();
      // playWhenReady also covers buffering, so Android leaving during a
      // rebuffer does not terminate the background media session.
      prefs.edit()
        .putBoolean("bg_resume_requested",watchView.hasLoadedOrPendingVideo())
        .putBoolean("bg_was_playing",watchView.isPlaybackRequested()).apply();
      // Audio-only while outside the app; intentional PiP still renders video.
      if(!isInPictureInPictureMode())
        PlaybackCore.INSTANCE.setAudioOnlyBackground(true);
    }
    super.onStop();
  }
  @Override public void onBackPressed(){
    if(watchView!=null && !miniVisible){
      if(watchView.isFullScreen())watchView.exitFullScreen();
      else dockMiniPlayer();
      return;
    }
    if(miniVisible && selected!=0){
      show(0);
      return;
    }
    super.onBackPressed();
  }
  @Override public void onUserLeaveHint(){
    // Home / Recents must enter AUDIO background playback, not auto-PiP.
    // PiP is still available explicitly from the video player's own button.
    // Android 12+ auto-enter is also disabled in NativeWatchView.
    super.onUserLeaveHint();
  }
  @Override public void onPictureInPictureModeChanged(boolean inPip,android.content.res.Configuration config){
    super.onPictureInPictureModeChanged(inPip,config);
    if(watchView!=null)watchView.onPictureInPictureChanged(inPip);
    // Keep picture visible during PiP rather than switching to background audio.
    if(inPip)PlaybackCore.INSTANCE.setAudioOnlyBackground(false);
    if(!inPip && restoreMiniAfterPip){
      restoreMiniAfterPip=false;
      if(watchView!=null && watchView.hasVideo())dockMiniPlayer();
    }
  }
  @Override public void onConfigurationChanged(android.content.res.Configuration c){
    super.onConfigurationChanged(c);
    if(watchView!=null)watchView.onScreenChanged();
  }
  private void showImage(String source,ImageView target){
    if(source==null||!source.startsWith("https://"))return;
    Bitmap cached=images.get(source);if(cached!=null){target.setImageBitmap(cached);return;}
    pool.execute(()->{
      try{
        HttpURLConnection c=(HttpURLConnection)new URL(source).openConnection();
        c.setConnectTimeout(8000);c.setReadTimeout(8000);
        Bitmap b=BitmapFactory.decodeStream(c.getInputStream());c.disconnect();
        if(b!=null){if(images.size()>45)images.clear();images.put(source,b);
          runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())target.setImageBitmap(b);});}
      }catch(Exception ignored){}
    });
  }
  private void addAd(int slot){
    LinearLayout.LayoutParams space=new LinearLayout.LayoutParams(-1,-2);
    space.topMargin=dp(6);space.bottomMargin=dp(13);
    feed.addView(AdSlots.create(this,slot),space);
  }
  private void archive(String kind,Video video){
    JSONArray result=new JSONArray();result.put(video.json());
    JSONArray old=new JSONArray();
    try{old=new JSONArray(prefs.getString(kind,"[]"));}catch(Exception ignored){}
    for(int i=0;i<old.length()&&result.length()<80;i++){
      JSONObject o=old.optJSONObject(i);if(o!=null&&!video.url.equals(o.optString("url")))result.put(o);
    }
    prefs.edit().putString(kind,result.toString()).apply();
  }
  private void saved(String kind){
    JSONArray arr=new JSONArray();
    try{arr=new JSONArray(prefs.getString(kind,"[]"));}catch(Exception ignored){}
    if(arr.length()==0){placeholder("لا يوجد محتوى محفوظ بعد.");return;}
    for(int i=0;i<arr.length();i++){
      JSONObject o=arr.optJSONObject(i);if(o!=null)addCard(Video.parse(o),false);
    }
  }
  private boolean isFollowing(String uploader){
    return prefs.getString("following","").contains("\n"+uploader.replace("\n"," ")+"\n");
  }
  private void toggleFollow(String uploader,String url){
    if(uploader==null||uploader.trim().isEmpty()){notice("اسم القناة غير متاح");return;}
    String current=prefs.getString("following","");
    String needle="\n"+uploader.replace("\n"," ")+"\n";
    if(current.contains(needle))current=current.replace(needle,"");
    else current+=needle;
    prefs.edit().putString("following",current).apply();
    Toast.makeText(this,"تم تحديث قائمة الاشتراكات المحلية",Toast.LENGTH_SHORT).show();
  }
  private void screenRow(String title,String description,Runnable onClick){
    LinearLayout row=linear(LinearLayout.HORIZONTAL);
    row.setGravity(Gravity.CENTER_VERTICAL);
    GradientDrawable surface=background(WHITE,17);
    surface.setStroke(dp(1),0xffe8e9ed);
    row.setBackground(surface);
    pad(row,13,13,13,13);
    String mark="◉";
    if(title.length()>0 && "◷♡▶▣↗⚙◫ⓘ☾⬇⊕▤✂".contains(title.substring(0,1)))mark=title.substring(0,1);
    TextView icon=text(mark,24,RED,true);icon.setGravity(Gravity.CENTER);
    icon.setBackground(background(0xffffeef0,11));
    row.addView(icon,new LinearLayout.LayoutParams(dp(43),dp(43)));
    LinearLayout detail=linear(LinearLayout.VERTICAL);pad(detail,10,0,10,0);
    TextView heading=text(title,16,DARK,true);
    heading.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
    detail.addView(heading);
    if(description!=null&&!description.isEmpty()){
      TextView caption=text(description,12,GREY,false);
      caption.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
      pad(caption,0,4,0,0);detail.addView(caption);
    }
    row.addView(detail,new LinearLayout.LayoutParams(0,-2,1));
    TextView arrow=text("‹",25,GREY,false);arrow.setGravity(Gravity.CENTER);
    row.addView(arrow,new LinearLayout.LayoutParams(dp(26),dp(38)));
    LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
    lp.setMargins(dp(13),dp(4),dp(13),dp(7));
    feed.addView(row,lp);
    row.setOnClickListener(v->onClick.run());
  }
  private int countSaved(String kind){
    try{return new JSONArray(prefs.getString(kind,"[]")).length();}catch(Exception error){return 0;}
  }
  private void systemDownloads(){
    try{startActivity(new Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS));}
    catch(Exception error){notice("لا يتوفر مدير التنزيلات على الجهاز.");}
  }
  void requestVideoDownload(String id,String title,String quality,String url,String ext){
    if(id==null||title==null||url==null||!url.startsWith("https://"))return;
    String tree=prefs.getString("video_download_tree","");
    ArrayList<String> actions=new ArrayList<>();
    actions.add(Build.VERSION.SDK_INT>=29?"مجلد التنزيلات الافتراضي · Download/EGYTUBE":"اختيار مجلد على هذا الجهاز");
    if(!tree.isEmpty())actions.add("المجلد الذي اخترته سابقًا");
    actions.add("اختيار مجلد حفظ جديد");
    new AlertDialog.Builder(this)
      .setTitle("حفظ "+quality+" · "+title)
      .setItems(actions.toArray(new String[0]),(d,which)->{
        if(which==0){
          if(Build.VERSION.SDK_INT>=29)enqueueVideoDownload(id,title,quality,url,ext,"");
          else chooseDownloadFolder(new String[]{id,title,quality,url,ext});
        }else if(!tree.isEmpty() && which==1){
          enqueueVideoDownload(id,title,quality,url,ext,tree);
        }else{
          chooseDownloadFolder(new String[]{id,title,quality,url,ext});
        }
      }).setNegativeButton("إلغاء",null).show();
  }
  private void chooseDownloadFolder(String[] request){
    pendingDownload=request;
    try{
      Intent picker=new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
      picker.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION |
        Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
      startActivityForResult(picker,CHOOSE_DOWNLOAD_FOLDER);
    }catch(Exception e){
      pendingDownload=null;
      notice("اختيار مجلد الحفظ غير مدعوم على هذا الجهاز");
    }
  }
  @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
    super.onActivityResult(requestCode,resultCode,data);
    if(requestCode!=CHOOSE_DOWNLOAD_FOLDER)return;
    String[] selected=pendingDownload;
    pendingDownload=null;
    if(resultCode!=RESULT_OK || data==null||data.getData()==null)return;
    Uri folder=data.getData();
    try{
      getContentResolver().takePersistableUriPermission(folder,
        Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
      prefs.edit().putString("video_download_tree",folder.toString()).apply();
      if(selected!=null && selected.length==5)
        enqueueVideoDownload(selected[0],selected[1],selected[2],selected[3],selected[4],folder.toString());
      else notice("تم اختيار مجلد التنزيلات. يمكنك استخدامه في التنزيلات القادمة.");
      if(downloadsVisible)renderDownloadItems();
    }catch(Exception e){notice("تعذر الاحتفاظ بإذن مجلد الحفظ. اختر مجلدًا آخر.");}
  }
  private void enqueueVideoDownload(String videoId,String title,String quality,String url,String ext,String tree){
    Data data=new Data.Builder()
      .putString(VideoDownloadWorker.K_VIDEO,videoId)
      .putString(VideoDownloadWorker.K_URL,url)
      .putString(VideoDownloadWorker.K_TITLE,title)
      .putString(VideoDownloadWorker.K_QUALITY,quality)
      .putString(VideoDownloadWorker.K_EXT,ext)
      .putString(VideoDownloadWorker.K_TREE,tree).build();
    OneTimeWorkRequest job=new OneTimeWorkRequest.Builder(VideoDownloadWorker.class)
      .setInputData(data)
      .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
      .addTag(VideoDownloadWorker.TAG).build();
    DownloadCatalog.register(this,job.getId().toString(),title,quality,
      tree.isEmpty()?"Downloads/EGYTUBE":"المجلد الذي اخترته");
    WorkManager.getInstance(this).enqueue(job);
    notice("بدأ تنزيل "+quality+" · يمكنك متابعة التقدم في قسم التنزيلات");
    if(Build.VERSION.SDK_INT>=33 &&
        checkSelfPermission("android.permission.POST_NOTIFICATIONS")!=
          android.content.pm.PackageManager.PERMISSION_GRANTED)
      requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"},916);
  }
  private void downloadsScreen(){
    downloadsVisible=true;
    downloadsUi.removeCallbacks(downloadsRefresh);
    requestId++;resetSearchState();
    selected=3;buildNav();feed.removeAllViews();list.clear();
    scroll.scrollTo(0,0);
    addHeading("التنزيلات");
    String tree=prefs.getString("video_download_tree","");
    screenRow("📂  مجلد التنزيلات",
      tree.isEmpty()?"Downloads/EGYTUBE · يمكنك اختيار مجلد آخر":"تم اختيار مجلد خاص للحفظ",
      ()->chooseDownloadFolder(null));
    screenRow("↗  مدير تنزيلات الهاتف","يمكنك العثور على الملفات في مدير الملفات",this::systemDownloads);
    downloadItems=linear(LinearLayout.VERTICAL);
    feed.addView(downloadItems,new LinearLayout.LayoutParams(-1,-2));
    renderDownloadItems();
    downloadsUi.postDelayed(downloadsRefresh,2400);
  }
  private void renderDownloadItems(){
    if(!downloadsVisible || downloadItems==null)return;
    final int token=++downloadsScreenToken;
    final List<JSONObject> entries=DownloadCatalog.entries(this);
    pool.execute(()->{
      Map<String,WorkInfo> states=new HashMap<>();
      try{
        for(WorkInfo info:WorkManager.getInstance(this).getWorkInfosByTag(VideoDownloadWorker.TAG)
          .get(8,TimeUnit.SECONDS)){
          states.put(info.getId().toString(),info);
        }
      }catch(Exception ignored){}
      runOnUiThread(()->{
        if(!downloadsVisible||token!=downloadsScreenToken ||isFinishing())return;
        downloadItems.removeAllViews();
        if(entries.isEmpty()){
          TextView msg=text("لا توجد تنزيلات بعد. افتح فيديو واضغط تحميل أسفل الفيديو بجوار المشاركة.",14,GREY,false);
          pad(msg,18,25,18,26);
          downloadItems.addView(msg);
          return;
        }
        for(JSONObject entry:entries){
          String id=entry.optString("id"),title=entry.optString("title","فيديو");
          String quality=entry.optString("quality"),location=entry.optString("folder");
          String persisted=entry.optString("state","queued");
          WorkInfo work=states.get(id);
          String state=work!=null?work.getState().name():persisted.toUpperCase(Locale.ROOT);
          int percent=work!=null?work.getProgress().getInt("percent",-1):-1;
          if(work!=null && work.getState()==WorkInfo.State.SUCCEEDED)state="DONE";
          if(work!=null && work.getState()==WorkInfo.State.CANCELLED)state="CANCELLED";
          if(work!=null && work.getState()==WorkInfo.State.FAILED)state="FAILED";
          LinearLayout box=linear(LinearLayout.VERTICAL);
          pad(box,14,11,14,12);
          box.setBackground(background(0xfff5f5f6,13));
          TextView titleView=text(title,15,DARK,true);
          titleView.setMaxLines(2);
          box.addView(titleView);
          String status=(state.equals("DONE")?"اكتمل التنزيل":
            state.equals("RUNNING")?"جارٍ التنزيل"+(percent>=0?" · "+percent+"%":""):
            state.equals("CANCELLED")?"ملغى":
            state.equals("FAILED")?"فشل التنزيل":"في انتظار بدء التنزيل");
          TextView detail=text(quality+" · "+status+"\nالحفظ: "+location,12,GREY,false);
          pad(detail,0,5,0,7);
          box.addView(detail);
          if("RUNNING".equals(state) && percent>=0){
            ProgressBar progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);
            progress.setMax(100);progress.setProgress(percent);
            box.addView(progress,new LinearLayout.LayoutParams(-1,dp(6)));
          }
          LinearLayout row=linear(LinearLayout.HORIZONTAL);
          row.setGravity(Gravity.CENTER_VERTICAL);
          if("DONE".equals(state)){
            String uri=entry.optString("uri");
            if(uri.isEmpty()&&work!=null)uri=work.getOutputData().getString("uri");
            final String fileUri=uri;
            TextView open=text("▶ فتح الملف",14,RED,true);
            pad(open,9,10,9,10);row.addView(open,new LinearLayout.LayoutParams(0,-2,1));
            open.setOnClickListener(v->openDownloadedVideo(fileUri));
          }else if("RUNNING".equals(state)||"ENQUEUED".equals(state)||"BLOCKED".equals(state)){
            TextView stop=text("× إلغاء التنزيل",14,RED,true);
            pad(stop,9,10,9,10);row.addView(stop,new LinearLayout.LayoutParams(0,-2,1));
            stop.setOnClickListener(v->{
              try{WorkManager.getInstance(this).cancelWorkById(UUID.fromString(id));}catch(Exception ignored){}
              DownloadCatalog.update(this,id,"cancelled",null,null);
              renderDownloadItems();
            });
          }else{
            TextView hint=text(entry.optString("error","يمكنك فتح الفيديو وإعادة التنزيل"),12,GREY,false);
            row.addView(hint,new LinearLayout.LayoutParams(0,-2,1));
          }
          TextView forget=text("إزالة من القائمة",12,GREY,false);
          pad(forget,8,10,8,10);row.addView(forget);
          forget.setOnClickListener(v->new AlertDialog.Builder(this)
            .setMessage("إزالة هذا التنزيل من القائمة؟ ستُلغى المهمة إذا كانت نشطة، ولن تُحذف الملفات المكتملة.")
            .setPositiveButton("إزالة",(d,w)->{
              if(work!=null && !work.getState().isFinished())
                WorkManager.getInstance(this).cancelWorkById(work.getId());
              DownloadCatalog.forget(this,id);renderDownloadItems();
            }).setNegativeButton("إلغاء",null).show());
          box.addView(row);
          LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);
          p.setMargins(dp(12),dp(7),dp(12),dp(7));
          downloadItems.addView(box,p);
        }
      });
    });
  }
  private void openDownloadedVideo(String value){
    if(value==null||value.isEmpty()){notice("لم يتم العثور على الملف المحفوظ");return;}
    try{
      Uri uri=Uri.parse(value);
      // A MediaStore/document URI has no visible filename extension; ask its
      // content provider for the actual MIME type instead of forcing MP4.
      String mime=getContentResolver().getType(uri);
      if(mime==null||!mime.startsWith("video/"))mime="video/*";
      Intent open=new Intent(Intent.ACTION_VIEW);
      open.setDataAndType(uri,mime);
      open.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
      startActivity(Intent.createChooser(open,"فتح الفيديو"));
    }catch(Exception e){notice("تعذر فتح الملف. يمكنك العثور عليه باستخدام مدير ملفات الهاتف.");}
  }
  private void subscriptionsScreen(){
    sectionHead("الاشتراكات",null);
    String raw=prefs.getString("following","");
    LinkedHashSet<String> channels=new LinkedHashSet<>();
    for(String ch:raw.split("\\n"))if(ch!=null&&!ch.trim().isEmpty())channels.add(ch.trim());
    if(channels.isEmpty()){
      placeholder("تابع القنوات من قائمة أي فيديو لتظهر هنا.");
      screenRow("⊕  اكتشف قنوات جديدة","استخدم البحث للوصول إلى القنوات",()->show(5));
      return;
    }
    sectionHead("القنوات التي تتابعها",null);
    HorizontalScrollView scrollX=new HorizontalScrollView(this);
    scrollX.setHorizontalScrollBarEnabled(false);
    LinearLayout strip=linear(LinearLayout.HORIZONTAL);pad(strip,12,6,12,6);
    for(String ch:channels){
      LinearLayout cell=linear(LinearLayout.VERTICAL);cell.setGravity(Gravity.TOP|Gravity.CENTER_HORIZONTAL);
      TextView avatar=circleAvatar(ch,65);cell.addView(avatar,new LinearLayout.LayoutParams(dp(65),dp(65)));
      TextView name=text(ch,12,DARK,true);name.setGravity(Gravity.CENTER);
      name.setMaxLines(2);pad(name,0,6,0,0);
      cell.addView(name,new LinearLayout.LayoutParams(-1,dp(42)));
      LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(95),dp(121));
      lp.leftMargin=dp(8);strip.addView(cell,lp);
      cell.setOnClickListener(v->queryVideos(ch,false));
    }
    scrollX.addView(strip);feed.addView(scrollX);
    sectionHead("فيديوهات القنوات",null);
    int knownCount=0;
    for(Video v:knownVideos.values()){
      if(channels.contains(v.uploader)){compactRow(v);knownCount++;if(knownCount>=12)break;}
    }
    if(knownCount==0){
      TextView none=text("يمكنك عرض الفيديوهات الحديثة للقنوات المتابعة.",13,GREY,false);
      pad(none,18,8,18,10);feed.addView(none);
    }
    for(String ch:channels){
      screenRow("◉  "+ch,"استعراض نتائج جديدة من هذه القناة",()->queryVideos(ch,false));
    }
    placeholder("اشتراكاتك محفوظة على هذا الهاتف فقط.");
  }
  private void libraryScreen(){
    sectionHead("المكتبة",null);
    LinearLayout profile=linear(LinearLayout.HORIZONTAL);
    profile.setGravity(Gravity.CENTER_VERTICAL);
    profile.setBackground(background(0xfff7f7f9,17));
    pad(profile,15,12,15,12);
    String display=prefs.getString("local_profile_name","EGYTUBE");
    TextView avatar=circleAvatar(display,67);
    profile.addView(avatar,new LinearLayout.LayoutParams(dp(67),dp(67)));
    LinearLayout info=linear(LinearLayout.VERTICAL);pad(info,13,0,13,0);
    info.addView(text(display,19,DARK,true));
    info.addView(text("مكتبتك الخاصة على هذا الجهاز",13,GREY,false));
    profile.addView(info,new LinearLayout.LayoutParams(0,-2,1));
    TextView arrow=text("‹",26,GREY,false);
    profile.addView(arrow,new LinearLayout.LayoutParams(dp(24),dp(44)));
    LinearLayout.LayoutParams cardLp=new LinearLayout.LayoutParams(-1,-2);
    cardLp.setMargins(dp(13),dp(8),dp(13),dp(8));
    feed.addView(profile,cardLp);profile.setOnClickListener(v->show(4));
    ArrayList<Video> history=collection("history",15);
    if(!history.isEmpty()){
      sectionHead("السجل الأخير",()->{
        requestId++;feed.removeAllViews();sectionHead("سجل المشاهدة",null);saved("history");
      });
      horizontalRail(history.subList(0,Math.min(8,history.size())),160);
    } else {
      sectionHead("السجل الأخير",null);
      placeholder("الفيديوهات التي تشاهدها ستظهر هنا تلقائيًا.");
    }
    sectionHead("مجموعاتك",null);
    screenRow("◷  سجل المشاهدة","الفيديوهات التي شاهدتها • "+countSaved("history"),()->{
      requestId++;feed.removeAllViews();sectionHead("سجل المشاهدة",null);saved("history");
    });
    screenRow("▤  قوائم التشغيل","الفيديوهات المحفوظة في المفضلة",()->{
      requestId++;feed.removeAllViews();sectionHead("قائمة المفضلة",null);saved("favorites");
    });
    screenRow("⬇  التنزيلات","ملفات EGYTUBE المحمّلة والتقدّم ومجلد الحفظ",this::downloadsScreen);
    screenRow("◷  المشاهدة لاحقًا","المحفوظة للمشاهدة • "+countSaved("watch_later"),()->{
      requestId++;feed.removeAllViews();sectionHead("المشاهدة لاحقًا",null);saved("watch_later");
    });
    screenRow("♡  الفيديوهات المعجبة","فيديوهات المفضلة • "+countSaved("favorites"),()->{
      requestId++;feed.removeAllViews();sectionHead("المفضلة",null);saved("favorites");
    });
    screenRow("▶  تشغيل رابط","افتح فيديو يوتيوب عبر الرابط",this::askLink);
    placeholder("لا يتم إظهار مقاطع منشأة أو تنزيلات غير موجودة.");
    addAd(AdSlots.BONEPA_4);
  }
  private void editLocalName(){
    EditText entry=new EditText(this);
    entry.setSingleLine(true);
    entry.setText(prefs.getString("local_profile_name","EGYTUBE"));
    pad(entry,14,8,14,8);
    new AlertDialog.Builder(this).setTitle("الاسم الظاهر على هذا الجهاز")
      .setView(entry).setPositiveButton("حفظ",(d,i)->{
        String name=entry.getText().toString().trim();
        if(name.isEmpty())name="EGYTUBE";
        prefs.edit().putString("local_profile_name",name).apply();
        show(4);
      }).setNegativeButton("إلغاء",null).show();
  }
  private void shareApp(){
    Intent send=new Intent(Intent.ACTION_SEND);
    send.setType("text/plain");
    send.putExtra(Intent.EXTRA_SUBJECT,"تطبيق EGYTUBE");
    send.putExtra(Intent.EXTRA_TEXT,
      "حمّل تطبيق EGYTUBE للأندرويد من موقع EGYSHOW. أحدث إصدار والتحديثات هنا:\n"+APP_PAGE);
    startActivity(Intent.createChooser(send,"مشاركة رابط تحميل EGYTUBE"));
  }
  private JSONObject getUpdateManifest(String path)throws Exception{
    URL url=new URL(path);
    if(!"https".equalsIgnoreCase(url.getProtocol()))throw new SecurityException("Requires HTTPS");
    HttpURLConnection conn=(HttpURLConnection)url.openConnection();
    conn.setConnectTimeout(7000);conn.setReadTimeout(7000);
    conn.setRequestProperty("Accept","application/json");
    conn.setRequestProperty("Cache-Control","no-cache");
    try{
      if(conn.getResponseCode()!=200)throw new java.io.IOException("Update metadata unavailable");
      try(java.io.InputStream stream=conn.getInputStream()){
        byte[] data=new byte[0];
        java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();
        byte[] buffer=new byte[2048];int count;
        while((count=stream.read(buffer))!=-1){
          if(out.size()+count>16_384)throw new java.io.IOException("Update metadata too large");
          out.write(buffer,0,count);
        }
        data=out.toByteArray();
        return new JSONObject(new String(data,java.nio.charset.StandardCharsets.UTF_8));
      }
    }finally{conn.disconnect();}
  }
  private void checkAppUpdate(boolean manual){
    long now=System.currentTimeMillis();
    if(!manual && now-prefs.getLong("last_update_check",0L)<12*60*60*1000L)return;
    prefs.edit().putLong("last_update_check",now).apply();
    pool.execute(()->{
      JSONObject manifest=null;
      try{manifest=getUpdateManifest(OFFICIAL_UPDATE_JSON);}
      catch(Exception first){
        try{manifest=getUpdateManifest(FALLBACK_UPDATE_JSON);}
        catch(Exception second){android.util.Log.w("EGYTUBE.Updates","Could not check update manifest");}
      }
      final JSONObject info=manifest;
      runOnUiThread(()->{
        if(isFinishing() || isDestroyed())return;
        if(info==null){
          if(manual)notice("لا يمكن التحقق من التحديثات الآن. يمكنك زيارة صفحة التطبيق على EGYSHOW.");
          return;
        }
        // Do not advertise a different Android package as a valid upgrade.
        String declaredPackage=info.optString("packageName","");
        if(!declaredPackage.isEmpty() && !getPackageName().equals(declaredPackage)){
          if(manual)notice("قناة التحديث تخص نسخة مختلفة من التطبيق.");
          return;
        }
        int latestCode=info.optInt("versionCode",0);
        int installed=0;
        String installedName="";
        try{
          android.content.pm.PackageInfo pkg=getPackageManager().getPackageInfo(getPackageName(),0);
          installed=pkg.versionCode;
          installedName=pkg.versionName;
        }catch(Exception ignored){}
        if(latestCode<=installed){
          if(manual)notice("التطبيق محدث إلى آخر إصدار متاح ("+installedName+").");
          return;
        }
        String latestName=info.optString("versionName","الجديد");
        String detail=info.optString("notes","تحسينات وإصلاحات جديدة");
        String remoteUrl=info.optString("download_url",APP_PAGE);
        String target=APP_PAGE;
        // Update downloads must remain on the first-party site or GitHub.
        try{
          Uri validated=Uri.parse(remoteUrl);
          String hostName=validated.getHost();
          if("https".equalsIgnoreCase(validated.getScheme()) &&
            (("egyshow.com".equalsIgnoreCase(hostName)) ||
             ("www.egyshow.com".equalsIgnoreCase(hostName)) ||
             ("raw.githubusercontent.com".equalsIgnoreCase(hostName)) ||
             ("github.com".equalsIgnoreCase(hostName))))
              target=remoteUrl;
        }catch(Exception ignored){}
        final String safeUrl=target;
        new AlertDialog.Builder(this)
          .setTitle("يتوفر تحديث EGYTUBE "+latestName)
          .setMessage(detail+"\n\nالإصدار المثبت: "+installedName+
            "\nالإصدار الجديد: "+latestName)
          .setPositiveButton("تحميل التحديث",(dialog,which)->{
             try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(safeUrl)));}
             catch(Exception error){notice("تعذر فتح رابط التحديث. افتح "+APP_PAGE);}
          })
          .setNegativeButton("لاحقًا",null).show();
      });
    });
  }
  private void openAppPage(){
    try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(APP_PAGE)));}
    catch(Exception error){notice("صفحة تطبيق EGYTUBE: "+APP_PAGE);}
  }
  private void settingsScreen(String title){
    try{
      Intent intent=new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:"+getPackageName()));
      startActivity(intent);
    }catch(Exception error){notice("تعذر فتح إعدادات التطبيق في النظام.");}
  }
  private void clearHistory(){
    new AlertDialog.Builder(this).setTitle("حذف سجل المشاهدة")
      .setMessage("حذف السجل المحفوظ على هذا الجهاز فقط؟")
      .setPositiveButton("حذف",(d,w)->{
        prefs.edit().remove("history").apply();show(4);
      }).setNegativeButton("إلغاء",null).show();
  }
  private void profileScreen(){
    sectionHead("الملف الشخصي",null);
    LinearLayout card=linear(LinearLayout.VERTICAL);
    card.setBackground(background(0xffffeff1,22));
    pad(card,17,22,17,22);
    LinearLayout top=linear(LinearLayout.HORIZONTAL);
    top.setGravity(Gravity.CENTER_VERTICAL);
    String name=prefs.getString("local_profile_name","EGYTUBE");
    TextView avatar=circleAvatar(name,75);
    top.addView(avatar,new LinearLayout.LayoutParams(dp(75),dp(75)));
    LinearLayout detail=linear(LinearLayout.VERTICAL);pad(detail,13,0,13,0);
    detail.addView(text(name,22,DARK,true));
    detail.addView(text("ملف شخصي محلي",14,GREY,false));
    detail.addView(text("التفضيلات محفوظة على هذا الهاتف",12,GREY,false));
    top.addView(detail,new LinearLayout.LayoutParams(0,-2,1));
    card.addView(top);
    TextView edit=text("✎  تعديل الاسم الظاهر",16,WHITE,true);
    edit.setGravity(Gravity.CENTER);edit.setBackground(background(RED,14));
    LinearLayout.LayoutParams editLp=new LinearLayout.LayoutParams(-1,dp(48));
    editLp.topMargin=dp(17);card.addView(edit,editLp);
    edit.setOnClickListener(v->editLocalName());
    LinearLayout.LayoutParams cardLp=new LinearLayout.LayoutParams(-1,-2);
    cardLp.setMargins(dp(14),dp(8),dp(14),dp(10));
    feed.addView(card,cardLp);
    sectionHead("الإعدادات",null);
    screenRow("⚙  إعدادات التطبيق","الإشعارات والأذونات من نظام أندرويد",
      ()->settingsScreen("settings"));
    screenRow("▶  تفضيلات التشغيل","إعدادات الجودة والسرعة داخل المشغّل",
      ()->notice("يمكنك تغيير الجودة والسرعة والترجمة من أدوات مشغّل الفيديو نفسه."));
    screenRow("⬇  التحميلات والتخزين","ملفات الفيديو المحمّلة ومكان حفظها",this::downloadsScreen);
    screenRow("◫  الوضع العائم PiP","أذونات التطبيق والتشغيل بالخلفية",
      ()->settingsScreen("pip"));
    screenRow("⚡  الاستمرار في الخلفية","فتح إعدادات توفير البطارية للهاتف",
      ()->new AlertDialog.Builder(this)
        .setTitle("استمرار التشغيل في الخلفية")
        .setMessage("يعتمد استمرار المشاهدة عند قفل الشاشة على خدمة التشغيل في التطبيق. "
          +"قد توقف بعض الهواتف التطبيقات بسبب قيود البطارية. "
          +"يمكنك اختيار السماح لـ EGYTUBE بالتشغيل في الخلفية من إعدادات النظام. "
          +"لن يغيّر التطبيق إعدادات البطارية دون اختيارك.")
        .setPositiveButton("فتح إعدادات البطارية",(d,w)->{
          try{startActivity(new Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));}
          catch(Exception error){settingsScreen("settings");}
        }).setNegativeButton("إلغاء",null).show());
    screenRow("◷  الخصوصية","التحكم في سجل المشاهدة المحلي",this::clearHistory);
    screenRow("◉  اللغة","العربية — الواجهة الحالية",
      ()->notice("الواجهة الحالية باللغة العربية."));
    sectionHead("الدعم والمعلومات",null);
    screenRow("⬇  تنزيل EGYTUBE","صفحة التحميل الرسمية على موقع EGYSHOW",this::openAppPage);
    screenRow("↻  التحقق من التحديثات","الحصول على أحدث إصدار وإصلاحات التطبيق",
      ()->checkAppUpdate(true));
    screenRow("↗  مشاركة التطبيق","دعوة الأصدقاء وتحميل EGYTUBE من EGYSHOW",this::shareApp);
    screenRow("ⓘ  حول التطبيق","EGYTUBE — عرض الإصدار الحالي",()->{
      String v="غير معروف";
      try{v=getPackageManager().getPackageInfo(getPackageName(),0).versionName;}
      catch(Exception ignored){}
      notice("EGYTUBE "+v+"\\nMini Player • PiP • التشغيل بالخلفية • تحديثات من EGYSHOW");
    });
    placeholder("لا توجد مزامنة حساب Google في هذه النسخة، ولا تُعرض بيانات مستخدمين وهمية.");
  }
  @Override protected void onDestroy(){
    downloadsVisible=false;
    downloadsUi.removeCallbacks(downloadsRefresh);
    if(watchView!=null){
      // When Android removes the UI, the MediaSessionService owns audio playback.
      watchView.savePlaybackPosition();
      boolean continueAudio=watchView.keepAudioInBackground();
      // Protect an ongoing audio session even if onStop was skipped.
      if(continueAudio && !isInPictureInPictureMode())
        PlaybackCore.INSTANCE.setAudioOnlyBackground(true);
      prefs.edit()
        .putBoolean("bg_resume_requested",watchView.hasLoadedOrPendingVideo())
        .putBoolean("bg_was_playing",watchView.isPlaybackRequested()).apply();
      watchView.release(!continueAudio);
      shell.removeView(watchView);
      watchView=null;
    }
    pool.shutdownNow();
    super.onDestroy();
  }
}
