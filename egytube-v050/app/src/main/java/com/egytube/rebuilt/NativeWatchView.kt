package com.egytube.rebuilt

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.BitmapFactory
import android.content.Context
import android.net.Uri
import android.graphics.Color
import android.media.AudioManager
import androidx.media3.common.C
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.app.PictureInPictureParams
import android.util.Rational
import android.view.MotionEvent
import android.view.GestureDetector
import android.graphics.drawable.GradientDrawable
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.WebView
import android.widget.*
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import android.graphics.Rect
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
import android.util.Log

/**
 * A native in-page YouTube-style watch surface.
 * MainActivity remains visible underneath and retains scroll/search state.
 * It does not contain YouTube's embedded player or navigate to a web watch page.
 */
@OptIn(UnstableApi::class)
class NativeWatchView(private val host: MainActivity, private val exit: Runnable) : LinearLayout(host) {
    companion object {
      private val sourceLock=Any()
      private val recentInfo=LinkedHashMap<String,Pair<Long,StreamInfo>>()
      private const val SOURCE_CACHE_MS=75_000L
      private fun cachedInfo(videoId:String):StreamInfo?=synchronized(sourceLock){
        val entry=recentInfo[videoId]
        if(entry!=null && android.os.SystemClock.elapsedRealtime()-entry.first<SOURCE_CACHE_MS)
          entry.second else null
      }
      private fun storeInfo(videoId:String,info:StreamInfo)=synchronized(sourceLock){
        recentInfo[videoId]=android.os.SystemClock.elapsedRealtime() to info
        while(recentInfo.size>4)recentInfo.remove(recentInfo.keys.first())
      }
    }
    private val worker = Executors.newSingleThreadExecutor()
    private val recoveryWorker=Executors.newSingleThreadExecutor()
    private val images = Executors.newFixedThreadPool(2)
    private val player = PlaybackCore.get(host)
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
    private val centerPlay = text("▶",27f,Color.WHITE)
    private val seekFeedback = text("",18f,Color.WHITE)
    private val fastBadge = text("2×  تشغيل سريع",15f,Color.WHITE)
    private var holdSpeedActive=false
    private var speedBeforeHold=1f
    private var miniTarget:ViewGroup?=null
    private val lowerToolbar = LinearLayout(host)
    private val toolbarPlay = text("▶",20f,Color.WHITE)
    private val nextButton = text("⏭",19f,Color.WHITE)
    private val volumeButton = text("◖))",16f,Color.WHITE)
    private val volumeBar = SeekBar(host)
    private val compactClock = text("0:00 / 0:00",12f,Color.WHITE)
    private val captionsButton = text("CC",13f,Color.WHITE)
    private val settingsButton = text("⚙",22f,Color.WHITE)
    private val audioManager = host.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var previousVolume=4
    private var captionsEnabled=false
    private var relatedChoices:List<StreamInfoItem> = emptyList()
    private val recentlyPlayedIds=LinkedHashSet<String>()
    private var lastEndedTicket=-1
    private var lastBackgroundSaveAt=0L
    private var lastPauseAt=0L
    private var resumeRecoveryAttempted=false
    private var recoveryInFlight=false
    private var resumeWatchdog:Runnable?=null
    private var resumeRecoveryPosition=0L
    private var openAsPaused=false
    private val bottomLayer = LinearLayout(host)
    private val timeline = SeekBar(host)
    private val elapsed = text("0:00",12f,Color.WHITE)
    private val total = text("0:00",12f,Color.WHITE)
    private val spinner = ProgressBar(host)
    private val settingsPanel = LinearLayout(host)
    private var settingsOpen=false
    private var scrubbing=false
    private var controlsVisible=true
    private val progressTicker = object:Runnable {
      override fun run(){
        if(shutdown)return
        updateTime()
        uiHandler.postDelayed(this,650L)
      }
    }
    private val backwardButton = text("↶10",16f,Color.WHITE)
    private val forwardButton = text("10↷",16f,Color.WHITE)
    private val uiHandler = Handler(Looper.getMainLooper())
    private val autoHide = Runnable { if(!shutdown && !pipActive && player.isPlaying && !scrubbing && !settingsOpen) setChromeVisibility(false) }
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
    // Lowest-bandwidth standalone audio stream, resolved with video metadata.
    private var lowDataAudioUrl:String?=null
    private var active = -1
    private val unsuccessfulSources=mutableSetOf<Int>()
    private var fallbackResumeMs=0L
    private var fallbackIsPending=false
    private var ticket = 0
    private var videoId = ""
    private var videoTitle = ""
    private var zoomed = false
    private var fullscreen = false
    private var videoWidth = 16
    private var videoHeight = 9
    private var shutdown = false
    private lateinit var adContainer:LinearLayout
    private lateinit var playerListener:Player.Listener
    private val colorText = Color.rgb(25,25,25)
    private fun dp(x:Int)=(x*resources.displayMetrics.density+.5f).toInt()
    private fun text(value:String, size:Float, fg:Int=Color.BLACK):TextView {
      val t=TextView(host);t.text=value;t.textSize=size;t.setTextColor(fg);t.gravity=Gravity.CENTER_VERTICAL
      return t
    }
    private fun padding(v:View,a:Int,b:Int,c:Int,d:Int){v.setPadding(dp(a),dp(b),dp(c),dp(d))}
    init {
      PlaybackCore.attachUi()
      orientation=VERTICAL
      setBackgroundColor(Color.WHITE)
      layoutDirection=View.LAYOUT_DIRECTION_RTL

      viewport.setBackgroundColor(Color.BLACK)
      mediaView.player=player
      mediaView.useController=false
      mediaView.resizeMode=AspectRatioFrameLayout.RESIZE_MODE_FIT
      mediaView.setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
      host.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      player.setHandleAudioBecomingNoisy(true)
      viewport.addView(mediaView,FrameLayout.LayoutParams(-1,-1))
      val detector=GestureDetector(host,object:GestureDetector.SimpleOnGestureListener(){
        override fun onDown(e:MotionEvent)=true
        override fun onSingleTapConfirmed(e:MotionEvent):Boolean {
          if(settingsOpen)closeSettings()
          else if(controlsVisible)setChromeVisibility(false)
          else showChrome()
          return true
        }
        override fun onDoubleTap(e:MotionEvent):Boolean {
          val backwards=e.x<viewport.width/2f
          skipBy(if(backwards)-10000L else 10000L,false)
          flashSeekFeedback(if(backwards)"−10 ثوانٍ" else "+10 ثوانٍ")
          return true
        }
        override fun onLongPress(e:MotionEvent){
          if(!shutdown && miniTarget==null && player.currentMediaItem!=null && player.isPlaying && !holdSpeedActive){
            speedBeforeHold=player.playbackParameters.speed
            holdSpeedActive=true
            player.setPlaybackSpeed(2f)
            fastBadge.visibility=View.VISIBLE
            fastBadge.alpha=1f
            uiHandler.removeCallbacks(autoHide)
          }
        }
      })
      val gestureSurface=View(host)
      gestureSurface.isClickable=true
      gestureSurface.setOnTouchListener{_,e->
        detector.onTouchEvent(e)
        if(e.actionMasked==MotionEvent.ACTION_UP || e.actionMasked==MotionEvent.ACTION_CANCEL)restoreHoldSpeed()
        true
      }
      viewport.addView(gestureSurface,FrameLayout.LayoutParams(-1,-1))

      // Small upper overlay. Main controls are in a compact black footer, as in the reference.
      val chrome=overlayControls
      chrome.orientation=HORIZONTAL
      chrome.gravity=Gravity.CENTER_VERTICAL
      chrome.background=GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,intArrayOf(0xa9000000.toInt(),0x00000000))
      padding(chrome,7,1,7,1)
      val back=text("‹",27f,Color.WHITE)
      back.gravity=Gravity.CENTER
      back.contentDescription="العودة لقائمة الفيديوهات"
      chrome.addView(back,LinearLayout.LayoutParams(dp(38),dp(38)))
      back.setOnClickListener{if(fullscreen)exitFullScreen() else exit.run()}
      val nowPlaying=text("EGYTUBE",13f,Color.WHITE)
      nowPlaying.setTypeface(null,android.graphics.Typeface.BOLD)
      padding(nowPlaying,7,0,5,0)
      chrome.addView(nowPlaying,LinearLayout.LayoutParams(0,dp(38),1f))
      viewport.addView(chrome,FrameLayout.LayoutParams(-1,dp(42),Gravity.TOP))
      // Transport seeking is available by double-tapping either side of the video.
      // No permanently visible 10-second buttons cover the picture.
      // Central play/pause overlays the actual native ExoPlayer video.
      centerPlay.gravity=Gravity.CENTER
      centerPlay.background=GradientDrawable().apply{
        shape=GradientDrawable.OVAL
        setColor(0x66000000)
        setStroke(dp(1),0x55ffffff)
      }
      centerPlay.contentDescription="تشغيل أو إيقاف الفيديو مؤقتًا"
      centerPlay.alpha=0f
      centerPlay.visibility=View.GONE
      viewport.addView(centerPlay,FrameLayout.LayoutParams(dp(56),dp(56),Gravity.CENTER))
      seekFeedback.gravity=Gravity.CENTER
      seekFeedback.background=GradientDrawable().apply{
        setColor(0x99000000.toInt())
        cornerRadius=dp(17).toFloat()
      }
      seekFeedback.visibility=View.GONE
      viewport.addView(seekFeedback,FrameLayout.LayoutParams(dp(146),dp(44),Gravity.CENTER))
      fastBadge.gravity=Gravity.CENTER
      fastBadge.background=GradientDrawable().apply{
        setColor(0x88000000.toInt())
        cornerRadius=dp(17).toFloat()
      }
      fastBadge.visibility=View.GONE
      viewport.addView(fastBadge,FrameLayout.LayoutParams(dp(156),dp(38),Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply{
        topMargin=dp(56)
      })
      centerPlay.setOnClickListener{togglePlayback()}
      // Thin red seek line sits above the compact dark playback control strip.
      bottomLayer.orientation=VERTICAL
      bottomLayer.layoutDirection=View.LAYOUT_DIRECTION_LTR
      bottomLayer.setBackgroundColor(0xf6090a0d.toInt())
      timeline.max=1000
      timeline.progressTintList=ColorStateList.valueOf(0xfff32d40.toInt())
      timeline.progressBackgroundTintList=ColorStateList.valueOf(0x77e9e9e9)
      timeline.thumbTintList=ColorStateList.valueOf(0xfff32d40.toInt())
      timeline.splitTrack=false
      bottomLayer.addView(timeline,LinearLayout.LayoutParams(-1,dp(23)))
      timeline.setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener{
        override fun onStartTrackingTouch(v:SeekBar){scrubbing=true;uiHandler.removeCallbacks(autoHide)}
        override fun onProgressChanged(v:SeekBar,value:Int,fromUser:Boolean){
          if(fromUser && player.duration>0)compactClock.text=renderTime(player.duration*value/1000L)+" / "+renderTime(player.duration)
        }
        override fun onStopTrackingTouch(v:SeekBar){
          if(player.duration>0)player.seekTo(player.duration*v.progress/1000L)
          scrubbing=false;showChrome()
        }
      })
      lowerToolbar.layoutDirection=View.LAYOUT_DIRECTION_LTR
      lowerToolbar.gravity=Gravity.CENTER_VERTICAL
      padding(lowerToolbar,5,0,5,4)
      fun button(t:TextView,content:String,width:Int){
        t.gravity=Gravity.CENTER
        t.contentDescription=content
        lowerToolbar.addView(t,LinearLayout.LayoutParams(dp(width),dp(39)))
      }
      button(toolbarPlay,"تشغيل أو إيقاف",36)
      toolbarPlay.setOnClickListener{togglePlayback()}
      button(nextButton,"الفيديو التالي",34)
      nextButton.setOnClickListener{playNext()}
      button(volumeButton,"كتم أو تفعيل الصوت",31)
      volumeButton.setOnClickListener{
        val current=audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        if(current>0){
          previousVolume=current
          audioManager.setStreamVolume(AudioManager.STREAM_MUSIC,0,0)
        } else {
          audioManager.setStreamVolume(AudioManager.STREAM_MUSIC,previousVolume.coerceAtLeast(1),0)
        }
        syncVolume()
      }
      volumeBar.max=audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
      volumeBar.progress=audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
      lowerToolbar.addView(volumeBar,LinearLayout.LayoutParams(dp(58),dp(36)))
      volumeBar.setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener{
        override fun onStartTrackingTouch(s:SeekBar){uiHandler.removeCallbacks(autoHide)}
        override fun onProgressChanged(s:SeekBar,value:Int,fromUser:Boolean){
          if(fromUser){
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC,value,0)
            syncVolume()
          }
        }
        override fun onStopTrackingTouch(s:SeekBar){showChrome()}
      })
      compactClock.setSingleLine(true)
      compactClock.gravity=Gravity.CENTER
      lowerToolbar.addView(compactClock,LinearLayout.LayoutParams(-2,dp(39)))
      lowerToolbar.addView(Space(host),LinearLayout.LayoutParams(0,dp(1),1f))
      button(captionsButton,"الترجمة النصية",31)
      captionsButton.setOnClickListener{toggleCaptions()}
      button(settingsButton,"إعدادات الجودة والسرعة والملاءمة",34)
      settingsButton.setOnClickListener{showPlayerMenu()}
      pipButton.text="▣"
      button(pipButton,"الصورة داخل الصورة",32)
      pipButton.setOnClickListener{enterPictureInPicture()}
      expandButton.text="⛶"
      button(expandButton,"ملء الشاشة",36)
      expandButton.setOnClickListener{setFull(!fullscreen);showChrome()}
      val rowScroller=HorizontalScrollView(host)
      rowScroller.isHorizontalScrollBarEnabled=false
      rowScroller.isFillViewport=true
      rowScroller.addView(lowerToolbar)
      bottomLayer.addView(rowScroller,LinearLayout.LayoutParams(-1,dp(43)))
      viewport.addView(bottomLayer,FrameLayout.LayoutParams(-1,dp(66),Gravity.BOTTOM))
      spinner.indeterminateTintList=ColorStateList.valueOf(Color.WHITE)
      spinner.visibility=View.GONE
      viewport.addView(spinner,FrameLayout.LayoutParams(dp(36),dp(36),Gravity.CENTER))
      settingsPanel.orientation=VERTICAL;settingsPanel.visibility=View.GONE
      settingsPanel.layoutDirection=View.LAYOUT_DIRECTION_RTL
      settingsPanel.background=GradientDrawable().apply{setColor(0xf414161e.toInt());cornerRadius=dp(12).toFloat()}
      viewport.addView(settingsPanel,FrameLayout.LayoutParams(dp(240),dp(175),Gravity.RIGHT or Gravity.TOP).apply{topMargin=dp(48);rightMargin=dp(10)})
      updatePlayIcon()
      syncVolume()
      addView(viewport,LinearLayout.LayoutParams(-1,dp(220)))

      val adBox=LinearLayout(host)
      adBox.orientation=VERTICAL
      val adLabel=text("إعلان",11f,0xff777777.toInt())
      padding(adLabel,12,2,12,2)
      adBox.addView(adLabel)
      AdSlots.loadInto(advertisement,AdSlots.NETWORK_MOBILE_320x50)
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
      share.gravity=Gravity.CENTER
      padding(share,8,9,8,9);actions.addView(share,LinearLayout.LayoutParams(0,-2,1f))
      share.setOnClickListener{
        val i=Intent(Intent.ACTION_SEND)
        i.type="text/plain";i.putExtra(Intent.EXTRA_TEXT,"https://egyshow.com/egy?v=$videoId")
        host.startActivity(Intent.createChooser(i,"مشاركة"))
      }
      val download=text("⬇ تحميل",14f,colorText)
      padding(download,8,9,8,9)
      download.gravity=Gravity.CENTER
      actions.addView(download,LinearLayout.LayoutParams(0,-2,1f))
      download.setOnClickListener{showDownloadQualities()}
      val favorite=text("☆ حفظ",14f,colorText)
      favorite.gravity=Gravity.CENTER
      padding(favorite,8,9,8,9);actions.addView(favorite,LinearLayout.LayoutParams(0,-2,1f))
      favorite.setOnClickListener{
        val p=host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
        p.edit().putString("lastSavedVideo","https://www.youtube.com/watch?v=$videoId").apply()
        Toast.makeText(host,"تم حفظ رابط الفيديو",Toast.LENGTH_SHORT).show()
      }
      val like=text("♡ إعجاب",14f,colorText)
      like.gravity=Gravity.CENTER
      padding(like,8,9,8,9);actions.addView(like,LinearLayout.LayoutParams(0,-2,1f))
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
      playerListener=object:Player.Listener {
        override fun onPlayerError(error:PlaybackException){
          Log.w("EGYTUBE.Player","Playback failed (code=${error.errorCode}, source=$active)")
          cancelResumeWatchdog()
          // Paused for a long period: source URLs can have expired. Renew the
          // stream URLs once instead of cycling through equally expired links.
          if(lastPauseAt>0L && !resumeRecoveryAttempted && !recoveryInFlight &&
             player.playWhenReady){
            refreshPausedSource()
          }else{
            recoverWithAnotherSource()
          }
        }
        override fun onPlayWhenReadyChanged(playWhenReady:Boolean,reason:Int){
          // Keep Android 12+ auto-PiP armed only while playback is requested.
          updatePiPParameters()
          if(!playWhenReady && player.currentMediaItem!=null){
            lastPauseAt=android.os.SystemClock.elapsedRealtime()
            resumeRecoveryPosition=player.currentPosition.coerceAtLeast(0L)
            resumeRecoveryAttempted=false
            cancelResumeWatchdog()
            savePlaybackPosition()
          }else if(playWhenReady && player.currentMediaItem!=null && lastPauseAt>0L){
            scheduleResumeWatchdog()
          }
          updatePlayIcon()
        }
        override fun onIsPlayingChanged(isPlaying:Boolean){
          host.onMiniPlaybackChanged(isPlaying)
          updatePlayIcon()
          if(isPlaying){
            cancelResumeWatchdog()
            scheduleChromeHide()
          }else showChrome()
          updatePiPParameters()
        }
        override fun onPlaybackStateChanged(s:Int){
          spinner.visibility=if(s==Player.STATE_BUFFERING)View.VISIBLE else View.GONE
          updatePlayIcon()
          if(s==Player.STATE_READY){
            fallbackIsPending=false
            if(player.playWhenReady && player.isPlaying)cancelResumeWatchdog()
            savePlaybackPosition()
            state.text="جاري تشغيل الفيديو · ${formats.getOrNull(active)?.label.orEmpty()}"
          }
          if(s==Player.STATE_ENDED){
            forgetPosition()
            if(lastEndedTicket!=ticket){
              lastEndedTicket=ticket
              val currentTicket=ticket
              val autoNext=host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
                .getBoolean("autoplay_next",true)
              if(autoNext)uiHandler.postDelayed({
                if(!shutdown && ticket==currentTicket && player.playbackState==Player.STATE_ENDED)
                  playNext(automatic=true)
              },750L)
              else showChrome()
            }
          }
        }
        override fun onVideoSizeChanged(size:VideoSize){
          if(size.width>0&&size.height>0){
            videoWidth=(size.width*size.pixelWidthHeightRatio).toInt().coerceAtLeast(1);videoHeight=size.height
            resize()
            updatePiPParameters()
          }
        }
      }
      player.addListener(playerListener)
      resize()
      uiHandler.postDelayed(progressSaver,5000L)
      uiHandler.post(progressTicker)
      showChrome()
    }

    fun openVideo(id:String,title:String,channel:String,startPaused:Boolean=false){
      if(!Regex("[A-Za-z0-9_-]{11}").matches(id))return
      if(videoId.isNotEmpty())rememberPosition()
      videoId=id;videoTitle=title
      openAsPaused=startPaused
      recentlyPlayedIds.add(id)
      while(recentlyPlayedIds.size>90)recentlyPlayedIds.remove(recentlyPlayedIds.first())
      heading.text=title;creator.text=channel
      ticket++
      lastEndedTicket=-1
      val token=ticket
      formats.clear();active=-1
      lowDataAudioUrl=null
      cancelResumeWatchdog()
      lastPauseAt=0L
      resumeRecoveryAttempted=false
      recoveryInFlight=false
      unsuccessfulSources.clear()
      fallbackResumeMs=0L
      fallbackIsPending=false
      closeSettings()
      timeline.progress=0;elapsed.text="0:00";total.text="0:00"
      qualityButton.text="⚙ جودة"
      showChrome()
      videoWidth=if(title.contains("Shorts",true))9 else 16
      videoHeight=if(videoWidth==9)16 else 9
      resize()
      suggestions.removeAllViews()
      relatedChoices=emptyList()
      state.text="جارٍ تحميل روابط المشاهدة..."
      player.stop();player.clearMediaItems()
      details.scrollTo(0,0)
      worker.execute{
        try{
          val info=cachedInfo(id)?:StreamInfo.getInfo("https://www.youtube.com/watch?v=$id")
            .also{storeInfo(id,it)}
          val sources=options(info)
          val related=info.relatedItems.filterIsInstance<StreamInfoItem>().take(15)
          host.runOnUiThread {
            if(token!=ticket || shutdown || host.isFinishing || host.isDestroyed)return@runOnUiThread
            heading.text=info.name
            creator.text=info.uploaderName
            videoTitle=info.name
            formats.clear();formats.addAll(sources)
            // In background, request just audio instead of video+audio.
            lowDataAudioUrl=info.audioStreams
              .filter{it.isUrl && it.content.startsWith("https://")}
              .minByOrNull{if(it.averageBitrate>0)it.averageBitrate else Int.MAX_VALUE}
              ?.content
            if(info.ageLimit>0){
              state.text="هذا الفيديو مقيد بالعمر ولا يمكن تشغيله هنا"
            }else if(sources.isEmpty()){
              state.text="لا يوجد مصدر قابل للتشغيل لهذا الفيديو"
            }else{
              choose(0)
            }
            showSuggestions(related)
            if(host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
                .getBoolean("autoplay_next",true)){
              val upcoming=relatedChoices.firstOrNull{
                val nextId=nextVideoId(it.url)
                nextId!=null && nextId!=videoId && nextId !in recentlyPlayedIds
              }
              val nextId=upcoming?.url?.let{nextVideoId(it)}
              if(nextId!=null && cachedInfo(nextId)==null){
                worker.execute{
                  try{storeInfo(nextId,StreamInfo.getInfo("https://www.youtube.com/watch?v=$nextId"))}
                  catch(_:Exception){}
                }
              }
            }
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
      relatedChoices=items.filter{ item->
        val id=nextVideoId(item.url)
        id!=null && id!=videoId && !(item.streamType?.name.orEmpty().contains("LIVE",true))
      }.distinctBy{nextVideoId(it.url)}
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
      // A combined MP4 video+audio source is typically the broadest supported
      // option on Android. Prefer it over DASH/HLS and over high-res adaptive
      // codecs that may be AV1, VP9 Profile 2 or HDR-only on older devices.
      val combined=info.videoStreams
        .filter{it.isUrl && it.content.startsWith("https://") && !it.isVideoOnly}
        .sortedByDescending{
          val name=it.format?.name.orEmpty().uppercase(Locale.ROOT)
          val score=if(name.contains("MPEG_4") || name.contains("MP4"))100000 else 0
          score-kotlin.math.abs(it.height.coerceAtLeast(0)-720)
        }
      combined.forEach{
        val container=if(it.format?.name.orEmpty().contains("WEBM",true))"webm" else "mp4"
        available+=Source("${it.resolution} · صوت وصورة",it.content,extension=container)
      }
      if(!info.hlsUrl.isNullOrBlank()&&info.hlsUrl.startsWith("https://"))
        available+=Source("تلقائي · HLS",info.hlsUrl,mime=MimeTypes.APPLICATION_M3U8)
      if(!info.dashMpdUrl.isNullOrBlank()&&info.dashMpdUrl.startsWith("https://"))
        available+=Source("تلقائي · DASH",info.dashMpdUrl,mime=MimeTypes.APPLICATION_MPD)
      val audio=info.audioStreams.filter{it.isUrl && it.content.startsWith("https://")}
      info.videoOnlyStreams.filter{it.isUrl && it.content.startsWith("https://")}
        .sortedByDescending{
          val name=it.format?.name.orEmpty().uppercase(Locale.ROOT)
          val score=if(name.contains("MPEG_4")||name.contains("MP4"))100000 else 0
          score-kotlin.math.abs(it.height.coerceAtLeast(0)-720)
        }
        .forEach{v->
          val webm=v.format?.name.orEmpty().contains("WEBM")
          val matching=audio.filter{it.format?.name.orEmpty().contains("WEBM")==webm}
          val track=matching.maxByOrNull{it.averageBitrate}?:audio.maxByOrNull{it.averageBitrate}
          if(track!=null)available+=Source("${v.resolution} · فيديو + صوت",v.content,track.content)
        }
      return available.distinctBy{it.url+"|"+it.audio}
    }
    private fun recoverWithAnotherSource(){
      if(shutdown || videoId.isBlank() || active !in formats.indices)return
      if(fallbackIsPending)return
      unsuccessfulSources.add(active)
      val current=player.currentPosition.coerceAtLeast(0L)
      fallbackResumeMs=maxOf(fallbackResumeMs,current)
      val next=formats.indices.firstOrNull{it !in unsuccessfulSources}
      if(next==null){
        fallbackIsPending=false
        // Background streams may expire even without a pause; resolve fresh
        // URLs once all candidate sources have failed, preserving position.
        if(!resumeRecoveryAttempted && !recoveryInFlight &&
           player.playWhenReady){
          refreshPausedSource()
          return
        }
        spinner.visibility=View.GONE
        state.text="لا يمكن تشغيل الفيديو بهذه المصادر. أعد المحاولة من المشغّل."
        updatePlayIcon()
        showChrome()
        return
      }
      fallbackIsPending=true
      state.text="جارٍ تجربة جودة أخرى متوافقة مع جهازك..."
      val videoToken=ticket
      uiHandler.post{
        if(!shutdown && videoToken==ticket && fallbackIsPending && next !in unsuccessfulSources)
          choose(next,positionOverride=fallbackResumeMs,automaticFallback=true)
      }
    }
    private fun showDownloadQualities(){
      if(shutdown || videoId.isBlank())return
      // Only present progressive audio+video options; DASH split tracks would
      // otherwise produce downloaded silent video without remuxing.
      val downloadable=formats.filter{
        it.audio==null && it.mime==null && it.url.startsWith("https://") &&
          (it.extension=="mp4" || it.extension=="webm")
      }.distinctBy{it.label+"|"+it.extension}
      if(downloadable.isEmpty()){
        Toast.makeText(host,"لم تتوفر جودة قابلة للتنزيل بالصوت والصورة لهذا الفيديو",Toast.LENGTH_LONG).show()
        return
      }
      val labels=downloadable.map{it.label+"  ·  "+it.extension.uppercase(Locale.ROOT)}.toTypedArray()
      android.app.AlertDialog.Builder(host)
        .setTitle("اختر جودة تحميل الفيديو")
        .setItems(labels){_,which->
          if(which in downloadable.indices){
            val option=downloadable[which]
            val resolution=option.label.substringBefore(" · ").trim()
            host.requestVideoDownload(videoId,videoTitle,resolution,option.url,option.extension)
          }
        }.setNegativeButton("إلغاء",null).show()
    }
    private fun showQuality(){
      if(formats.isEmpty()){
        Toast.makeText(host,"الجودات غير متاحة بعد",Toast.LENGTH_SHORT).show();return
      }
      val indices=formats.indices.distinctBy{formats[it].label.substringBefore(" · ").trim()}
      val labels=indices.map{formats[it].label.substringBefore(" · ").trim()}
      openSettings("جودة الفيديو",labels,indices.indexOf(active)){index->
        indices.getOrNull(index)?.let{choose(it)}
      }
    }
    private fun choose(index:Int,positionOverride:Long?=null,automaticFallback:Boolean=false){
      if(index !in formats.indices || shutdown)return
      if(!automaticFallback){
        unsuccessfulSources.clear()
        fallbackResumeMs=0L
        fallbackIsPending=false
      }
      val previousPosition=if(active>=0)player.currentPosition.coerceAtLeast(0L)
          else host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE).getLong("resume_$videoId",0L)
      val position=(positionOverride ?: previousPosition).coerceAtLeast(0L)
      if(automaticFallback){
        fallbackResumeMs=position
        // The scheduled retry is now active; allow the next decoder/source error
        // to select another candidate instead of leaving retries blocked.
        fallbackIsPending=false
      }
      val src=formats[index]
      // MediaSessionService continues playback with a media notification when the UI closes.
      try{host.startService(Intent(host,PlaybackService::class.java))}
      catch(e:Exception){state.text="تعذر بدء تشغيل الخلفية: ${e.message.orEmpty()}"}
      active=index
      qualityButton.text="⚙ ${src.label.substringBefore(" · ")}"
      val ds=DefaultDataSource.Factory(host,DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
        .setConnectTimeoutMs(12_000)
        .setReadTimeoutMs(18_000))
      // Use audio-style metadata and an original music-note artwork in the
      // Android lock-screen / notification MediaSession card. This remains a
      // video inside the app and the actual audio track is never transcoded.
      val metadata=MediaMetadata.Builder()
        .setTitle(videoTitle)
        .setArtist(creator.text.toString().ifBlank{"EGYTUBE"})
        .setAlbumTitle("EGYTUBE · مشغّل الصوت")
        .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
        .setArtworkData(AudioNotificationArt.png(),MediaMetadata.PICTURE_TYPE_FRONT_COVER)
        .build()
      fun item(u:String,mime:String?=null):MediaItem=
        MediaItem.Builder().setMediaId(videoId).setUri(u).setMimeType(mime).setMediaMetadata(metadata).build()
      fun direct(u:String):MediaSource=ProgressiveMediaSource.Factory(ds).createMediaSource(item(u))
      val media:MediaSource=when(src.mime){
        MimeTypes.APPLICATION_M3U8->HlsMediaSource.Factory(ds).createMediaSource(
           item(src.url,MimeTypes.APPLICATION_M3U8))
        MimeTypes.APPLICATION_MPD->DashMediaSource.Factory(ds).createMediaSource(
           item(src.url,MimeTypes.APPLICATION_MPD))
        else->if(src.audio!=null)MergingMediaSource(direct(src.url),direct(src.audio))else direct(src.url)
      }
      state.text="جارٍ تشغيل ${src.label}"
      player.setMediaSource(media)
      PlaybackCore.setForegroundSource(videoId,media,lowDataAudioUrl ?: src.audio)
      if(position>0)player.seekTo(position)
      player.playWhenReady=!openAsPaused
      if(openAsPaused)lastPauseAt=android.os.SystemClock.elapsedRealtime()
      openAsPaused=false
      player.prepare()
      PlaybackCore.applyPendingBackgroundMode()
      showChrome()
    }
    private fun showSpeedOptions(){
      val speeds=floatArrayOf(0.5f,0.75f,1f,1.25f,1.5f,2f)
      val labels=speeds.map{String.format(Locale.US,"%.2g×",it)}.toTypedArray()
      val chosen=speeds.indexOfFirst{it==playingRate}.coerceAtLeast(0)
      openSettings("سرعة التشغيل",labels.toList(),chosen){index->
        playingRate=speeds[index]
        player.setPlaybackSpeed(playingRate)
        speedButton.text=labels[index]
      }
    }
    private fun openSettings(title:String,items:List<String>,selected:Int,chooseItem:(Int)->Unit){
      settingsOpen=true;uiHandler.removeCallbacks(autoHide)
      settingsPanel.removeAllViews()
      val heading=text("‹  $title",15f,Color.WHITE)
      padding(heading,12,9,12,8)
      settingsPanel.addView(heading,LinearLayout.LayoutParams(-1,dp(42)))
      heading.setOnClickListener{closeSettings()}
      val list=ScrollView(host)
      val values=LinearLayout(host);values.orientation=VERTICAL
      items.forEachIndexed{index,label->
        val cell=text((if(index==selected)"✓  " else "    ")+label,14f,if(index==selected)0xffff727c.toInt() else Color.WHITE)
        padding(cell,12,7,12,7)
        values.addView(cell,LinearLayout.LayoutParams(-1,dp(40)))
        cell.setOnClickListener{
          closeSettings()
          chooseItem(index)
          if(!settingsOpen)showChrome()
        }
      }
      list.addView(values)
      settingsPanel.addView(list,LinearLayout.LayoutParams(-1,0,1f))
      val maxH=viewport.height.coerceAtLeast(dp(160))
      settingsPanel.layoutParams=FrameLayout.LayoutParams(dp(240),minOf(dp(260),maxH-dp(45)).coerceAtLeast(dp(105)),Gravity.RIGHT or Gravity.TOP).apply{topMargin=dp(46);rightMargin=dp(10)}
      settingsPanel.visibility=View.VISIBLE
      settingsPanel.bringToFront()
    }
    private fun closeSettings(){
      settingsOpen=false
      settingsPanel.visibility=View.GONE
      scheduleChromeHide()
    }
    private fun renderTime(ms:Long):String{
      val t=ms.coerceAtLeast(0L)/1000L
      return if(t>=3600)String.format(Locale.US,"%d:%02d:%02d",t/3600,(t/60)%60,t%60)
         else String.format(Locale.US,"%d:%02d",t/60,t%60)
    }
    private fun updateTime(){
      if(shutdown||scrubbing)return
      val duration=player.duration
      elapsed.text=renderTime(player.currentPosition)
      total.text=if(duration>0)renderTime(duration) else "--:--"
      compactClock.text=elapsed.text.toString()+" / "+total.text.toString()
      if(duration>0){
        timeline.progress=(player.currentPosition.coerceAtLeast(0)*1000L/duration).coerceIn(0L,1000L).toInt()
        timeline.secondaryProgress=(player.bufferedPosition.coerceAtLeast(0)*1000L/duration).coerceIn(0L,1000L).toInt()
      }else{timeline.progress=0;timeline.secondaryProgress=0}
    }
    private fun updatePlayIcon(){
      val playbackRequested=player.playWhenReady && player.currentMediaItem!=null
      centerPlay.text=if(playbackRequested)"Ⅱ" else "▶"
      toolbarPlay.text=if(playbackRequested)"Ⅱ" else "▶"
      centerPlay.contentDescription=if(playbackRequested)"إيقاف مؤقت" else "تشغيل"
      if(!controlsVisible || pipActive || miniTarget!=null){
        centerPlay.animate().cancel()
        centerPlay.visibility=View.GONE
      }
    }
    private fun syncVolume(){
      val current=audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
      volumeButton.text=if(current==0)"◖×" else "◖))"
      if(volumeBar.progress!=current)volumeBar.progress=current
    }
    private fun nextVideoId(url:String):String?=
      Regex("(?:[?&]v=|youtu[.]be/|/shorts/|/embed/)([A-Za-z0-9_-]{11})")
        .find(url)?.groupValues?.getOrNull(1)

    private fun playNext(automatic:Boolean=false){
      if(shutdown)return
      val candidate=relatedChoices.firstOrNull{item->
        val id=nextVideoId(item.url)
        id!=null && id !in recentlyPlayedIds
      }
      if(candidate!=null){
        host.playFromWatch(candidate.url,candidate.name,candidate.uploaderName.orEmpty())
        return
      }
      if(host.playNextFromFeed(videoId,recentlyPlayedIds))return
      if(!automatic)Toast.makeText(host,"لا يوجد فيديو تالٍ متاح",Toast.LENGTH_SHORT).show()
      else state.text="انتهى الفيديو. لا تتوفر اقتراحات جديدة."
      showChrome()
    }
    private fun toggleCaptions(){
      captionsEnabled=!captionsEnabled
      player.trackSelectionParameters=player.trackSelectionParameters.buildUpon()
        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT,!captionsEnabled).build()
      captionsButton.setTextColor(if(captionsEnabled)0xffff4e60.toInt() else Color.WHITE)
      Toast.makeText(host,if(captionsEnabled)"تم تفعيل الترجمة عند توفرها" else "تم إيقاف الترجمة",Toast.LENGTH_SHORT).show()
      showChrome()
    }
    private fun showPlayerMenu(){
      openSettings("إعدادات المشغّل",listOf(
         "الجودة  ·  "+(formats.getOrNull(active)?.label?.substringBefore(" · ") ?: "تلقائي"),
         "السرعة  ·  "+String.format(Locale.US,"%.2g×",playingRate),
         if(zoomed)"العرض  ·  احتواء الفيديو" else "العرض  ·  ملء الإطار",
         if(captionsEnabled)"الترجمة  ·  تشغيل" else "الترجمة  ·  إيقاف",
         if(host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
             .getBoolean("autoplay_next",true))"الفيديو التالي  ·  تلقائي" else "الفيديو التالي  ·  يدوي"
      ),-1){index->
         when(index){
           0->showQuality()
           1->showSpeedOptions()
           2->{zoomed=!zoomed;mediaView.resizeMode=if(zoomed)AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT}
           3->toggleCaptions()
           4->{
             val prefs=host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
             prefs.edit().putBoolean("autoplay_next",!prefs.getBoolean("autoplay_next",true)).apply()
             Toast.makeText(host,"تم تحديث التشغيل التلقائي",Toast.LENGTH_SHORT).show()
           }
         }
      }
    }
    private fun restoreHoldSpeed(){
      if(!holdSpeedActive)return
      holdSpeedActive=false
      if(!shutdown && player.currentMediaItem!=null)player.setPlaybackSpeed(speedBeforeHold)
      fastBadge.visibility=View.GONE
      scheduleChromeHide()
    }
    private fun flashSeekFeedback(label:String){
      seekFeedback.animate().cancel()
      seekFeedback.text=label
      seekFeedback.alpha=0f
      seekFeedback.visibility=View.VISIBLE
      seekFeedback.animate().alpha(1f).setDuration(100).withEndAction{
        seekFeedback.animate().alpha(0f).setStartDelay(390).setDuration(170)
          .withEndAction{seekFeedback.visibility=View.GONE}.start()
      }.start()
    }
    private fun flashCenterIcon(){
      if(pipActive || miniTarget!=null || spinner.visibility==View.VISIBLE)return
      centerPlay.animate().cancel()
      centerPlay.alpha=0f
      centerPlay.visibility=View.VISIBLE
      centerPlay.animate().alpha(1f).setDuration(100).withEndAction{
        centerPlay.animate().alpha(0f).setStartDelay(600).setDuration(210)
          .withEndAction{centerPlay.visibility=View.GONE}.start()
      }.start()
    }
    private fun skipBy(delta:Long,showControls:Boolean=true){
      if(player.currentMediaItem==null)return
      val max=if(player.duration>0)player.duration else Long.MAX_VALUE
      player.seekTo((player.currentPosition+delta).coerceIn(0L,max))
      if(showControls)showChrome()
    }
    private fun setChromeVisibility(visible:Boolean){
      controlsVisible=visible
      overlayControls.visibility=if(visible)View.VISIBLE else View.GONE
      bottomLayer.visibility=if(visible)View.VISIBLE else View.GONE
      if(!visible){
        centerPlay.animate().cancel()
        centerPlay.visibility=View.GONE
      }
      updatePlayIcon()
    }
    private fun showChrome(){
      if(pipActive)return
      uiHandler.removeCallbacks(autoHide)
      setChromeVisibility(true)
      flashCenterIcon()
      scheduleChromeHide()
    }
    private fun scheduleChromeHide(){
      uiHandler.removeCallbacks(autoHide)
      if(!pipActive && !holdSpeedActive && player.isPlaying && !scrubbing && !settingsOpen)
        uiHandler.postDelayed(autoHide,3100L)
    }
    private fun cancelResumeWatchdog(){
      resumeWatchdog?.let{uiHandler.removeCallbacks(it)}
      resumeWatchdog=null
    }
    private fun scheduleResumeWatchdog(){
      cancelResumeWatchdog()
      if(shutdown || recoveryInFlight || resumeRecoveryAttempted ||
         !player.playWhenReady || videoId.isBlank())return
      val token=ticket
      val task=Runnable{
        resumeWatchdog=null
        if(shutdown || token!=ticket || !player.playWhenReady ||
           recoveryInFlight || resumeRecoveryAttempted || player.isPlaying)return@Runnable
        // Avoid refreshing while audio focus, a call or another system policy
        // suppresses playback. The user can press Play again after focus returns.
        if(player.playbackSuppressionReason!=Player.PLAYBACK_SUPPRESSION_REASON_NONE)return@Runnable
        if(player.playbackState==Player.STATE_BUFFERING ||
           player.playbackState==Player.STATE_IDLE || player.playerError!=null)
           refreshPausedSource()
      }
      resumeWatchdog=task
      uiHandler.postDelayed(task,7_000L)
    }
    private fun togglePlayback(){
      if(shutdown || videoId.isBlank())return
      if(!player.playWhenReady || player.playerError!=null){
        // A paused MediaSessionService may have been destroyed by Android
        // without disposing the still-visible player's instance. Restart the
        // mediaPlayback service when the user explicitly resumes.
        try{host.startService(Intent(host,PlaybackService::class.java))}
        catch(e:Exception){Log.w("EGYTUBE.Player","Media service restart deferred",e)}
      }
      if(player.playerError!=null || player.playbackState==Player.STATE_IDLE){
        // A failed source can remain in a stopped state with playWhenReady=true.
        // Treat an explicit user tap as a fresh request, not an instruction to pause.
        resumeRecoveryAttempted=false
        if(!recoveryInFlight)refreshPausedSource()
      }else if(player.currentMediaItem==null){
        resumeRecoveryAttempted=false
        resumeRecoveryPosition=maxOf(resumeRecoveryPosition,
          host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
            .getLong("resume_$videoId",0L))
        refreshPausedSource()
      }else if(player.playWhenReady){
        // isPlaying may be false during buffering; pause the requested playback.
        player.pause()
      }else{
        val pausedFor=if(lastPauseAt>0L)
          android.os.SystemClock.elapsedRealtime()-lastPauseAt else 0L
        resumeRecoveryPosition=player.currentPosition.coerceAtLeast(0L)
        if(player.playerError!=null || player.playbackState==Player.STATE_IDLE){
          refreshPausedSource()
        }else{
          // Try immediate resume from the existing buffered media. If its
          // expiring URL has gone stale, the watchdog will renew it once.
          player.play()
          if(pausedFor>60_000L)scheduleResumeWatchdog()
        }
      }
      updatePlayIcon()
      showChrome()
    }
    private fun refreshPausedSource(){
      if(shutdown || videoId.isBlank() || recoveryInFlight || resumeRecoveryAttempted)return
      cancelResumeWatchdog()
      recoveryInFlight=true
      resumeRecoveryAttempted=true
      val currentTicket=ticket
      val id=videoId
      val position=maxOf(resumeRecoveryPosition,player.currentPosition.coerceAtLeast(0L))
      state.text="جارٍ استعادة الفيديو من موضع التوقف..."
      spinner.visibility=View.VISIBLE
      recoveryWorker.execute{
        try{
          // Do not reuse the old resolved URLs or the short-lived source cache.
          val fresh=StreamInfo.getInfo("https://www.youtube.com/watch?v=$id")
          val candidates=options(fresh)
          host.runOnUiThread{
            if(shutdown || currentTicket!=ticket || id!=videoId)return@runOnUiThread
            recoveryInFlight=false
            if(candidates.isEmpty()){
              spinner.visibility=View.GONE
              state.text="مصدر الفيديو غير متاح حاليًا."
              showChrome()
              return@runOnUiThread
            }
            storeInfo(id,fresh)
            formats.clear();formats.addAll(candidates)
            unsuccessfulSources.clear()
            fallbackIsPending=false
            active=-1
            choose(0,positionOverride=position,automaticFallback=true)
          }
        }catch(e:Exception){
          Log.w("EGYTUBE.Player","Cannot refresh paused media",e)
          host.runOnUiThread{
            if(shutdown || currentTicket!=ticket || id!=videoId)return@runOnUiThread
            recoveryInFlight=false
            spinner.visibility=View.GONE
            state.text="تعذر استعادة الفيديو. تحقق من الإنترنت واضغط تشغيل للمحاولة مجددًا."
            showChrome()
          }
        }
      }
    }
    private fun rememberPosition(){
      savePlaybackPosition()
    }
    fun savePlaybackPosition(){
      if(videoId.isEmpty() || player.currentMediaItem==null || shutdown)return
      val now=player.currentPosition
      if(now>2000L && (player.duration<=0L || now<player.duration-2500L)){
        host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE).edit()
          .putLong("resume_$videoId",now).apply()
        lastBackgroundSaveAt=android.os.SystemClock.elapsedRealtime()
      }
    }
    fun keepAudioInBackground():Boolean=
      !shutdown && player.currentMediaItem!=null && player.playWhenReady &&
        player.playbackState!=Player.STATE_ENDED
    fun hasLoadedOrPendingVideo():Boolean=!shutdown && videoId.isNotBlank()
    fun isPlaybackRequested():Boolean=!shutdown && player.playWhenReady
    fun onReturnedToForeground(){
      if(shutdown || videoId.isBlank())return
      // A source URL can expire while the app is backgrounded. Only re-resolve
      // after a real terminal player error; don't interrupt normal buffering.
      if(player.playerError!=null &&
        host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE)
          .getBoolean("bg_resume_requested",false)){
        synchronized(sourceLock){recentInfo.remove(videoId)}
        openVideo(videoId,videoTitle,creator.text.toString())
      }else if(player.currentMediaItem!=null && player.playWhenReady &&
        player.playbackState==Player.STATE_IDLE){
        player.prepare()
      }
    }
    fun reconnectExisting(id:String,title:String,channel:String){
      if(shutdown || player.currentMediaItem==null)return
      // If Android restored a media-only session in a new process, fetch the
      // matching video again instead of showing a blank player on return.
      if(!PlaybackCore.hasForegroundSource(id)){
        val oldPosition=player.currentPosition.coerceAtLeast(0L)
        val wasPlaying=player.playWhenReady
        if(oldPosition>0L){
          host.getSharedPreferences("EGYTUBE_ONLY",Context.MODE_PRIVATE).edit()
            .putLong("resume_$id",oldPosition).apply()
        }
        openVideo(id,title,channel,!wasPlaying)
        return
      }
      videoId=id
      videoTitle=title
      heading.text=title
      creator.text=channel
      ticket++
      spinner.visibility=View.GONE
      state.text="تم استعادة جلسة التشغيل في الخلفية"
      if(player.playbackState==Player.STATE_IDLE && player.playerError==null)player.prepare()
      updatePlayIcon()
      resize()
      updatePiPParameters()
      showChrome()
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
        val visible=Rect()
        if((miniTarget ?: viewport).getGlobalVisibleRect(visible)&&!visible.isEmpty)params.setSourceRectHint(visible)
        // Android 12+ handles Home/app-switch PiP automatically when video is
        // playing. Paused videos do not open an unsolicited floating window.
        if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.S)
          params.setAutoEnterEnabled(player.playWhenReady && player.playbackState!=Player.STATE_ENDED)
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
      host.prepareWatchForPip()
      if(fullscreen)setFull(false)
      try{
        val builder=PictureInPictureParams.Builder().setAspectRatio(pipRatio())
        val visible=Rect()
        if(viewport.getGlobalVisibleRect(visible)&&!visible.isEmpty)builder.setSourceRectHint(visible)
        if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.S)builder.setAutoEnterEnabled(false)
        host.enterPictureInPictureMode(builder.build())
      }catch(e:Exception){
        Toast.makeText(host,"لا يتوفر PiP على هذا الجهاز",Toast.LENGTH_SHORT).show()
      }
    }
    fun onPictureInPictureChanged(inPip:Boolean){
      pipActive=inPip
      closeSettings()
      uiHandler.removeCallbacks(autoHide)
      mediaView.useController=false
      setChromeVisibility(!inPip)
      if(!inPip)showChrome()
      resize()
      // Re-arm Android 12+ automatic PiP after returning from a manual or
      // automatic PiP window. Otherwise the manual PiP builder's settings
      // could suppress automatic PiP on the next Home press.
      if(!inPip)updatePiPParameters()
    }
    fun hasVideo()=!shutdown && videoId.isNotBlank()
    fun currentVideoTitle()=videoTitle
    fun isPlayingVideo()=player.isPlaying && !shutdown
    fun toggleMiniPlayback(){togglePlayback()}
    fun dockIntoMini(container:ViewGroup){
      if(shutdown || miniTarget===container)return
      restoreHoldSpeed()
      centerPlay.animate().cancel()
      centerPlay.visibility=View.GONE
      closeSettings()
      (mediaView.parent as? ViewGroup)?.removeView(mediaView)
      container.addView(mediaView,ViewGroup.LayoutParams(-1,-1))
      miniTarget=container
      updatePiPParameters()
    }
    fun restoreFromMini(){
      if(shutdown || miniTarget==null)return
      (mediaView.parent as? ViewGroup)?.removeView(mediaView)
      viewport.addView(mediaView,0,FrameLayout.LayoutParams(-1,-1))
      miniTarget=null
      mediaView.useController=false
      resize()
      updatePiPParameters()
      showChrome()
    }
    private fun resize(){
      if(shutdown)return
      val landscape=resources.configuration.orientation==Configuration.ORIENTATION_LANDSCAPE
      // Display metrics can be tiny during PiP transitions, split screen and rotation.
      // A fixed dp minimum can then exceed the available maximum and crash coerceIn().
      val width=resources.displayMetrics.widthPixels.coerceAtLeast(1)
      val screen=resources.displayMetrics.heightPixels.coerceAtLeast(1)
      val portraitVideo=videoHeight>videoWidth
      val natural=((width.toLong()*videoHeight.coerceAtLeast(1).toLong())/
          videoWidth.coerceAtLeast(1).toLong()).coerceIn(1L,Int.MAX_VALUE.toLong()).toInt()
      val maxHeight=(screen*(if(portraitVideo)0.62f else 0.42f)).toInt().coerceAtLeast(1)
      val minHeight=minOf(dp(if(portraitVideo)230 else 170),maxHeight)
      val measured=natural.coerceIn(minHeight,maxHeight)
      val params=viewport.layoutParams as? LayoutParams ?:LayoutParams(-1,measured)
      params.height=when {
        pipActive -> ViewGroup.LayoutParams.MATCH_PARENT
        fullscreen -> ViewGroup.LayoutParams.MATCH_PARENT
        landscape -> (screen*0.78f).toInt().coerceAtLeast(1)
        else -> measured
      }
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
    fun release(stopPlayback:Boolean=true){
      if(shutdown)return
      rememberPosition()
      closeSettings()
      shutdown=true;ticket++
      cancelResumeWatchdog()
      uiHandler.removeCallbacksAndMessages(null)
      restoreHoldSpeed()
      if(miniTarget!=null){
        (mediaView.parent as? ViewGroup)?.removeView(mediaView)
        miniTarget=null
      }
      host.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      worker.shutdownNow();recoveryWorker.shutdownNow();images.shutdownNow()
      player.removeListener(playerListener)
      mediaView.player=null
      PlaybackCore.detachUi()
      if(stopPlayback){
        player.stop()
        player.clearMediaItems()
        host.stopService(Intent(host,PlaybackService::class.java))
      }
      advertisement.stopLoading();advertisement.destroy()
    }
    private data class Source(val label:String,val url:String,val audio:String?=null,val mime:String?=null,val extension:String="mp4")
}
