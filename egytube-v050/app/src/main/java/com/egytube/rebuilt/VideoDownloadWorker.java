package com.egytube.rebuilt;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.ServiceInfo;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.documentfile.provider.DocumentFile;
import androidx.work.Data;
import androidx.work.ForegroundInfo;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.stream.StreamInfo;
import org.schabi.newpipe.extractor.stream.VideoStream;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.io.File;
import java.io.FileOutputStream;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

/**
 * Only downloads progressive combined audio/video streams. No DRM bypass,
 * stream extraction in the player, hidden browser work, or silent file installs.
 * WorkManager persists and schedules the job even when the Activity closes.
 */
public final class VideoDownloadWorker extends Worker {
  public static final String TAG="egytube-download";
  public static final String K_URL="url",K_TITLE="title",K_QUALITY="quality",K_TREE="tree";
  public static final String K_EXT="ext",K_VIDEO="video_id";
  private static final String CHANNEL="egytube_downloads";
  private static final long MAX_BYTES=12L*1024*1024*1024;
  private long lastProgressAt=0;

  public VideoDownloadWorker(@NonNull Context context,@NonNull WorkerParameters params){
    super(context,params);
  }

  @NonNull @Override public Result doWork(){
    String workId=getId().toString(),url=getInputData().getString(K_URL);
    String title=getInputData().getString(K_TITLE);
    String quality=getInputData().getString(K_QUALITY);
    String tree=getInputData().getString(K_TREE);
    String videoId=getInputData().getString(K_VIDEO);
    String ext=getInputData().getString(K_EXT);
    if(url==null||!url.startsWith("https://")||title==null||quality==null){
      DownloadCatalog.update(getApplicationContext(),workId,"failed",null,"رابط التنزيل غير صالح");
      return Result.failure();
    }
    if(!"webm".equalsIgnoreCase(ext))ext="mp4";
    String name=filename(title,quality,videoId,ext);
    Context context=getApplicationContext();
    DownloadCatalog.update(context,workId,"running",null,null);
    Uri destination=null;
    File oldApiFile=null;
    boolean inMediaStore=false;
    try{
      setForegroundAsync(foreground(title,-1)).get(10,TimeUnit.SECONDS);
      if(isStopped())return Result.failure();
      ContentResolver resolver=context.getContentResolver();
      OutputStream stream;
      if(tree!=null&&!tree.isEmpty()){
        Uri selected=Uri.parse(tree);
        DocumentFile root=DocumentFile.fromTreeUri(context,selected);
        if(root==null||!root.canWrite())throw new IllegalStateException("مجلد الحفظ غير متاح. اختر المجلد مرة أخرى.");
        DocumentFile result=root.createFile(mime(ext),name);
        if(result==null)throw new IllegalStateException("تعذر إنشاء ملف داخل المجلد المحدد");
        destination=result.getUri();
        stream=resolver.openOutputStream(destination,"w");
      }else if(Build.VERSION.SDK_INT>=29){
        ContentValues values=new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME,name);
        values.put(MediaStore.MediaColumns.MIME_TYPE,mime(ext));
        values.put(MediaStore.MediaColumns.RELATIVE_PATH,Environment.DIRECTORY_DOWNLOADS+"/EGYTUBE");
        values.put(MediaStore.MediaColumns.IS_PENDING,1);
        destination=resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,values);
        if(destination==null)throw new IllegalStateException("تعذر فتح مجلد التنزيلات");
        inMediaStore=true;
        stream=resolver.openOutputStream(destination,"w");
      }else{
        // Android 8-9: the app-specific Downloads folder is available without
        // storage permissions; choose a shared folder through the system picker.
        File folder=new File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),"EGYTUBE");
        if(!folder.exists()&&!folder.mkdirs())throw new IllegalStateException("تعذر إنشاء مجلد التنزيلات");
        oldApiFile=new File(folder,name);
        stream=new FileOutputStream(oldApiFile);
        destination=Uri.fromFile(oldApiFile);
      }
      if(stream==null)throw new IllegalStateException("تعذر فتح ملف التنزيل");
      long total=0,bytes=0;
      try(OutputStream output=stream){
        HttpURLConnection connection=connect(url);
        try{
          int status=connection.getResponseCode();
          if(status==403||status==410){
            connection.disconnect();
            String replacement=refresh(videoId,quality,ext);
            if(replacement==null)throw new IllegalStateException("انتهت صلاحية رابط الفيديو. افتح الفيديو وجرب مجددًا.");
            connection=connect(replacement);
            status=connection.getResponseCode();
          }
          if(status!=200&&status!=206)
            throw new IllegalStateException("تعذر بدء التنزيل: HTTP "+status);
          total=connection.getContentLengthLong();
          if(total>MAX_BYTES)throw new IllegalStateException("الملف كبير جدًا");
          try(InputStream input=connection.getInputStream()){
            byte[] chunk=new byte[96*1024];
            int length;
            while((length=input.read(chunk))!=-1){
              if(isStopped())throw new InterruptedException("أُلغي التنزيل");
              bytes+=length;
              if(bytes>MAX_BYTES)throw new IllegalStateException("تجاوز حجم الملف المسموح");
              output.write(chunk,0,length);
              long now=System.currentTimeMillis();
              if(now-lastProgressAt>900){
                int percent=total>0?(int)Math.min(99,bytes*100/total):-1;
                Data progress=new Data.Builder().putLong("downloaded",bytes)
                  .putLong("total",total).putInt("percent",percent).build();
                setProgressAsync(progress);
                setForegroundAsync(foreground(title,percent));
                lastProgressAt=now;
              }
            }
            output.flush();
          }
        }finally{connection.disconnect();}
      }
      if(bytes<1)throw new IllegalStateException("لم يتم تنزيل أي بيانات");
      if(total>0 && bytes<total)throw new IllegalStateException("التنزيل غير مكتمل");
      if(inMediaStore){
        ContentValues values=new ContentValues();
        values.put(MediaStore.MediaColumns.IS_PENDING,0);
        resolver.update(destination,values,null,null);
      }
      Data done=new Data.Builder().putString("uri",destination.toString())
        .putLong("bytes",bytes).build();
      DownloadCatalog.update(context,workId,"done",destination.toString(),null);
      return Result.success(done);
    }catch(Exception e){
      if(destination!=null){
        try{
          if(oldApiFile!=null)oldApiFile.delete();
          else context.getContentResolver().delete(destination,null,null);
        }catch(Exception ignored){}
      }
      String reason=isStopped()?"تم إلغاء التنزيل":e.getMessage();
      DownloadCatalog.update(context,workId,isStopped()?"cancelled":"failed",null,reason);
      return Result.failure(new Data.Builder().putString("error",reason==null?"تعذر تنزيل الفيديو":reason).build());
    }
  }

  private ForegroundInfo foreground(String name,int progress){
    Context c=getApplicationContext();
    NotificationManager manager=(NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE);
    if(Build.VERSION.SDK_INT>=26){
      NotificationChannel channel=new NotificationChannel(CHANNEL,"تنزيلات EGYTUBE",NotificationManager.IMPORTANCE_LOW);
      channel.setDescription("تنزيل الفيديوهات التي اخترت حفظها");
      manager.createNotificationChannel(channel);
    }
    Notification notification=new NotificationCompat.Builder(c,CHANNEL)
      .setSmallIcon(R.drawable.ic_app).setContentTitle("EGYTUBE · تنزيل الفيديو")
      .setContentText(name).setOngoing(true).setOnlyAlertOnce(true)
      .setProgress(100,progress<0?0:progress,progress<0).build();
    int notificationId=0x2800+(getId().hashCode()&0x0fff);
    return new ForegroundInfo(notificationId,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
  }

  private static String filename(String title,String quality,String videoId,String ext){
    String titleSafe=title.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]"," ").replaceAll("\\s+"," ").trim();
    if(titleSafe.length()>65)titleSafe=titleSafe.substring(0,65).trim();
    String qualitySafe=quality.replaceAll("[^a-zA-Z0-9]","");
    if(qualitySafe.length()>14)qualitySafe=qualitySafe.substring(0,14);
    String id=videoId!=null&&videoId.matches("[A-Za-z0-9_-]{11}")?videoId:"video";
    return (titleSafe.isEmpty()?"EGYTUBE":titleSafe)+"-"+qualitySafe+"-"+id+"."+ext;
  }

  private static String mime(String ext){return "webm".equalsIgnoreCase(ext)?"video/webm":"video/mp4";}

  private HttpURLConnection connect(String url)throws Exception{
    URL current=new URL(url);
    for(int i=0;i<5;i++){
      if(!"https".equalsIgnoreCase(current.getProtocol()))
        throw new IllegalStateException("مصدر التنزيل غير آمن");
      HttpURLConnection connection=(HttpURLConnection)current.openConnection();
      connection.setInstanceFollowRedirects(false);
      connection.setConnectTimeout(16000);
      connection.setReadTimeout(30000);
      connection.setRequestProperty("Accept-Encoding","identity");
      connection.setRequestProperty("User-Agent","Mozilla/5.0 (Linux; Android) EGYTUBE/0.8.1");
      int status=connection.getResponseCode();
      if(status==301||status==302||status==303||status==307||status==308){
        String location=connection.getHeaderField("Location");
        connection.disconnect();
        if(location==null)throw new IllegalStateException("المصدر غير متاح");
        current=new URL(current,location);
        continue;
      }
      return connection;
    }
    throw new IllegalStateException("إعادة توجيه كثيرة لمصدر الفيديو");
  }

  private String refresh(String videoId,String quality,String ext){
    if(videoId==null||!videoId.matches("[A-Za-z0-9_-]{11}"))return null;
    try{
      try{NewPipe.init(new HttpDownloader());}catch(Exception ignored){}
      StreamInfo info=StreamInfo.getInfo("https://www.youtube.com/watch?v="+videoId);
      for(VideoStream stream:info.getVideoStreams()){
        if(stream.isVideoOnly()||!stream.isUrl())continue;
        String container=stream.getFormat()!=null?stream.getFormat().getName():"";
        if(("webm".equals(ext)) != container.toUpperCase(Locale.ROOT).contains("WEBM"))continue;
        if(quality.equals(stream.getResolution())&&stream.getContent().startsWith("https://"))
          return stream.getContent();
      }
    }catch(Exception ignored){}
    return null;
  }
}
