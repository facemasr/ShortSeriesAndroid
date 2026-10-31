package com.egytube.rebuilt;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Message;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.util.concurrent.atomic.AtomicBoolean;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Five user-supplied creative slots with clearly marked ad containers.
 * User-initiated links open in an external browser, never over the media player.
 * Third-party scripts are not granted native Javascript bridges or permissions.
 */
public final class AdSlots {
    public static final int RECT_300x250 = 0;
    public static final int BANNER_468x60 = 1;
    public static final int PLAYER_320x50 = 2;
    public static final int BONEPA_4 = 3;
    public static final int AADS_320x100 = 4;
    // Additional user-supplied placements, isolated from the player surface.
    public static final int NATIVE_300x250 = 5;
    public static final int NETWORK_SCRIPT = 6;
    public static final int SPONSORED_LINK = 7;
    public static final int NETWORK_WIDE_468x60 = 8;
    public static final int NETWORK_MOBILE_320x50 = 9;
    private static final String DATA_SCRIPT = "https://data527.click/js/responsive.js";
    private AdSlots() {}

    public static LinearLayout create(Activity activity, int type) {
        LinearLayout wrapper = new LinearLayout(activity);
        wrapper.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(activity, 10);
        wrapper.setPadding(pad, dp(activity,9), pad, dp(activity,9));
        wrapper.setBackgroundColor(0xfff8f8f8);
        TextView caption = new TextView(activity);
        caption.setText("إعلان");
        caption.setTextColor(0xff777777);
        caption.setTextSize(11);
        caption.setPadding(dp(activity,4),0,dp(activity,4),dp(activity,4));
        wrapper.addView(caption);
        if(type==SPONSORED_LINK){
            TextView link=new TextView(activity);
            link.setText("↗  عرض الإعلان المموّل في المتصفح");
            link.setTextSize(14);
            link.setTextColor(0xffd82033);
            link.setPadding(dp(activity,12),dp(activity,15),dp(activity,12),dp(activity,15));
            link.setContentDescription("رابط إعلاني خارجي. لن يفتح إلا عند الضغط عليه");
            wrapper.addView(link);
            link.setOnClickListener(v->openBrowser(activity,Uri.parse(
                "https://astrayentireillegimateillegimate.com/qb38ute8?key=4ea2e7f9933440d5d1130955eff103c3")));
            return wrapper;
        }
        WebView webView=new WebView(activity);
        webView.setBackgroundColor(0xfff8f8f8);
        int height =
            (type==RECT_300x250||type==NATIVE_300x250)?260:
            (type==BANNER_468x60||type==NETWORK_WIDE_468x60)?78:
            (type==PLAYER_320x50||type==NETWORK_MOBILE_320x50)?64:
            type==NETWORK_SCRIPT?130:108;
        wrapper.addView(webView,new LinearLayout.LayoutParams(-1,dp(activity,height)));
        loadInto(webView,type);
        return wrapper;
    }

