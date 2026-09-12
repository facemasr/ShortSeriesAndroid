package online.shortseris.app;

import android.view.View;
import android.webkit.WebChromeClient;
import android.webkit.WebView;

public class AppChromeClient extends WebChromeClient {
    private final MainActivity activity;
    private CustomViewCallback callback;
    AppChromeClient(MainActivity activity){this.activity=activity;}

    @Override public void onProgressChanged(WebView view,int value){
        activity.progress.setVisibility(value<100?View.VISIBLE:View.GONE);
        activity.progress.setProgress(value);
    }

    @Override public void onShowCustomView(View view,CustomViewCallback cb){
        callback=cb;
        activity.showFullscreen(view);
    }

    @Override public void onHideCustomView(){
        activity.hideFullscreen();
        if(callback!=null) callback.onCustomViewHidden();
        callback=null;
    }
}
