package com.egytube.rebuilt;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.*;

public class MainActivity extends Activity {
 private final int RED=0xffe52739,BLACK=0xff161c29,MUTED=0xff788294,WHITE=Color.WHITE;
 private final String[] titles={"الرئيسية","البحث","أفلام","مسلسلات","قصيرة","أخبار"};
 private final String[] links={
  "https://egyshow.com/ar/youtube?category=entertainment",
  "",
  "https://egyshow.com/ar/movies",
  "https://egyshow.com/ar/series",
  "https://egyshow.com/ar/short-series",
  "https://egyshow.com/ar/news"};
 private final ExecutorService pool=Executors.newFixedThreadPool(4);
 private final Map<String,Bitmap> cache=Collections.synchronizedMap(new LinkedHashMap<>());
 private LinearLayout root,items,header,nav;
 private EditText searchBox;
 private int tab=0,generation=0;
 private final ArrayList<Entry> shown=new ArrayList<>();
 static class Entry{
  final String title,url,image,meta;final boolean video;
  Entry(String title,String url,String image,String meta,boolean video){
   this.title=title;this.url=url;this.image=image;this.meta=meta;this.video=video;
  }
 }
 private int dp(int x){return (int)(x*getResources().getDisplayMetrics().density+.5f);}
 private TextView label(String s,int size,int color,boolean bold){
  TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);
  v.setGravity(Gravity.CENTER_VERTICAL);
  if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);return v;
 }
 private GradientDrawable bg(int color,int radius){
  GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;
 }
 private LinearLayout row(){
  LinearLayout l=new LinearLayout(this);l.setOrientation(LinearLayout.HORIZONTAL);l.setGravity(Gravity.CENTER_VERTICAL);return l;
 }
 private LinearLayout col(){LinearLayout l=new LinearLayout(this);l.setOrientation(LinearLayout.VERTICAL);return l;}
 private void padding(View v,int a,int b,int c,int d){v.setPadding(dp(a),dp(b),dp(c),dp(d));}
 @Override public void onCreate(Bundle b){
  super.onCreate(b);getWindow().setStatusBarColor(WHITE);getWindow().setNavigationBarColor(WHITE);
  getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
  root=col();root.setBackgroundColor(WHITE);root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);setContentView(root);
  header=row();padding(header,18,12,18,12);
  TextView logo=label("▶",26,RED,true);header.addView(logo,new LinearLayout.LayoutParams(dp(42),dp(48)));
  TextView brand=label("EGYTUBE",22,BLACK,true);header.addView(brand,new LinearLayout.LayoutParams(0,dp(48),1));
  TextView refresh=label("⟳",28,RED,true);refresh.setGravity(Gravity.CENTER);
  header.addView(refresh,new LinearLayout.LayoutParams(dp(45),dp(48)));refresh.setOnClickListener(v->select(tab));
  root.addView(header);
  ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);
  items=col();padding(items,14,6,14,16);scroll.addView(items);
  root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
  HorizontalScrollView strip=new HorizontalScrollView(this);strip.setHorizontalScrollBarEnabled(false);
  nav=row();nav.setBackgroundColor(WHITE);padding(nav,6,7,6,7);strip.addView(nav);
  root.addView(strip,new LinearLayout.LayoutParams(-1,dp(72)));root.addView(new View(this),new LinearLayout.LayoutParams(1,dp(1)));
  String shared=getIntent()!=null?getIntent().getStringExtra(Intent.EXTRA_TEXT):null;
  if(shared!=null && (shared.contains("youtu.be/")||shared.contains("youtube.com/"))){
   String id=videoId(shared);if(id!=null){play(id,"فيديو يوتيوب");}
  }
  select(0);
 }
 private void drawNavigation(){
  nav.removeAllViews();
  for(int i=0;i<titles.length;i++){
   final int which=i;
   TextView item=label((i==0?"⌂ ":i==1?"⌕ ":i==2?"▣ ":i==3?"▤ ":i==4?"▸ ":"◉ ")+titles[i],
     13,tab==i?RED:MUTED,tab==i);
   item.setGravity(Gravity.CENTER);padding(item,12,12,12,12);
   nav.addView(item,new LinearLayout.LayoutParams(-2,dp(58)));
   item.setOnClickListener(v->select(which));
  }
 }
 private void select(int index){
  tab=index;generation++;drawNavigation();items.removeAllViews();shown.clear();
  TextView title=label(titles[index],24,BLACK,true);items.addView(title,new LinearLayout.LayoutParams(-1,dp(49)));
  if(index==1){renderSearch();return;}
  if(index==0){TextView sub=label("فيديوهات عادية • عرض متواصل بدون تقسيم",13,MUTED,false);items.addView(sub);}
  load(index,generation);
 }
 private void renderSearch(){
  searchBox=new EditText(this);searchBox.setSingleLine(true);
  searchBox.setHint("ابحث عن فيديو أو فيلم أو مسلسل");searchBox.setTextSize(15);
  searchBox.setImeOptions(EditorInfo.IME_ACTION_SEARCH);searchBox.setBackground(bg(0xfff1f3f7,14));
  padding(searchBox,14,5,14,5);items.addView(searchBox,new LinearLayout.LayoutParams(-1,dp(53)));
  TextView button=label("بحث",17,WHITE,true);button.setGravity(Gravity.CENTER);button.setBackground(bg(RED,12));
  LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(48));p.topMargin=dp(12);items.addView(button,p);
  button.setOnClickListener(v->search());
  searchBox.setOnEditorActionListener((v,id,event)->{if(id==EditorInfo.IME_ACTION_SEARCH){search();return true;}return false;});
  message("البحث يعرض نتائج من قوائم EGYSHOW دون مفتاح API. البحث العام في يوتيوب ليس متاحًا بهذه الطريقة.");
 }
 private void search(){
  if(searchBox==null)return;String q=searchBox.getText().toString().trim();
  if(q.isEmpty()){searchBox.setError("اكتب نص البحث");return;}
  String id=videoId(q);if(id!=null){play(id,q);return;}
  int token=++generation;
  items.removeAllViews();TextView title=label("نتائج: "+q,21,BLACK,true);items.addView(title);message("جارٍ البحث...");
  pool.execute(()->{
   LinkedHashMap<String,Entry> result=new LinkedHashMap<>();
   for(int i:new int[]{0,2,3,4,5}){
    try{for(Entry e:fetch(i)){
      if(e.title.toLowerCase(Locale.ROOT).contains(q.toLowerCase(Locale.ROOT)))result.put(e.url,e);
    }}catch(Exception ignored){}
   }
   runOnUiThread(()->{
    if(token!=generation||isFinishing())return;items.removeAllViews();
    items.addView(label("نتائج: "+q,21,BLACK,true));
    if(result.isEmpty())message("لا توجد نتائج في القوائم الحالية. جرّب كلمة أقصر.");
    else for(Entry e:result.values())addCard(e);
   });
  });
 }
 private void load(int page,int token){
  message("جارٍ تحميل المحتوى...");
  pool.execute(()->{
   List<Entry> data;String error=null;
   try{data=fetch(page);}catch(Exception ex){data=new ArrayList<>();error=ex.getMessage();}
   final List<Entry> list=data;final String why=error;
   runOnUiThread(()->{
    if(token!=generation||isFinishing())return;
    items.removeAllViews();
    items.addView(label(titles[page],24,BLACK,true),new LinearLayout.LayoutParams(-1,dp(50)));
    if(page==0)items.addView(label("الفيديوهات • بدون تقسيمات",13,MUTED,false));
    if(why!=null)message("تعذّر تحميل البيانات: "+why);
    else if(list.isEmpty())message("لا يتوفر محتوى حاليًا، جرّب تحديث الصفحة.");
    for(Entry item:list){shown.add(item);addCard(item);}
   });
  });
 }
 private List<Entry> fetch(int page)throws Exception{
  Document doc=Jsoup.connect(links[page]).userAgent("EGYTUBE-Native/0.5.0")
   .timeout(15000).maxBodySize(2_000_000).get();
  LinkedHashMap<String,Entry> data=new LinkedHashMap<>();
  String selector=page==0?"a[href*='watch?egy=']":
   page==2?"a[href*='/ar/movie/']":
   page==3?"a[href*='/ar/series/']":
   page==4?"a[href*='/ar/short-series/']":"a[href*='/ar/news/'], article a[href]";
  for(Element a:doc.select(selector)){
   String url=a.absUrl("href"),name=a.text().trim();
   if(url.isEmpty()||!url.startsWith("https://egyshow.com/"))continue;
   if(name.isEmpty())name=a.attr("title");
   Element poster=a.selectFirst("img");
   if(poster==null&&a.parent()!=null)poster=a.parent().selectFirst("img");
   if(name.isEmpty()&&poster!=null)name=poster.attr("alt");
   if(name.isEmpty()||name.length()<3||name.equals("EGYSHOW"))continue;
   boolean video=page==0;
   String id=video?videoId(url):null;
   if(video&&id==null)continue;
   String img=video?"https://i.ytimg.com/vi/"+id+"/hqdefault.jpg":"";
   if(poster!=null&&!video){img=poster.absUrl("data-src");if(img.isEmpty())img=poster.absUrl("src");}
   if(page>0&&url.equals(links[page]))continue;
   data.put(url,new Entry(name,url,img,video?"YouTube":"EGYSHOW",video));
   if(data.size()>=40)break;
  }
  return new ArrayList<>(data.values());
 }
 private String videoId(String input){
  if(input==null)return null;
  Matcher m=Pattern.compile("[?&]egy=([A-Za-z0-9_-]{11})|[?&]v=([A-Za-z0-9_-]{11})|youtu\\.be/([A-Za-z0-9_-]{11})|/embed/([A-Za-z0-9_-]{11})").matcher(input);
  if(m.find()){for(int i=1;i<=4;i++){if(m.group(i)!=null)return m.group(i);}}
  if(input.matches("[A-Za-z0-9_-]{11}"))return input;
  return null;
 }
 private void play(String id,String title){
  startActivity(new Intent(this,PlayerActivity.class).putExtra("videoId",id).putExtra("videoTitle",title));
 }
 private void openEntry(Entry e){
  if(e.video){String id=videoId(e.url);if(id!=null){play(id,e.title);return;}}
  new AlertDialog.Builder(this).setTitle(e.title).setMessage("عرض تفاصيل المحتوى على EGYSHOW. ستفتح صفحة المشاهدة في متصفح الجهاز.")
   .setPositiveButton("فتح التفاصيل",(d,w)->{
    try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(e.url)));}
    catch(Exception ignored){Toast.makeText(this,"لا يوجد متصفح متاح",Toast.LENGTH_SHORT).show();}
   }).setNegativeButton("إلغاء",null).show();
 }
 private void addCard(Entry e){
  LinearLayout card=row();card.setBackground(bg(0xfff7f8fa,14));padding(card,9,9,9,9);
  ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setBackground(bg(0xffd8dce3,8));
  card.addView(image,new LinearLayout.LayoutParams(dp(136),dp(88)));
  if(e.image!=null&&!e.image.isEmpty())imageAsync(e.image,image);
  LinearLayout details=col();padding(details,11,0,11,0);
  TextView t=label(e.title,15,BLACK,true);t.setMaxLines(3);t.setEllipsize(TextUtils.TruncateAt.END);
  details.addView(t);TextView info=label(e.meta,12,MUTED,false);
  LinearLayout.LayoutParams pInfo=new LinearLayout.LayoutParams(-1,dp(29));pInfo.topMargin=dp(6);details.addView(info,pInfo);
  card.addView(details,new LinearLayout.LayoutParams(0,-2,1));
  LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.bottomMargin=dp(12);items.addView(card,p);
  card.setOnClickListener(v->openEntry(e));
 }
 private void imageAsync(String u,ImageView view){
  Bitmap bmp=cache.get(u);if(bmp!=null){view.setImageBitmap(bmp);return;}
  pool.execute(()->{
   try{
    HttpURLConnection c=(HttpURLConnection)new URL(u).openConnection();
    c.setConnectTimeout(7000);c.setReadTimeout(7000);
    Bitmap x=BitmapFactory.decodeStream(c.getInputStream());c.disconnect();
    if(x!=null){
     if(cache.size()>40)cache.clear();cache.put(u,x);
     runOnUiThread(()->{if(!isFinishing())view.setImageBitmap(x);});
    }
   }catch(Exception ignored){}
  });
 }
 private void message(String s){
  TextView t=label(s,14,MUTED,false);padding(t,7,13,7,13);
  items.addView(t,new LinearLayout.LayoutParams(-1,-2));
 }
 @Override protected void onDestroy(){pool.shutdownNow();super.onDestroy();}
}