    public static void loadInto(WebView webView,int placement){
        WebSettings settings=webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(false);
        settings.setSupportMultipleWindows(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSafeBrowsingEnabled(true);
        final long[] lastTouch={0};
        // Prevent repeated browser windows for the same ad redirect.
        final String[] lastOpened={""};
        final long[] lastOpenedAt={0};
        java.util.function.Consumer<Uri> visit = uri -> {
            if(uri==null)return;
            String u=uri.toString();
            long now=SystemClock.uptimeMillis();
            if(u.equals(lastOpened[0]) && now-lastOpenedAt[0]<1500)return;
            lastOpened[0]=u;lastOpenedAt[0]=now;
            openBrowser(webView.getContext(),uri);
        };
        webView.setOnTouchListener((v,event)->{
            if(event.getAction()==MotionEvent.ACTION_UP)lastTouch[0]=SystemClock.uptimeMillis();
            return false;
        });
        webView.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                boolean clicked=request.hasGesture() ||
                    (lastTouch[0]!=0 && SystemClock.uptimeMillis()-lastTouch[0]<1800);
                // Intercept intentional navigation in the main document AND ad iframes.
                // Do not promote automatic redirects or unsolicited popup destinations.
                if(clicked)visit.accept(request.getUrl());
                return clicked || request.isForMainFrame();
            }
        });
        webView.setWebChromeClient(new WebChromeClient(){
            @Override public boolean onCreateWindow(WebView source,boolean isDialog,boolean isUserGesture,Message resultMsg){
                // Refuse popups not initiated by the viewer.
                if(!isUserGesture)return false;
                WebView popup=new WebView(source.getContext());
                final AtomicBoolean handled=new AtomicBoolean(false);
                java.util.function.Consumer<Uri> openOnce=uri->{
                    if(handled.compareAndSet(false,true))visit.accept(uri);
                };
                popup.getSettings().setJavaScriptEnabled(false);
                popup.setWebViewClient(new WebViewClient(){
                    @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                        if(request.isForMainFrame())openOnce.accept(request.getUrl());
                        return true;
                    }
                    @Override public void onPageStarted(WebView view,String url,android.graphics.Bitmap favicon){
                        if(url!=null&&!url.startsWith("about:"))openOnce.accept(Uri.parse(url));
                        view.stopLoading();
                        view.post(view::destroy);
                    }
                });
                WebView.WebViewTransport transport=(WebView.WebViewTransport)resultMsg.obj;
                transport.setWebView(popup);
                resultMsg.sendToTarget();
                return true;
            }
        });
        String html=creative(placement);
        String base=placement==BONEPA_4?"https://bonepa.com/":
            placement==AADS_320x100?"https://ad.a-ads.com/":
            (placement==NATIVE_300x250||placement==NETWORK_SCRIPT)?"https://astrayentireillegimateillegimate.com/":
            (placement==NETWORK_WIDE_468x60||placement==NETWORK_MOBILE_320x50)?"https://bancadeltempoidea.org/":
            "https://data527.click/";
        webView.loadDataWithBaseURL(base,html,"text/html","UTF-8",null);
    }

    private static void openBrowser(Context context,Uri uri){
        if(uri==null)return;
        String scheme=uri.getScheme();
        if(!"https".equalsIgnoreCase(scheme)&&!"http".equalsIgnoreCase(scheme))return;
        try {
            Intent intent=new Intent(Intent.ACTION_VIEW,uri);
            intent.addCategory(Intent.CATEGORY_BROWSABLE);
            if(!(context instanceof Activity))intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
        } catch(Exception ignored) { }
    }
    private static String creative(int slot){
        String header="<!doctype html><html lang='ar'><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"+
            "<body style='margin:0;padding:2px;background:#f8f8f8;overflow:hidden;text-align:center'>";
        String footer="</body></html>";
        // Native, scripted and banner creatives load only in marked, fixed-size
        // WebViews. They cannot create unsolicited browser windows or affect player taps.
        if(slot==NATIVE_300x250){
            return header+
                "<div id='container-f2d83af2e65a70897bc7682d2a8aa66e' style='max-width:100%;min-height:250px'></div>"+
                "<script async data-cfasync='false' src='https://astrayentireillegimateillegimate.com/f2d83af2e65a70897bc7682d2a8aa66e/invoke.js'></script>"+footer;
        }
        if(slot==NETWORK_SCRIPT){
            return header+
                "<div style='font-size:11px;color:#777'>مساحة إعلانية</div>"+
                "<script src='https://astrayentireillegimateillegimate.com/42/e0/01/42e001815a55634ec456dac693eba30a.js'></script>"+footer;
        }
        if(slot==NETWORK_WIDE_468x60){
            return header+
                "<div id='newwide' style='width:468px;height:60px;transform-origin:top left'>"+
                "<script>window.atOptions={key:'e221bdfd44d439c4b0cd8a3d93745882',format:'iframe',height:60,width:468,params:{}};</script>"+
                "<script src='https://bancadeltempoidea.org/22/e221bdfd44d439c4b0cd8a3d93745882'></script></div>"+
                "<script>var e=document.getElementById('newwide');e.style.transform='scale('+Math.min(1,(document.documentElement.clientWidth-12)/468)+')';</script>"+footer;
        }
        if(slot==NETWORK_MOBILE_320x50){
            return header+
                "<div style='width:320px;max-width:100%;height:50px;margin:auto'>"+
                "<script>window.atOptions={key:'220d0e40b38592136c3d8d9ff3111157',format:'iframe',height:50,width:320,params:{}};</script>"+
                "<script src='https://bancadeltempoidea.org/22/220d0e40b38592136c3d8d9ff3111157'></script></div>"+footer;
        }
        if(slot==RECT_300x250){
            return header+
               "<ins style='width:300px;height:250px' data-width='300' data-height='250' class='zbdb0fb2d79'"+
               " data-domain='//data527.click' data-affquery='/6782610a11f54f817b52/bdb0fb2d79/?placementName=default'></ins>"+
               "<script async src='"+DATA_SCRIPT+"'></script>"+footer;
        }
        if(slot==BANNER_468x60){
            return header+
               "<div id='wide' style='width:468px;height:60px;transform-origin:top left;position:relative'>"+
               "<ins style='width:468px;height:60px' data-width='468' data-height='60' class='efcafa07e48'"+
               " data-domain='//data527.click' data-affquery='/24c433963a2c516b9146/fcafa07e48/?placementName=default'></ins></div>"+
               "<script>var el=document.getElementById('wide');var s=Math.min(1,(document.documentElement.clientWidth-10)/468);el.style.transform='scale('+s+')';</script>"+
               "<script async src='"+DATA_SCRIPT+"'></script>"+footer;
        }
        if(slot==PLAYER_320x50){
            return header+
               "<ins style='width:320px;height:50px' data-width='320' data-height='50' class='w34be394bb1'"+
               " data-domain='//data527.click' data-affquery='/e3ed80826e23881d9411/34be394bb1/?placementName=default'></ins>"+
               "<script async src='"+DATA_SCRIPT+"'></script>"+footer;
        }
        if(slot==AADS_320x100){
            // Inline unit: never overlay the media player or hijack the page.
            return header+
                "<div style='width:100%;max-width:320px;height:100px;margin:auto;overflow:hidden'>"+
                "<iframe data-aa='2460254' src='https://ad.a-ads.com/2460254/?size=320x100' "+
                "title='إعلان' loading='lazy' style='border:0;padding:0;width:320px;height:100px;max-width:100%;"+
                "display:block;margin:auto;overflow:hidden'></iframe></div>"+footer;
        }
        return header+"<script src='https://bonepa.com/2de39a55427445e4c1ee/23caae49eb/?placementName=default'></script>"+footer;
    }
    private static int dp(Context context,int px){return (int)(context.getResources().getDisplayMetrics().density*px+0.5f);}
}
