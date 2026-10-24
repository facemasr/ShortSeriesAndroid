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
  private static final String[] TABS={"الرئيسية","Shorts","بحث","الاشتراكات","أنت"};
  private static final String[] ICONS={"⌂","▶","⌕","▣","◉"};
  private final int WHITE=0xffffffff, DARK=0xff171717, RED=0xffed1c24, GREY=0xff696969, LIGHT=0xfff4f4f4;
  private final ExecutorService pool=Executors.newFixedThreadPool(5);
  private final Map<String,Bitmap> images=Collections.synchronizedMap(new LinkedHashMap<>());
  private final ArrayList<Video> list=new ArrayList<>();
  private LinearLayout app,feed,bottom;
  private FrameLayout shell;
  private NativeWatchView watchView;
  private EditText searchInput;
  private ScrollView scroll;
  private SharedPreferences prefs;
  private int selected=0,requestId=0;
  private String currentQuery="";
  private boolean currentShorts=false,loading=false;

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
    bottom=linear(LinearLayout.HORIZONTAL);bottom.setBackgroundColor(WHITE);pad(bottom,4,4,4,5);
    app.addView(bottom,new LinearLayout.LayoutParams(-1,dp(61)));
    View line=new View(this);line.setBackgroundColor(0xffeeeeee);app.addView(line,new LinearLayout.LayoutParams(-1,dp(1)));
    String shared=getIntent()==null?null:getIntent().getStringExtra(Intent.EXTRA_TEXT);
    if(shared!=null&&idFrom(shared)!=null)play(new Video("فيديو يوتيوب",shared,"","","",0));
    show(0);
  }
  private void setupHeader(){
    LinearLayout h=linear(LinearLayout.HORIZONTAL);h.setGravity(Gravity.CENTER_VERTICAL);pad(h,15,7,12,6);
    TextView title=text("▶ EGYTUBE",21,DARK,true);title.setSingleLine(true);
    h.addView(title,new LinearLayout.LayoutParams(0,dp(46),1));
    TextView cast=text("⟳",24,GREY,false);cast.setGravity(Gravity.CENTER);
    h.addView(cast,new LinearLayout.LayoutParams(dp(45),dp(46)));
    cast.setOnClickListener(v->show(selected));
    TextView find=text("⌕",28,DARK,true);find.setGravity(Gravity.CENTER);
    h.addView(find,new LinearLayout.LayoutParams(dp(48),dp(46)));
    find.setOnClickListener(v->show(2));
    TextView more=text("⋮",26,DARK,true);more.setGravity(Gravity.CENTER);
    h.addView(more,new LinearLayout.LayoutParams(dp(35),dp(46)));
    more.setOnClickListener(v->new AlertDialog.Builder(this).setItems(new String[]{"تحديث الرئيسية","حول EGYTUBE","فتح رابط فيديو"},(d,i)->{
      if(i==0)show(0);else if(i==1)notice("EGYTUBE 0.6.0 — فيديوهات يوتيوب فقط، مشغل Media3 خاص، بدون API، مكتبة محلية.");
      else askLink();
    }).show());
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
    for(int i=0;i<TABS.length;i++){
      final int tab=i;
      LinearLayout wrap=linear(LinearLayout.VERTICAL);wrap.setGravity(Gravity.CENTER);
      TextView sym=text(ICONS[i],25,i==selected?DARK:GREY,false);sym.setGravity(Gravity.CENTER);
      TextView label=text(TABS[i],11,i==selected?DARK:GREY,i==selected);label.setGravity(Gravity.CENTER);
      wrap.addView(sym);wrap.addView(label);
      bottom.addView(wrap,new LinearLayout.LayoutParams(0,-1,1));
      wrap.setOnClickListener(v->show(tab));
    }
  }
  private void show(int tab){
    selected=tab;requestId++;loading=false;buildNav();feed.removeAllViews();list.clear();currentQuery="";
    if(tab==0){currentShorts=false;addHeading("الفيديوهات");load("مقاطع فيديو جديدة 2026",false,requestId);}
    else if(tab==1){currentShorts=true;addHeading("Shorts");load("youtube shorts عربي جديد",true,requestId);}
    else if(tab==2)searchScreen();
    else if(tab==3)subscriptionsScreen();
    else libraryScreen();
  }
  private void addHeading(String label){
    TextView h=text(label,21,DARK,true);pad(h,16,10,16,8);feed.addView(h);
  }
  private void notice(String s){new AlertDialog.Builder(this).setMessage(s).setPositiveButton("موافق",null).show();}
  private void placeholder(String s){
    TextView t=text(s,14,GREY,false);pad(t,18,14,18,14);feed.addView(t);
  }
  private void searchScreen(){
    addHeading("البحث في يوتيوب");
    LinearLayout shell=linear(LinearLayout.HORIZONTAL);pad(shell,14,8,14,8);
    searchInput=new EditText(this);searchInput.setSingleLine(true);searchInput.setTextSize(16);
    searchInput.setHint("ابحث عن فيديو أو قناة");searchInput.setBackground(background(LIGHT,13));
    searchInput.setImeOptions(EditorInfo.IME_ACTION_SEARCH);pad(searchInput,13,4,13,4);
    shell.addView(searchInput,new LinearLayout.LayoutParams(0,dp(50),1));
    TextView go=text("بحث",15,WHITE,true);go.setGravity(Gravity.CENTER);go.setBackground(background(RED,13));
    LinearLayout.LayoutParams gp=new LinearLayout.LayoutParams(dp(65),dp(50));gp.leftMargin=dp(8);shell.addView(go,gp);
    feed.addView(shell);
    go.setOnClickListener(v->startSearch());
    searchInput.setOnEditorActionListener((v,a,e)->{if(a==EditorInfo.IME_ACTION_SEARCH){startSearch();return true;}return false;});
    placeholder("البحث مباشرة في نتائج يوتيوب بدون مفتاح API.");
  }
  private void startSearch(){
    String q=searchInput==null?"":searchInput.getText().toString().trim();
    if(q.isEmpty()){if(searchInput!=null)searchInput.setError("أدخل كلمات البحث");return;}
    String id=idFrom(q);if(id!=null){play(new Video("يوتيوب",q,"","","",0));return;}
    currentShorts=false;requestId++;feed.removeAllViews();addHeading("نتائج: "+q);load(q,false,requestId);
  }
  private void load(String query,boolean onlyShorts,int token){
    currentQuery=query;loading=true;placeholder("جارٍ تحميل فيديوهات يوتيوب...");
    pool.execute(()->{
      ArrayList<Video> rows=new ArrayList<>();String failure=null;
      try{
        SearchInfo results=SearchInfo.getInfo(NewPipe.getService(0),NewPipe.getService(0).getSearchQHFactory().fromQuery(query));
        for(InfoItem item:results.getRelatedItems()){
          if(!(item instanceof StreamInfoItem))continue;
          StreamInfoItem stream=(StreamInfoItem)item;
          if(stream.getStreamType()!=null&&stream.getStreamType().name().toUpperCase(Locale.ROOT).contains("LIVE"))continue;
          long duration=stream.getDuration();
          if(onlyShorts){if(!(stream.isShortFormContent() || (duration>0&&duration<=180)))continue;}
          else if(stream.isShortFormContent() || (duration>0&&duration<=180))continue;
          Video video=new Video(stream.getName(),stream.getUrl(),(stream.getThumbnails().isEmpty()?"":stream.getThumbnails().get(0).getUrl()),
            stream.getUploaderName(),stream.getUploaderUrl(),duration);
          if(video.id==null)continue;
          rows.add(video);
        }
      }catch(Exception error){failure=error.getMessage();}
      final String issue=failure;
      runOnUiThread(()->{
        if(isFinishing()||isDestroyed()||requestId!=token)return;
        loading=false;
        feed.removeAllViews();addHeading(selected==0?"الفيديوهات":selected==1?"Shorts":"نتائج البحث");
        if(issue!=null)placeholder("تعذر الاتصال بنتائج يوتيوب: "+issue+"\nقد يتغير عمل مصدر البحث، ويمكنك تشغيل رابط فيديو مباشر.");
        if(rows.isEmpty()){
          if(issue==null)placeholder("لا توجد نتائج لهذا البحث، جرّب كلمات أخرى.");
          TextView retry=text("↻ إعادة المحاولة",15,RED,true);pad(retry,18,14,18,14);
          feed.addView(retry);retry.setOnClickListener(v->{requestId++;load(query,onlyShorts,requestId);});
        }else{
          for(int i=0;i<rows.size();i++){Video v=rows.get(i);list.add(v);addCard(v,onlyShorts);if(i==3)addAd(AdSlots.RECT_300x250);if(i==9)addAd(AdSlots.BANNER_468x60);if(i==16)addAd(AdSlots.BONEPA_4);}
        }
      });
    });
  }
  private void addCard(Video video,boolean isShort){
    LinearLayout box=linear(LinearLayout.VERTICAL);pad(box,0,0,0,15);
    ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    image.setBackgroundColor(0xffe7e7e7);
    int h=(getResources().getDisplayMetrics().widthPixels*9)/16;
    if(isShort)h=Math.min(dp(310),getResources().getDisplayMetrics().heightPixels/2);
    FrameLayout thumb=new FrameLayout(this);
    thumb.addView(image,new FrameLayout.LayoutParams(-1,h));
    if(video.duration>0){
      TextView clock=text(formatted(video.duration),12,WHITE,true);
      clock.setBackground(background(0xcc000000,5));pad(clock,5,1,5,1);
      FrameLayout.LayoutParams badge=new FrameLayout.LayoutParams(-2,dp(22),Gravity.RIGHT|Gravity.BOTTOM);
      badge.setMargins(0,0,dp(10),dp(9));thumb.addView(clock,badge);
    }
    box.addView(thumb,new LinearLayout.LayoutParams(-1,h));
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
    String title="حفظ في المفضلة",share="مشاركة الفيديو", follow=isFollowing(sub)?"إلغاء متابعة القناة":"متابعة القناة";
    new AlertDialog.Builder(this).setTitle(video.title).setItems(new String[]{title,follow,share,"تشغيل"},(d,which)->{
      if(which==0){archive("favorites",video);Toast.makeText(this,"أضيف إلى المفضلة",Toast.LENGTH_SHORT).show();}
      if(which==1){toggleFollow(sub,video.uploaderUrl);}
      if(which==2){Intent i=new Intent(Intent.ACTION_SEND);i.setType("text/plain");i.putExtra(Intent.EXTRA_TEXT,video.url);startActivity(Intent.createChooser(i,"مشاركة"));}
      if(which==3)play(video);
    }).show();
  }
  private void searchUploader(Video v){
    selected=2;buildNav();requestId++;feed.removeAllViews();
    addHeading("القناة: "+v.uploader);load(v.uploader,false,requestId);
  }
  private void play(Video v){
    if(v.id==null){notice("رابط فيديو غير مدعوم");return;}
    archive("history",v);
    if(watchView==null){
      watchView=new NativeWatchView(this, ()->closeWatch());
      shell.addView(watchView,new FrameLayout.LayoutParams(-1,-1));
    }
    watchView.openVideo(v.id,v.title,v.uploader);
  }
  void playFromWatch(String url,String title,String uploader){
    play(new Video(title,url,"",uploader,"",0));
  }
  private void closeWatch(){
    if(watchView==null)return;
    watchView.release();
    shell.removeView(watchView);
    watchView=null;
    getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    getWindow().setStatusBarColor(WHITE);
    getWindow().setNavigationBarColor(WHITE);
  }
  @Override public void onBackPressed(){
    if(watchView!=null){
      if(watchView.isFullScreen()){watchView.exitFullScreen();}
      else closeWatch();
      return;
    }
    super.onBackPressed();
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
  private void subscriptionsScreen(){
    addHeading("الاشتراكات");
    String str=prefs.getString("following","");
    if(str.trim().isEmpty()){placeholder("تابع قنواتك من القائمة ⋮ بجانب الفيديو. سيتم حفظ المتابعة على هذا الهاتف فقط.");return;}
    HashSet<String> list=new LinkedHashSet<>(Arrays.asList(str.split("\n")));
    for(String channel:list){
      if(channel.trim().isEmpty())continue;
      TextView t=text("▣  "+channel,17,DARK,true);pad(t,20,20,20,20);feed.addView(t);
      t.setOnClickListener(v->{requestId++;feed.removeAllViews();addHeading(channel);load(channel,false,requestId);});
    }
    placeholder("الاشتراكات محفوظة محليًا دون تسجيل الدخول إلى حساب Google.");
  }
  private void libraryScreen(){
    addHeading("أنت");
    TextView fav=text("★  مقاطع أعجبتك وحفظتها",17,DARK,true);pad(fav,18,18,18,18);
    feed.addView(fav);fav.setOnClickListener(v->{requestId++;feed.removeAllViews();addHeading("المفضلة");saved("favorites");});
    TextView recent=text("◷  سجل المشاهدة",17,DARK,true);pad(recent,18,18,18,18);
    feed.addView(recent);recent.setOnClickListener(v->{requestId++;feed.removeAllViews();addHeading("سجل المشاهدة");saved("history");});
    TextView link=text("▶  تشغيل رابط فيديو",17,DARK,true);pad(link,18,18,18,18);feed.addView(link);link.setOnClickListener(v->askLink());
    placeholder("EGYTUBE — خاص بيوتيوب فقط. المفضلة والسجل محفوظان على الهاتف. لن تتم إزالة إعلانات يوتيوب أو تجاوز قيود المحتوى.");
    addAd(AdSlots.BONEPA_4);
  }
  @Override protected void onDestroy(){if(watchView!=null)closeWatch();pool.shutdownNow();super.onDestroy();}
}
