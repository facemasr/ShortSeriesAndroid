package com.egytube.rebuilt

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.BitmapFactory
import android.content.Context
import android.net.Uri
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.app.PictureInPictureParams
import android.util.Rational
import android.view.MotionEvent
import android.content.res.Configuration
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.WebView
import android.widget.*
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.Locale

/**
 * A native in-page YouTube-style watch surface.
 * MainActivity remains visible underneath and retains scroll/search state.
 * It does not contain YouTube's embedded player or navigate to a web watch page.
 */
@OptIn(UnstableApi::class)
class NativeWatchView(private val host: MainActivity, private val exit: Runnable) : LinearLayout(host) {
    private val worker = Executors.newSingleThreadExecutor()
    private val images = Executors.newFixedThreadPool(2)
    private val player = ExoPlayer.Builder(host).build()
    private val mediaView = PlayerView(host)
    private val viewport = FrameLayout(host)
    private val below = LinearLayout(host)
    private val details = ScrollView(host)
    private val suggestions = LinearLayout(host)
    private val heading = TextView(host)
    private val creator = TextView(host)
    private val state = TextView(host)
    private val qualityButton = text("⚙ جودة",13f,Color.WHITE)
    private val expandButton = text("⛶",27f,Color.WHITE)
    private val fitButton = text("↔ ملاءمة",12f,Color.WHITE)
    private val speedButton = text("1.0×",13f,Color.WHITE)
    private val pipButton = text("▣",19f,Color.WHITE)
    private val overlayControls = LinearLayout(host)
    private val backwardButton = text("↶10",16f,Color.WHITE)
    private val forwardButton = text("10↷",16f,Color.WHITE)
    private val uiHandler = Handler(Looper.getMainLooper())
    private val autoHide = Runnable { if(!shutdown && !pipActive && player.isPlaying) setChromeVisibility(false) }
    private var pipActive = false
    private var playingRate = 1.0f
    private val progressSaver = object: Runnable {
      override fun run() {
        if(shutdown)return
        rememberPosition()
        uiHandler.postDelayed(this,5000L)
      }
    }
    private val advertisement = WebView(host)
    private val formats = mutableListOf<Source>()
    private var active = -1
    private var ticket = 0
    private var videoId = ""
    private var videoTitle = ""
    private var zoomed = false
    private var fullscreen = false
    private var videoWidth = 16
    private var videoHeight = 9
    private var shutdown = false
    private lateinit var adContainer:LinearLayout
    private val colorText = Color.rgb(25,25,25)
    private fun dp(x:Int)=(x*resources.displayMetrics.density+.5f).toInt()
    private fun text(value:String, size:Float, fg:Int=Color.BLACK):TextView {
      val t=TextView(host);t.text=value;t.textSize=size;t.setTextColor(fg);t.gravity=Gravity.CENTER_VERTICAL
      return t
    }
    private fun padding(v:View,a:Int,b:Int,c:Int,d:Int){v.setPadding(dp(a),dp(b),dp(c),dp(d))}
    init {
      orientation=VERTICAL
      setBackgroundColor(Color.WHITE)
      layoutDirection=View.LAYOUT_DIRECTION_RTL

      viewport.setBackgroundColor(Color.BLACK)
      mediaView.player=player
      mediaView.useController=true
      mediaView.resizeMode=AspectRatioFrameLayout.RESIZE_MODE_FIT
      mediaView.controllerShowTimeoutMs=4000
      mediaView.setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
      host.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      player.setHandleAudioBecomingNoisy(true)
      viewport.addView(mediaView,FrameLayout.LayoutParams(-1,-1))

      // Overlay controls live inside the player, independently of the page below.
      val chrome=overlayControls
      chrome.orientation=HORIZONTAL
      chrome.gravity=Gravity.CENTER_VERTICAL
      chrome.setBackgroundColor(0x880a0b10.toInt())
      padding(chrome,3,3,3,3)
      val back=text("‹",30f,Color.WHITE)
      back.gravity=Gravity.CENTER
      chrome.addView(back,LinearLayout.LayoutParams(dp(42),dp(39)))
      back.setOnClickListener { if(fullscreen)exitFullScreen() else exit.run() }
      val space=Space(host)
      chrome.addView(space,LinearLayout.LayoutParams(0,dp(1),1f))
      qualityButton.gravity=Gravity.CENTER
      padding(qualityButton,5,5,5,5)
      chrome.addView(qualityButton,LinearLayout.LayoutParams(-2,dp(39)))
      qualityButton.setOnClickListener { showChrome();showQuality() }
      speedButton.gravity=Gravity.CENTER
      padding(speedButton,4,4,4,4)
      chrome.addView(speedButton,LinearLayout.LayoutParams(dp(45),dp(39)))
      speedButton.setOnClickListener{showChrome();showSpeedOptions()}
      pipButton.gravity=Gravity.CENTER
      pipButton.contentDescription="تشغيل الفيديو في نافذة عائمة PiP"
      chrome.addView(pipButton,LinearLayout.LayoutParams(dp(37),dp(39)))
      pipButton.setOnClickListener{enterPictureInPicture()}
      fitButton.gravity=Gravity.CENTER
      padding(fitButton,6,5,6,5)
      chrome.addView(fitButton,LinearLayout.LayoutParams(-2,dp(39)))
      fitButton.setOnClickListener{ showChrome();zoomed=!zoomed;mediaView.resizeMode=if(zoomed)AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT;fitButton.text=if(zoomed)"↔ احتواء" else "↔ ملاءمة" }
      expandButton.gravity=Gravity.CENTER
      chrome.addView(expandButton,LinearLayout.LayoutParams(dp(45),dp(39)))
      expandButton.setOnClickListener { showChrome();setFull(!fullscreen) }
      viewport.addView(chrome,FrameLayout.LayoutParams(-1,dp(45),Gravity.TOP))
      // Ten-second transport controls sit at the sides of the video, away from ExoPlayer seekbar.
      backwardButton.gravity=Gravity.CENTER
      backwardButton.setBackgroundColor(0x44000000)
      backwardButton.contentDescription="الرجوع عشر ثوانٍ"
      val backPosition=FrameLayout.LayoutParams(dp(53),dp(47),Gravity.LEFT or Gravity.CENTER_VERTICAL)
      backPosition.leftMargin=dp(12)
      viewport.addView(backwardButton,backPosition)
      backwardButton.setOnClickListener{skipBy(-10000L)}
      forwardButton.gravity=Gravity.CENTER
      forwardButton.setBackgroundColor(0x44000000)
      forwardButton.contentDescription="التقدم عشر ثوانٍ"
      val forwardPosition=FrameLayout.LayoutParams(dp(53),dp(47),Gravity.RIGHT or Gravity.CENTER_VERTICAL)
      forwardPosition.rightMargin=dp(12)
      viewport.addView(forwardButton,forwardPosition)
      forwardButton.setOnClickListener{skipBy(10000L)}
      mediaView.setOnTouchListener{_,event->
        if(event.actionMasked==MotionEvent.ACTION_DOWN)showChrome()
        false
      }
      addView(viewport,LinearLayout.LayoutParams(-1,dp(220)))

      val adBox=LinearLayout(host)
      adBox.orientation=VERTICAL
      val adLabel=text("إعلان",11f,0xff777777.toInt())
      padding(adLabel,12,2,12,2)
      adBox.addView(adLabel)
      AdSlots.loadInto(advertisement,AdSlots.PLAYER_320x50)
      adBox.addView(advertisement,LinearLayout.LayoutParams(-1,dp(58)))
      addView(adBox,LinearLayout.LayoutParams(-1,dp(79)))
      adContainer=adBox

      below.orientation=VERTICAL
      details.isFillViewport=true
      details.addView(below)
      addView(details,LinearLayout.LayoutParams(-1,0,1f))
      padding(heading,15,14,15,7)
      heading.textSize=19f;heading.setTextColor(colorText)
      heading.setTypeface(null,android.graphics.Typeface.BOLD)
      below.addView(heading,LinearLayout.LayoutParams(-1,-2))
      padding(creator,15,6,15,9)
      creator.textSize=14f;creator.setTextColor(0xff666666.toInt())
      below.addView(creator)
      val actions=LinearLayout(host)
      actions.gravity=Gravity.CENTER_VERTICAL
      padding(actions,10,2,10,11)
      val share=text("↗ مشاركة",14f,colorText)
      padding(share,10,9,10,9);actions.addView(share,LinearLayout.LayoutParams(0,-2,1f))
      share.setOnClickListener{
        val i=Intent(Intent.ACTION_SEND)
        i.type="text/plain";i.putExtra(Intent.EXTRA_TEXT,"https://www.youtube.com/watch?v=$videoId")
        host.startActivity(Intent.createChooser(i,"مشاركة"))
      }
      val favorite=text("☆ حفظ",14f,colorText)
      padding(favorite,10,9,10,9);actions.addView(favorite,LinearLayout.LayoutParams(0,-2,1f))
      favorite.setOnClickListener{
        val p=host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
        p.edit().putString("lastSavedVideo","https://www.youtube.com/watch?v=$videoId").apply()
        Toast.makeText(host,"تم حفظ رابط الفيديو",Toast.LENGTH_SHORT).show()
      }
      val like=text("♡ إعجاب",14f,colorText)
      padding(like,10,9,10,9);actions.addView(like,LinearLayout.LayoutParams(0,-2,1f))
      like.setOnClickListener{like.text=if(like.text.toString().startsWith("♡"))"♥ أعجبني" else "♡ إعجاب"}
      below.addView(actions)
      val divider=View(host);divider.setBackgroundColor(0xffededed.toInt())
      below.addView(divider,LinearLayout.LayoutParams(-1,dp(1)))
      padding(state,15,12,15,12)
      state.textSize=13f;state.setTextColor(0xff666666.toInt())
      below.addView(state)
      val suggested=text("الفيديوهات المقترحة",18f,colorText)
      padding(suggested,15,12,15,13);below.addView(suggested)
      suggestions.orientation=VERTICAL
      below.addView(suggestions)
      player.addListener(object:Player.Listener {
        override fun onPlayerError(error:PlaybackException){
          state.text="تعذر تشغيل المصدر الحالي: ${error.errorCodeName}"
          showChrome()
        }
        override fun onIsPlayingChanged(isPlaying:Boolean){
          if(isPlaying)scheduleChromeHide() else showChrome()
          updatePiPParameters()
        }
        override fun onPlaybackStateChanged(s:Int){
          if(s==Player.STATE_READY)state.text="جاري تشغيل الفيديو · ${formats.getOrNull(active)?.label.orEmpty()}"
          if(s==Player.STATE_ENDED){forgetPosition();showChrome()}
        }
        override fun onVideoSizeChanged(size:VideoSize){
          if(size.width>0&&size.height>0){
            videoWidth=(size.width*size.pixelWidthHeightRatio).toInt().coerceAtLeast(1);videoHeight=size.height
            resize()
            updatePiPParameters()
          }
        }
      })
      resize()
      uiHandler.postDelayed(progressSaver,5000L)
      showChrome()
    }

