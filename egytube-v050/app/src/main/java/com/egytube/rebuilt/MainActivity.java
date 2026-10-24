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
  private static final String[] TABS={"الرئيسية","Shorts","الاشتراكات","المكتبة","حسابي"};
  private static final String[] ICONS={"⌂","▶","▣","▤","◉"};
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
      final int tab=i;
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
    selected=tab;requestId++;loading=false;buildNav();feed.removeAllViews();list.clear();currentQuery="";
    scroll.smoothScrollTo(0,0);
    if(tab==0){
      currentShorts=false;
      addHeading("اكتشف فيديوهات تناسبك");
      load("مقاطع فيديو جديدة 2026",false,requestId);
    }else if(tab==1){
      currentShorts=true;
      addHeading("المقاطع القصيرة");
      load("shorts",true,requestId);
    }else if(tab==2)subscriptionsScreen();
    else if(tab==3)libraryScreen();
    else if(tab==4)profileScreen();
    else searchScreen();
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
    selected=shorts?1:5;buildNav();requestId++;feed.removeAllViews();list.clear();
    currentShorts=shorts;currentQuery=q;
    addHeading(shorts?"Shorts":"نتائج البحث: "+q);
    load(q,shorts,requestId);
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
  private void shortRail(int token){
    sectionHead("المقاطع القصيرة",()->show(1));
    LinearLayout holder=linear(LinearLayout.HORIZONTAL);
    holder.setGravity(Gravity.CENTER_VERTICAL);pad(holder,15,10,15,10);
    TextView pending=text("جارٍ جلب المقاطع القصيرة...",13,GREY,false);
    holder.addView(pending);feed.addView(holder);
    pool.execute(()->{
      ArrayList<Video> clips=new ArrayList<>();
      try{
        SearchInfo results=SearchInfo.getInfo(NewPipe.getService(0),
          NewPipe.getService(0).getSearchQHFactory().fromQuery("shorts"));
        for(InfoItem item:results.getRelatedItems()){
          if(!(item instanceof StreamInfoItem))continue;
          StreamInfoItem v=(StreamInfoItem)item;
          if(v.getStreamType()!=null && v.getStreamType().name().toUpperCase(Locale.ROOT).contains("LIVE"))continue;
          long dur=v.getDuration();
          if(!(v.isShortFormContent() || (dur>0&&dur<=180)))continue;
          Video itemVideo=new Video(v.getName(),v.getUrl(),
            v.getThumbnails().isEmpty()?"":v.getThumbnails().get(0).getUrl(),
            v.getUploaderName(),v.getUploaderUrl(),dur);
          if(itemVideo.id!=null)clips.add(itemVideo);
          if(clips.size()>=8)break;
        }
      }catch(Exception ignored){}
      runOnUiThread(()->{
        if(isDestroyed()||isFinishing()||token!=requestId||selected!=0)return;
        holder.removeAllViews();
        if(clips.isEmpty()){
          TextView open=actionChip("استكشف المقاطع القصيرة",()->show(1));holder.addView(open);
          return;
        }
        HorizontalScrollView x=new HorizontalScrollView(this);x.setHorizontalScrollBarEnabled(false);
        LinearLayout track=linear(LinearLayout.HORIZONTAL);
        for(Video clip:clips){
          remember(clip);
          FrameLayout poster=new FrameLayout(this);
          poster.setBackground(background(0xff101014,15));poster.setClipToOutline(true);
          ImageView img=new ImageView(this);img.setScaleType(ImageView.ScaleType.CENTER_CROP);
          poster.addView(img,new FrameLayout.LayoutParams(-1,-1));showImage(clip.image,img);
          GradientDrawable tint=new GradientDrawable(
            GradientDrawable.Orientation.BOTTOM_TOP,new int[]{0xce000000,0x00000000});
          View dark=new View(this);dark.setBackground(tint);
          poster.addView(dark,new FrameLayout.LayoutParams(-1,-1));
          TextView name=text(clip.title,13,WHITE,true);name.setMaxLines(3);
          pad(name,7,3,7,10);
          poster.addView(name,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));
          LinearLayout.LayoutParams t=new LinearLayout.LayoutParams(dp(132),dp(220));
          t.leftMargin=dp(9);track.addView(poster,t);
          poster.setOnClickListener(v->play(clip));
        }
        x.addView(track);holder.addView(x,new LinearLayout.LayoutParams(-1,-2));
      });
    });
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
        feed.removeAllViews();
        for(Video video:rows)remember(video);
        if(selected==0){
          categoryChips();
          if(!rows.isEmpty())hero(rows.get(0));
          sectionHead("مقترحة لك",()->queryVideos("فيديوهات متنوعة",false));
          horizontalRail(rows.subList(0,Math.min(6,rows.size())),176);
          shortRail(token);
          ArrayList<Video> watched=collection("history",12);
          if(!watched.isEmpty()){
            sectionHead("متابعة المشاهدة",()->show(3));
            horizontalRail(watched,175);
          }
          sectionHead("أحدث الفيديوهات",null);
        }else if(selected==1){
          sectionHead("المقاطع القصيرة",null);
          placeholder("اسحب لأعلى لاستكشاف المقاطع. اضغط على الصورة للتشغيل.");
        }else sectionHead("نتائج البحث: "+query,null);
        if(issue!=null)placeholder("تعذر الاتصال بنتائج يوتيوب: "+issue+"\nقد يتغير عمل مصدر البحث، ويمكنك تشغيل رابط فيديو مباشر.");
        if(rows.isEmpty()){
          if(issue==null)placeholder("لا توجد نتائج لهذا البحث، جرّب كلمات أخرى.");
          TextView retry=text("↻ إعادة المحاولة",15,RED,true);pad(retry,18,14,18,14);
          feed.addView(retry);retry.setOnClickListener(v->{requestId++;load(query,onlyShorts,requestId);});
        }else{
          for(int i=0;i<rows.size();i++){
            Video v=rows.get(i);list.add(v);
            if(onlyShorts)addShortCard(v);
            else if(selected==0 && i<4)addCard(v,false);
            else if(selected!=0)compactRow(v);
            if(i==3)addAd(AdSlots.RECT_300x250);
            if(i==9)addAd(AdSlots.BANNER_468x60);
            if(i==16)addAd(AdSlots.BONEPA_4);
          }
        }
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
  private void addShortCard(Video video){
    FrameLayout tile=new FrameLayout(this);
    tile.setBackground(background(0xff171717,19));tile.setClipToOutline(true);
    int height=Math.min(dp(490),(int)(getResources().getDisplayMetrics().heightPixels*.65f));
    ImageView preview=new ImageView(this);
    preview.setScaleType(ImageView.ScaleType.CENTER_CROP);
    tile.addView(preview,new FrameLayout.LayoutParams(-1,-1));
    showImage(video.image,preview);
    android.graphics.drawable.GradientDrawable shade=new android.graphics.drawable.GradientDrawable(
      android.graphics.drawable.GradientDrawable.Orientation.BOTTOM_TOP,new int[]{0xe0000000,0x00000000});
    View scrim=new View(this);scrim.setBackground(shade);
    tile.addView(scrim,new FrameLayout.LayoutParams(-1,-1));
    TextView center=text("▶",32,WHITE,true);center.setGravity(Gravity.CENTER);
    center.setBackground(background(0x88000000,36));
    tile.addView(center,new FrameLayout.LayoutParams(dp(68),dp(68),Gravity.CENTER));
    LinearLayout info=linear(LinearLayout.VERTICAL);pad(info,14,8,14,17);
    TextView title=text(video.title,19,WHITE,true);title.setMaxLines(2);
    TextView channel=text("◉  "+video.uploader+"   ·   "+formatted(video.duration),13,WHITE,true);
    info.addView(title);info.addView(channel);
    FrameLayout.LayoutParams ilp=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);tile.addView(info,ilp);
    LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,height);
    lp.setMargins(dp(14),dp(4),dp(14),dp(15));feed.addView(tile,lp);
    LinearLayout actions=linear(LinearLayout.VERTICAL);
    actions.setGravity(Gravity.CENTER);pad(actions,0,2,0,3);
    TextView like=text("♡",31,WHITE,true);like.setGravity(Gravity.CENTER);
    TextView share=text("↗",32,WHITE,true);share.setGravity(Gravity.CENTER);
    TextView save=text("▤",30,WHITE,true);save.setGravity(Gravity.CENTER);
    TextView follow=text("⊕",30,WHITE,true);follow.setGravity(Gravity.CENTER);
    for(TextView icon:new TextView[]{like,share,save,follow})
      actions.addView(icon,new LinearLayout.LayoutParams(dp(55),dp(65)));
    FrameLayout.LayoutParams actionsLp=new FrameLayout.LayoutParams(dp(55),-2,Gravity.LEFT|Gravity.CENTER_VERTICAL);
    tile.addView(actions,actionsLp);
    like.setOnClickListener(v->{archive("favorites",video);Toast.makeText(this,"أضيف للمفضلة",Toast.LENGTH_SHORT).show();});
    save.setOnClickListener(v->{archive("watch_later",video);Toast.makeText(this,"تم الحفظ للمشاهدة لاحقًا",Toast.LENGTH_SHORT).show();});
    share.setOnClickListener(v->{Intent send=new Intent(Intent.ACTION_SEND);send.setType("text/plain");
      send.putExtra(Intent.EXTRA_TEXT,video.url);startActivity(Intent.createChooser(send,"مشاركة"));});
    follow.setOnClickListener(v->{toggleFollow(video.uploader,video.uploaderUrl);});
    tile.setOnClickListener(v->play(video));
    tile.setOnLongClickListener(v->{menu(video);return true;});
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
    requestId++;feed.removeAllViews();scroll.smoothScrollTo(0,0);
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
    watchView.release(true);
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
  @Override public void onUserLeaveHint(){
    super.onUserLeaveHint();
    // Android 8-11 need explicit PiP when the user presses Home.
    if(android.os.Build.VERSION.SDK_INT>=26 && android.os.Build.VERSION.SDK_INT<31 && watchView!=null && watchView.isPlayingVideo()){
      watchView.enterPictureInPicture();
    }
  }
  @Override public void onPictureInPictureModeChanged(boolean inPip,android.content.res.Configuration config){
    super.onPictureInPictureModeChanged(inPip,config);
    if(watchView!=null)watchView.onPictureInPictureChanged(inPip);
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
    row.setBackground(background(LIGHT,16));
    pad(row,16,12,15,12);
    LinearLayout detail=linear(LinearLayout.VERTICAL);
    TextView heading=text(title,16,DARK,true);heading.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
    detail.addView(heading);
    if(description!=null&&!description.isEmpty()){
      TextView caption=text(description,12,GREY,false);caption.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);
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
  private void subscriptionsScreen(){
    addHeading("الاشتراكات");
    String raw=prefs.getString("following","");
    LinkedHashSet<String> channels=new LinkedHashSet<>(Arrays.asList(raw.split("\\n")));
    channels.remove("");
    if(channels.isEmpty()){
      placeholder("لم تتابع قنوات بعد. اضغط على ⋮ بجوار الفيديو لاختيار متابعة القناة.");
      screenRow("استكشف الفيديوهات","ابحث عن قنوات وفيديوهات جديدة",()->show(5));
    }else{
      addSubheading("قنواتك المفضلة · "+channels.size());
      for(String channel:channels){
        if(channel.trim().isEmpty())continue;
        screenRow("◉  "+channel,"عرض أحدث الفيديوهات من القناة",()->queryVideos(channel,false));
      }
    }
    placeholder("المتابعات محلية داخل EGYTUBE ولا تحتاج حساب يوتيوب.");
  }
  private void libraryScreen(){
    addHeading("مكتبتك");
    addSubheading("شاهدتها مؤخرًا");
    JSONArray recent=new JSONArray();
    try{recent=new JSONArray(prefs.getString("history","[]"));}catch(Exception ignored){}
    if(recent.length()==0)placeholder("شغّل فيديو لتظهر هنا فيديوهات المشاهدة الأخيرة.");
    else {
      int count=Math.min(recent.length(),3);
      for(int i=0;i<count;i++){JSONObject o=recent.optJSONObject(i);if(o!=null)addCard(Video.parse(o),false);}
    }
    addSubheading("مجموعات الفيديوهات");
    screenRow("◷  سجل المشاهدة","إجمالي الفيديوهات: "+countSaved("history"),()->{
      requestId++;feed.removeAllViews();addHeading("سجل المشاهدة");saved("history");
    });
    screenRow("♡  المفضلة","إجمالي العناصر المحفوظة: "+countSaved("favorites"),()->{
      requestId++;feed.removeAllViews();addHeading("المفضلة");saved("favorites");
    });
    screenRow("▶  تشغيل رابط","أدخل رابط فيديو يوتيوب",this::askLink);
    placeholder("المكتبة محفوظة على هذا الجهاز، وليست حساب يوتيوب متزامنًا.");
    addAd(AdSlots.BONEPA_4);
  }
  private void profileScreen(){
    addHeading("حسابي");
    LinearLayout panel=linear(LinearLayout.VERTICAL);
    panel.setBackground(background(0xfffff0f1,18));pad(panel,17,16,17,16);
    TextView monogram=text("◉",32,RED,true);monogram.setGravity(Gravity.CENTER);
    panel.addView(monogram,new LinearLayout.LayoutParams(-1,dp(55)));
    TextView title=text("EGYTUBE",22,DARK,true);title.setGravity(Gravity.CENTER);
    panel.addView(title);
    TextView caption=text("ملف شخصي محلي · لا يتطلب تسجيل الدخول",13,GREY,false);
    caption.setGravity(Gravity.CENTER);pad(caption,0,5,0,0);
    panel.addView(caption);
    LinearLayout.LayoutParams area=new LinearLayout.LayoutParams(-1,-2);
    area.setMargins(dp(14),dp(7),dp(14),dp(9));feed.addView(panel,area);
    addSubheading("إعدادات وتجربة التطبيق");
    screenRow("◉  البلد واللغة","الواجهة باللغة العربية",()->notice(
      "الواجهة عربية. نتائج الفيديو تعتمد على البحث المتاح في يوتيوب."));
    screenRow("◷  البحث السابق","استعرض ما بحثت عنه",()->show(5));
    screenRow("◫  PiP والتشغيل في الخلفية",
      "التشغيل في نافذة عائمة والصوت عبر MediaSession",()->notice(
       "يدعم الإصدار 0.6.8 نافذة PiP وإشعار تشغيل الصوت عبر MediaSession. "
       +"قد يختلف الأداء حسب الجهاز وإعدادات توفير الطاقة."));
    screenRow("♡  المفضلة والمحفوظات","إدارة الفيديوهات المحفوظة محليًا",()->show(3));
    screenRow("↗  مشاركة التطبيق","مشاركة رابط مشروع EGYTUBE",()->{
      Intent intent=new Intent(Intent.ACTION_SEND);
      intent.setType("text/plain");
      intent.putExtra(Intent.EXTRA_TEXT,"https://github.com/facemasr/ShortSeriesAndroid");
      startActivity(Intent.createChooser(intent,"مشاركة EGYTUBE"));
    });
    screenRow("ⓘ  عن EGYTUBE","الإصدار التجريبي 0.6.9 — تطوير واجهة 0.6.8",
      ()->notice("EGYTUBE — تطبيق Android أصلي باستخدام Media3. "
      +"هذا الإصدار يعرض تصميم واجهات جديدًا، ويحتفظ بخدمة PiP والصوت والإعلانات."));
    placeholder("لا توجد مزامنة حساب مع YouTube أو انتحال للاشتراكات على المنصة.");
  }
  @Override protected void onDestroy(){
    if(watchView!=null){
      // When Android removes the UI, the MediaSessionService owns audio playback.
      boolean continueAudio=watchView.isPlayingVideo();
      watchView.release(!continueAudio);
      shell.removeView(watchView);
      watchView=null;
    }
    pool.shutdownNow();
    super.onDestroy();
  }
}
