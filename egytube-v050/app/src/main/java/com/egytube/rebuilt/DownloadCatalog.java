package com.egytube.rebuilt;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;

/** Persistent, lightweight index: downloads remain visible after job completion or process restart. */
public final class DownloadCatalog {
  private static final String PREFS="egytube_downloads";
  private static final String KEY="entries";
  private DownloadCatalog(){}

  public static synchronized void register(Context context,String id,String title,String quality,String folder){
    try{
      JSONArray list=read(context);
      JSONObject item=new JSONObject();
      item.put("id",id);item.put("title",title);item.put("quality",quality);
      item.put("folder",folder);item.put("state","queued");
      item.put("createdAt",System.currentTimeMillis());
      list.put(item);
      save(context,list);
    }catch(Exception ignored){}
  }

  public static synchronized void update(Context context,String id,String state,String uri,String error){
    try{
      JSONArray list=read(context);
      for(int i=0;i<list.length();i++){
        JSONObject row=list.optJSONObject(i);
        if(row!=null && id.equals(row.optString("id"))){
          row.put("state",state);
          if(uri!=null && !uri.isEmpty())row.put("uri",uri);
          if(error!=null && !error.isEmpty())row.put("error",error);
          row.put("updatedAt",System.currentTimeMillis());
          break;
        }
      }
      save(context,list);
    }catch(Exception ignored){}
  }

  public static synchronized List<JSONObject> entries(Context context){
    ArrayList<JSONObject> rows=new ArrayList<>();
    JSONArray list=read(context);
    for(int i=list.length()-1;i>=0;i--){
      JSONObject obj=list.optJSONObject(i);
      if(obj!=null)rows.add(obj);
    }
    return rows;
  }

  public static synchronized void forget(Context context,String id){
    JSONArray existing=read(context),remaining=new JSONArray();
    for(int i=0;i<existing.length();i++){
      JSONObject entry=existing.optJSONObject(i);
      if(entry!=null && !id.equals(entry.optString("id")))remaining.put(entry);
    }
    save(context,remaining);
  }

  private static JSONArray read(Context c){
    try{return new JSONArray(c.getSharedPreferences(PREFS,Context.MODE_PRIVATE).getString(KEY,"[]"));}
    catch(Exception ignored){return new JSONArray();}
  }
  private static void save(Context c,JSONArray value){
    // Bound the local metadata index to avoid unbounded SharedPreferences growth.
    JSONArray limited=new JSONArray();
    for(int i=Math.max(0,value.length()-300);i<value.length();i++)limited.put(value.opt(i));
    c.getSharedPreferences(PREFS,Context.MODE_PRIVATE).edit().putString(KEY,limited.toString()).apply();
  }
}
