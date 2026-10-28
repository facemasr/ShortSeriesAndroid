package com.egytube.rebuilt;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.widget.Toast;
import org.json.JSONObject;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Read-only update discovery from the project-owned GitHub release manifest.
 * Installation is deliberately user-approved via the default external browser.
 * Android will not install a differently-signed APK over an existing package.
 */
public final class UpdateChecker {
  private static final String FEED =
    "https://raw.githubusercontent.com/facemasr/ShortSeriesAndroid/" +
    "egytube-rebuild-20261024/public-downloads/latest.json";
  private static final String TRUSTED_DOWNLOAD_PREFIX =
    "https://raw.githubusercontent.com/facemasr/ShortSeriesAndroid/" +
    "egytube-rebuild-20261024/public-downloads/EGYTUBE-YouTube-Only-";
  private static final long CHECK_INTERVAL_MS = 12L * 60L * 60L * 1000L;
  private static final ExecutorService WORKER = Executors.newSingleThreadExecutor();

  private UpdateChecker() {}

  public static void check(Activity activity,boolean manual){
    SharedPreferences p = activity.getSharedPreferences("EGYTUBE_ONLY",Activity.MODE_PRIVATE);
    long now = System.currentTimeMillis();
    if(!manual && now-p.getLong("last_update_check",0L) < CHECK_INTERVAL_MS)return;
    WORKER.execute(()->{
      HttpURLConnection connection=null;
      try{
        connection=(HttpURLConnection)new URL(FEED).openConnection();
        connection.setRequestProperty("Accept","application/json");
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(10000);
        connection.setInstanceFollowRedirects(false);
        if(connection.getResponseCode()!=200)throw new Exception("تعذر الوصول إلى معلومات الإصدار");
        byte[] bytes;
        try(java.io.InputStream in=connection.getInputStream();
            java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream()){
          byte[] chunk=new byte[4096];
          int n;
          while((n=in.read(chunk))!=-1){
            if(out.size()+n>16000)throw new Exception("ملف تحديث غير صالح");
            out.write(chunk,0,n);
          }
          bytes=out.toByteArray();
        }
        JSONObject latest = new JSONObject(new String(bytes,java.nio.charset.StandardCharsets.UTF_8));
        int remoteVersion=latest.getInt("versionCode");
        String versionName=latest.optString("versionName","إصدار جديد");
        String apkUrl=latest.getString("apkUrl");
        String description=latest.optString("notes","");
        String packageName=latest.optString("packageName","");
        if(!activity.getPackageName().equals(packageName) ||
            !apkUrl.startsWith(TRUSTED_DOWNLOAD_PREFIX) || !apkUrl.endsWith(".apk") ||
            latest.optInt("schema",0)!=1)
          throw new Exception("مصدر التحديث غير موثوق");
        String hash=latest.optString("sha256","");
        if(!hash.matches("[0-9a-f]{64}"))throw new Exception("لا توجد بصمة موثوقة للملف");
        long localVersion=BuildConfig.VERSION_CODE;
        p.edit().putLong("last_update_check",System.currentTimeMillis()).apply();
        activity.runOnUiThread(()->{
          if(activity.isFinishing() || activity.isDestroyed())return;
          if(remoteVersion<=localVersion){
            if(manual)Toast.makeText(activity,"لديك أحدث إصدار من EGYTUBE",Toast.LENGTH_LONG).show();
            return;
          }
          String message = "يتوفر EGYTUBE "+versionName+
             "\n\n"+description+
             "\n\nالتثبيت يحتاج موافقتك وقد يرفض أندرويد التحديث إذا كان توقيع APK مختلفًا.";
          new AlertDialog.Builder(activity)
            .setTitle("تحديث جديد متاح")
            .setMessage(message)
            .setPositiveButton("تحميل التحديث",(dialog,which)->{
              Intent browser=new Intent(Intent.ACTION_VIEW,Uri.parse(apkUrl));
              browser.addCategory(Intent.CATEGORY_BROWSABLE);
              try{activity.startActivity(browser);}
              catch(Exception ex){Toast.makeText(activity,"تعذر فتح متصفح التنزيل",Toast.LENGTH_LONG).show();}
            })
            .setNegativeButton("لاحقًا",null)
            .show();
        });
      }catch(Exception error){
        if(manual){
          activity.runOnUiThread(()->{
            if(!activity.isFinishing() && !activity.isDestroyed())
              new AlertDialog.Builder(activity)
                .setTitle("تعذر فحص التحديثات")
                .setMessage(error.getMessage()==null?"يرجى التحقق من الإنترنت":error.getMessage())
                .setPositiveButton("موافق",null)
                .show();
          });
        }
      }finally{
        if(connection!=null)connection.disconnect();
      }
    });
  }
}