    fun openVideo(id:String,title:String,channel:String){
      if(!Regex("[A-Za-z0-9_-]{11}").matches(id))return
      if(videoId.isNotEmpty())rememberPosition()
      videoId=id;videoTitle=title
      heading.text=title;creator.text=channel
      ticket++
      val token=ticket
      formats.clear();active=-1
      qualityButton.text="⚙ جودة"
      showChrome()
      videoWidth=if(title.contains("Shorts",true))9 else 16
      videoHeight=if(videoWidth==9)16 else 9
      resize()
      suggestions.removeAllViews()
      state.text="جارٍ تحميل روابط المشاهدة..."
      player.stop();player.clearMediaItems()
      details.scrollTo(0,0)
      worker.execute{
        try{
          val info=StreamInfo.getInfo("https://www.youtube.com/watch?v=$id")
          val sources=options(info)
          val related=info.relatedItems.filterIsInstance<StreamInfoItem>().take(15)
          host.runOnUiThread {
            if(token!=ticket || shutdown || host.isFinishing || host.isDestroyed)return@runOnUiThread
            heading.text=info.name
            creator.text=info.uploaderName
            videoTitle=info.name
            formats.clear();formats.addAll(sources)
            if(info.ageLimit>0){
              state.text="هذا الفيديو مقيد بالعمر ولا يمكن تشغيله هنا"
            }else if(sources.isEmpty()){
              state.text="لا يوجد مصدر قابل للتشغيل لهذا الفيديو"
            }else{
              choose(0)
            }
            showSuggestions(related)
          }
        }catch(e:Exception){
          host.runOnUiThread{
            if(token==ticket && !shutdown)state.text="تعذر تحميل الفيديو: ${e.message?.take(120) ?: "مصدر غير متاح"}"
          }
        }
      }
    }
    private fun showSuggestions(items:List<StreamInfoItem>){
      suggestions.removeAllViews()
      for(item in items){
        val match=Regex("(?:v=|youtu\\.be/|shorts/)([A-Za-z0-9_-]{11})").find(item.url)
        val id=match?.groupValues?.get(1)?:continue
        val card=LinearLayout(host);card.orientation=HORIZONTAL;card.gravity=Gravity.CENTER_VERTICAL
        padding(card,10,7,10,9)
        val img=ImageView(host);img.scaleType=ImageView.ScaleType.CENTER_CROP
        img.setBackgroundColor(0xffeeeeee.toInt())
        card.addView(img,LinearLayout.LayoutParams(dp(148),dp(85)))
        val thumb=item.thumbnails.firstOrNull()?.url
        if(!thumb.isNullOrEmpty()){
          images.execute{
            try{
              val c=URL(thumb).openConnection() as HttpURLConnection
              c.connectTimeout=6000;c.readTimeout=6000
              val bmp=c.inputStream.use{BitmapFactory.decodeStream(it)}
              c.disconnect()
              host.runOnUiThread{if(!shutdown)img.setImageBitmap(bmp)}
            }catch(_:Exception){}
          }
        }
        val texts=LinearLayout(host);texts.orientation=VERTICAL
        padding(texts,11,2,11,2)
        val title=text(item.name,14f,colorText)
        title.maxLines=3;title.ellipsize=android.text.TextUtils.TruncateAt.END
        texts.addView(title)
        val subtitle=text(item.uploaderName.orEmpty(),12f,0xff777777.toInt())
        padding(subtitle,0,6,0,0);texts.addView(subtitle)
        card.addView(texts,LinearLayout.LayoutParams(0,-2,1f))
        card.setOnClickListener{host.playFromWatch(item.url,item.name,item.uploaderName.orEmpty())}
        suggestions.addView(card)
      }
      if(suggestions.childCount==0){
        val none=text("لا توجد اقتراحات متاحة لهذا الفيديو",13f,0xff777777.toInt())
        padding(none,15,14,15,15);suggestions.addView(none)
      }
    }
    private fun options(info:StreamInfo):List<Source>{
      val available=mutableListOf<Source>()
      if(!info.hlsUrl.isNullOrBlank()&&info.hlsUrl.startsWith("https://"))
        available+=Source("تلقائي · HLS",info.hlsUrl,mime=MimeTypes.APPLICATION_M3U8)
      if(!info.dashMpdUrl.isNullOrBlank()&&info.dashMpdUrl.startsWith("https://"))
        available+=Source("تلقائي · DASH",info.dashMpdUrl,mime=MimeTypes.APPLICATION_MPD)
      info.videoStreams.filter{it.isUrl&&it.content.startsWith("https://")&&!it.isVideoOnly}
        .sortedByDescending{it.height}
        .forEach{available+=Source("${it.resolution} · صوت وصورة",it.content)}
      val audio=info.audioStreams.filter{it.isUrl&&it.content.startsWith("https://")}
      info.videoOnlyStreams.filter{it.isUrl&&it.content.startsWith("https://")}
        .sortedByDescending{it.height}
        .forEach{v->
          val webm=v.format?.name.orEmpty().contains("WEBM")
          val track=audio.filter{it.format?.name.orEmpty().contains("WEBM")==webm}.maxByOrNull{it.averageBitrate}
            ?:audio.maxByOrNull{it.averageBitrate}
          if(track!=null)available+=Source("${v.resolution} · فيديو + صوت",v.content,track.content)
        }
      return available.distinctBy{it.url+"|"+it.audio}
    }
    private fun showQuality(){
      if(formats.isEmpty()){
        Toast.makeText(host,"الجودات غير متاحة بعد",Toast.LENGTH_SHORT).show();return
      }
      AlertDialog.Builder(host)
        .setTitle("جودة الفيديو")
        .setSingleChoiceItems(formats.map{it.label}.toTypedArray(),active){d,index->
          choose(index);d.dismiss()
        }.setNegativeButton("إلغاء",null).show()
    }
    private fun choose(index:Int){
      if(index !in formats.indices || shutdown)return
      val position=if(active>=0)player.currentPosition else host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE).getLong("resume_$videoId",0L)
      val src=formats[index]
      active=index
      qualityButton.text="⚙ ${src.label.substringBefore(' ')}"
      val ds=DefaultDataSource.Factory(host,DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true))
      fun direct(u:String):MediaSource=ProgressiveMediaSource.Factory(ds).createMediaSource(MediaItem.fromUri(u))
      val media:MediaSource=when(src.mime){
        MimeTypes.APPLICATION_M3U8->HlsMediaSource.Factory(ds).createMediaSource(
           MediaItem.Builder().setUri(src.url).setMimeType(MimeTypes.APPLICATION_M3U8).build())
        MimeTypes.APPLICATION_MPD->DashMediaSource.Factory(ds).createMediaSource(
           MediaItem.Builder().setUri(src.url).setMimeType(MimeTypes.APPLICATION_MPD).build())
        else->if(src.audio!=null)MergingMediaSource(direct(src.url),direct(src.audio))else direct(src.url)
      }
      state.text="جارٍ تشغيل ${src.label}"
      player.setMediaSource(media)
      player.prepare()
      if(position>0)player.seekTo(position)
      player.playWhenReady=true
      showChrome()
    }
    private fun showSpeedOptions(){
      val speeds=floatArrayOf(0.5f,0.75f,1f,1.25f,1.5f,2f)
      val labels=speeds.map{String.format(Locale.US,"%.2g×",it)}.toTypedArray()
      val chosen=speeds.indexOfFirst{it==playingRate}.coerceAtLeast(0)
      AlertDialog.Builder(host).setTitle("سرعة التشغيل")
        .setSingleChoiceItems(labels,chosen){dialog,index->
          playingRate=speeds[index]
          player.setPlaybackSpeed(playingRate)
          speedButton.text=String.format(Locale.US,"%.2g×",playingRate)
          dialog.dismiss()
          showChrome()
        }.setNegativeButton("إلغاء",null).show()
    }
    private fun skipBy(delta:Long){
      if(player.currentMediaItem==null)return
      val max=if(player.duration>0)player.duration else Long.MAX_VALUE
      player.seekTo((player.currentPosition+delta).coerceIn(0L,max))
      showChrome()
    }
    private fun setChromeVisibility(visible:Boolean){
      overlayControls.visibility=if(visible)View.VISIBLE else View.GONE
      backwardButton.visibility=if(visible)View.VISIBLE else View.GONE
      forwardButton.visibility=if(visible)View.VISIBLE else View.GONE
    }
    private fun showChrome(){
      if(pipActive)return
      uiHandler.removeCallbacks(autoHide)
      setChromeVisibility(true)
      scheduleChromeHide()
    }
    private fun scheduleChromeHide(){
      uiHandler.removeCallbacks(autoHide)
      if(!pipActive && player.isPlaying)uiHandler.postDelayed(autoHide,4500L)
    }
    private fun rememberPosition(){
      if(videoId.isEmpty() || player.currentMediaItem==null)return
      val now=player.currentPosition
      if(now>2500L && (player.duration<=0L || now<player.duration-5000L)){
        host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE).edit().putLong("resume_$videoId",now).apply()
      }
    }
    private fun forgetPosition(){
      host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE).edit().remove("resume_$videoId").apply()
    }
    private fun pipRatio():Rational{
      val ratio=videoWidth.toFloat()/videoHeight.coerceAtLeast(1).toFloat()
      return when{
        ratio>2.39f ->Rational(239,100)
        ratio<0.42f ->Rational(42,100)
        else->Rational(videoWidth.coerceAtLeast(1),videoHeight.coerceAtLeast(1))
      }
    }
    private fun updatePiPParameters(){
      if(Build.VERSION.SDK_INT<Build.VERSION_CODES.O || shutdown || player.currentMediaItem==null)return
      try{
        val params=PictureInPictureParams.Builder().setAspectRatio(pipRatio())
        // Android 12+ can enter PiP when the user goes Home during active playback.
        if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.S)params.setAutoEnterEnabled(player.isPlaying)
        host.setPictureInPictureParams(params.build())
      }catch(_:Exception){}
    }
    fun enterPictureInPicture(){
      if(Build.VERSION.SDK_INT<Build.VERSION_CODES.O){
        Toast.makeText(host,"يتطلب وضع الصورة داخل الصورة أندرويد 8 أو أحدث",Toast.LENGTH_SHORT).show()
        return
      }
      if(player.currentMediaItem==null){
        Toast.makeText(host,"يجب تشغيل الفيديو أولاً",Toast.LENGTH_SHORT).show()
        return
      }
      if(fullscreen)setFull(false)
      try{
        val builder=PictureInPictureParams.Builder().setAspectRatio(pipRatio())
        if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.S)builder.setAutoEnterEnabled(true)
        host.enterPictureInPictureMode(builder.build())
      }catch(e:Exception){
        Toast.makeText(host,"لا يتوفر PiP على هذا الجهاز",Toast.LENGTH_SHORT).show()
      }
    }
    fun onPictureInPictureChanged(inPip:Boolean){
      pipActive=inPip
      uiHandler.removeCallbacks(autoHide)
      mediaView.useController=!inPip
      setChromeVisibility(!inPip)
      if(!inPip)showChrome()
      resize()
    }
    fun isPlayingVideo()=player.isPlaying && !shutdown
    private fun resize(){
      if(shutdown)return
      val landscape=resources.configuration.orientation==Configuration.ORIENTATION_LANDSCAPE
      val width=resources.displayMetrics.widthPixels
      val screen=resources.displayMetrics.heightPixels
      val natural=(width.toFloat()*videoHeight.toFloat()/videoWidth.coerceAtLeast(1)).toInt()
      val measured=if(videoHeight>videoWidth)natural.coerceIn(dp(230),(screen*0.62).toInt())
                   else natural.coerceIn(dp(170),(screen*0.42).toInt())
      val params=viewport.layoutParams as? LayoutParams ?:LayoutParams(-1,measured)
      params.height=if(pipActive)ViewGroup.LayoutParams.MATCH_PARENT else if(fullscreen)screen else if(landscape)(screen*0.78).toInt() else measured
      viewport.layoutParams=params
      below.visibility=if(fullscreen||pipActive)View.GONE else View.VISIBLE
      details.visibility=if(fullscreen||pipActive)View.GONE else View.VISIBLE
      adContainer.visibility=if(fullscreen||pipActive)View.GONE else View.VISIBLE
    }
    private fun setFull(enabled:Boolean){
      fullscreen=enabled
      val decor=host.window.decorView
      decor.systemUiVisibility=if(enabled)
         (View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)
         else (View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR)
      host.window.setStatusBarColor(if(enabled)Color.BLACK else Color.WHITE)
      host.window.setNavigationBarColor(if(enabled)Color.BLACK else Color.WHITE)
      expandButton.text=if(enabled)"⤢" else "⛶"
      resize()
    }
    fun isFullScreen()=fullscreen
    fun exitFullScreen(){setFull(false)}
    fun onScreenChanged(){resize()}
    fun release(){
      if(shutdown)return
      rememberPosition()
      shutdown=true;ticket++
      uiHandler.removeCallbacksAndMessages(null)
      host.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      worker.shutdownNow();images.shutdownNow()
      mediaView.player=null
      player.release()
      advertisement.stopLoading();advertisement.destroy()
    }
    private data class Source(val label:String,val url:String,val audio:String?=null,val mime:String?=null)
}
