package online.shortseris.app;

import android.content.Intent;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class AppWebClient extends WebViewClient {
    private final MainActivity activity;
    AppWebClient(MainActivity activity){this.activity=activity;}

    @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request){
        Uri u=request.getUrl();
        String host=u.getHost()==null?"":u.getHost();
        if(host.equals("shortseris.online")||host.equals("www.shortseris.online")) return false;
        try{ activity.startActivity(new Intent(Intent.ACTION_VIEW,u)); return true; }catch(Exception e){ return false; }
    }

    @Override public void onPageFinished(WebView view,String url){
        activity.progress.setVisibility(android.view.View.GONE);
        String js="(function(){document.documentElement.setAttribute('data-shortseries-app','1');var s=document.createElement('style');s.innerHTML='.topbar,.mobile-nav,.mobile-drawer,#ssAppDownload,.ss-app-download{display:none!important}body{padding-top:0!important;padding-bottom:0!important}';document.head.appendChild(s);var a=document.getElementById('ssAppDownload');if(a)a.remove()})();";
        view.evaluateJavascript(js,null);
    }
}
