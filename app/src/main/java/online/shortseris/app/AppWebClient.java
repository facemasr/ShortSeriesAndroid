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
        String js="(function(){var s=document.createElement('style');s.innerHTML='.topbar,.mobile-nav,.mobile-drawer{display:none!important}body{padding-top:0!important;padding-bottom:0!important}';document.head.appendChild(s)})();";
        view.evaluateJavascript(js,null);
    }
}
