package com.egytube.rebuilt;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.*;
import java.util.regex.Pattern;

public class PlayerActivity extends Activity {
 private WebView video,advert;
 private static final String AD="https://bonepa.com/bafdf04fb5f56432509c/231238cdb2/?placementName=default";
 @Override public void onCreate(Bundle b){
  super.onCreate(b);
  getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
  String id=getIntent().getStringExtra("videoId");
  if(id==null||!Pattern.matches("[A-Za-z0-9_-]{11}",id)){finish();return;}
  String name=getIntent().getStringExtra("videoTitle");
  LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);
  root.setBackgroundColor(Color.WHITE);root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);setContentView(root);
  TextView back=new TextView(this);back.setText("↩  EGYTUBE");back.setTextSize(19);back.setTextColor(0xffda283a);
  back.setGravity(Gravity.CENTER_VERTICAL);back.setPadding(24,20,24,20);root.addView(back);
  back.setOnClickListener(v->finish());
  video=new WebView(this);video.setBackgroundColor(Color.BLACK);
  video.getSettings().setJavaScriptEnabled(true);
  video.getSettings().setDomStorageEnabled(true);
  video.getSettings().setMediaPlaybackRequiresUserGesture(true);
  video.setWebChromeClient(new WebChromeClient());
  video.setWebViewClient(new WebViewClient(){
   @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){
    Uri uri=r.getUrl();if(!r.isForMainFrame())return false;
    String host=uri.getHost()==null?"":uri.getHost();
    if(host.equals("www.youtube.com")||host.equals("www.youtube-nocookie.com"))return false;
    try{startActivity(new Intent(Intent.ACTION_VIEW,uri));}catch(Exception ignored){}return true;
   }
  });
  int height=Math.max((getResources().getDisplayMetrics().widthPixels*9)/16,Math.round(200*getResources().getDisplayMetrics().density));
  root.addView(video,new LinearLayout.LayoutParams(-1,height));
  // The official embedded player adjusts its stream quality to current network conditions.
  String html="<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"+
   "<body style='margin:0;background:#000'><iframe width='100%' height='100%'"+
   " style='position:absolute;inset:0;border:0' src='https://www.youtube.com/embed/"+id+
   "?playsinline=1&rel=0' allow='accelerometer;autoplay;encrypted-media;picture-in-picture' allowfullscreen></iframe></body></html>";
  video.loadDataWithBaseURL("https://egyshow.com/",html,"text/html","UTF-8",null);
  TextView title=new TextView(this);title.setText(name==null?"فيديو من يوتيوب":name);title.setTextSize(18);
  title.setTextColor(0xff161c29);title.setPadding(22,22,22,22);root.addView(title);
  TextView note=new TextView(this);note.setText("الجودة: تلقائية وفقًا لسرعة الإنترنت وإعدادات يوتيوب");
  note.setTextSize(13);note.setTextColor(0xff737e92);note.setPadding(22,0,22,12);root.addView(note);
  TextView adTitle=new TextView(this);adTitle.setText("إعلان");adTitle.setTextSize(11);adTitle.setTextColor(0xff878787);
  adTitle.setPadding(22,12,22,2);root.addView(adTitle);
  advert=new WebView(this);advert.setBackgroundColor(0xfffafafa);
  advert.getSettings().setJavaScriptEnabled(true);
  advert.getSettings().setDomStorageEnabled(false);
  advert.getSettings().setSupportMultipleWindows(false);
  advert.setWebViewClient(new WebViewClient(){
   @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest req){
    if(req.isForMainFrame())return true;return false;
   }
  });
  // Ad is outside the official YouTube iframe and never obscures its controls.
  advert.loadDataWithBaseURL("https://egyshow.com/",
    "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"+
    "<body style='margin:0'><script src='"+AD+"'></script></body></html>",
    "text/html","UTF-8",null);
  root.addView(advert,new LinearLayout.LayoutParams(-1,Math.round(90*getResources().getDisplayMetrics().density)));
 }
 @Override protected void onPause(){super.onPause();if(video!=null)video.onPause();}
 @Override protected void onResume(){super.onResume();if(video!=null)video.onResume();}
 @Override protected void onDestroy(){
  if(video!=null){video.destroy();video=null;}
  if(advert!=null){advert.destroy();advert=null;}
  super.onDestroy();
 }
}
