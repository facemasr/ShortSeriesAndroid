package com.egytube.rebuilt

import android.app.Activity
import android.content.res.Configuration
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Spinner
import android.widget.TextView
import android.widget.Button
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.PlayerView
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.util.concurrent.Executors

/** Native player based on EGYTUBE 0.4.4: Media3/ExoPlayer, not YouTube iframe. */
@OptIn(UnstableApi::class)
class PlayerActivity : Activity() {
    private val worker=Executors.newSingleThreadExecutor()
    private lateinit var player:ExoPlayer
    private lateinit var view:PlayerView
    private lateinit var status:TextView
    private lateinit var quality:Spinner
    private lateinit var title:TextView
    private lateinit var advert:WebView
    private val formats=mutableListOf<Format>()
    private var selected=-1
    private var ready=false

    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        view=findViewById(R.id.playerView)
        title=findViewById(R.id.videoTitle)
        status=findViewById(R.id.playerStatus)
        quality=findViewById(R.id.qualities)
        advert=findViewById(R.id.playerAdSlot)
        findViewById<Button>(R.id.back).setOnClickListener{ finish() }
        setupAdvert()
        player=ExoPlayer.Builder(this).build()
        view.player=player
        view.useController=true
        player.addListener(object:Player.Listener{
          override fun onPlayerError(error:PlaybackException){
             status.text="تعذر تشغيل المصدر الحالي: ${error.errorCodeName}"
          }
          override fun onPlaybackStateChanged(state:Int){
             if(state==Player.STATE_READY)status.text="يعمل مشغل EGYTUBE الأصلي"
          }
        })
        quality.onItemSelectedListener=object:AdapterView.OnItemSelectedListener{
          override fun onNothingSelected(parent:android.widget.AdapterView<*>?)=Unit
          override fun onItemSelected(parent:android.widget.AdapterView<*>?, row:View?, position:Int, id:Long){
             if(ready && selected!=position)choose(position)
          }
        }
        val id=intent.getStringExtra("videoId").orEmpty()
        if(!Regex("[A-Za-z0-9_-]{11}").matches(id)){
          status.text="معرّف الفيديو غير صالح";return
        }
        title.text=intent.getStringExtra("videoTitle").orEmpty().ifBlank{"EGYTUBE"}
        status.text="جارٍ البحث عن مصادر التشغيل..."
        NewPipe.init(HttpDownloader())
        load("https://www.youtube.com/watch?v=$id")
        resize()
    }
    private fun setupAdvert(){
        // Third provided creative: small 320x50 player banner, without covering player controls.
        AdSlots.loadInto(advert,AdSlots.PLAYER_320x50)
    }
    private fun load(page:String){
        worker.execute {
          try{
            val info=StreamInfo.getInfo(page)
            if(info.ageLimit>0){
              runOnUiThread { if(!isFinishing && !isDestroyed)status.text="لا يمكن تشغيل هذا المحتوى المقيد بالعمر" }
              return@execute
            }
            val list=options(info)
            runOnUiThread {
              if(isFinishing||isDestroyed)return@runOnUiThread
              title.text=info.name
              formats.clear();formats.addAll(list)
              if(formats.isEmpty()){
                status.text="لم تتوفر روابط تشغيل مناسبة للفيديو";return@runOnUiThread
              }
              quality.adapter=ArrayAdapter(this,android.R.layout.simple_spinner_dropdown_item,formats.map{it.label})
              ready=true
              choose(0)
            }
          }catch(e:Exception){
            runOnUiThread {
              if(!isFinishing&&!isDestroyed)status.text="مصدر الفيديو غير متاح: ${e.message?.take(120) ?: "خطأ"}"
            }
          }
        }
    }
    private fun options(info:StreamInfo):List<Format>{
        val list=mutableListOf<Format>()
        val hls=info.hlsUrl
        if(!hls.isNullOrBlank()&&hls.startsWith("https://"))
          list+=Format("AUTO · HLS حسب سرعة الإنترنت",hls,mime=MimeTypes.APPLICATION_M3U8)
        val dash=info.dashMpdUrl
        if(!dash.isNullOrBlank()&&dash.startsWith("https://"))
          list+=Format("AUTO · DASH حسب سرعة الإنترنت",dash,mime=MimeTypes.APPLICATION_MPD)
        info.videoStreams
          .filter{it.isUrl&&it.content.startsWith("https://")&&!it.isVideoOnly}
          .sortedByDescending{it.height}
          .forEach{list+=Format("${it.resolution} · صوت وصورة",it.content)}
        val audios=info.audioStreams.filter{it.isUrl&&it.content.startsWith("https://")}
        info.videoOnlyStreams.filter{it.isUrl&&it.content.startsWith("https://")}
          .sortedByDescending{it.height}.forEach{vid->
            val isWebm=vid.format?.name.orEmpty().contains("WEBM")
            val audio=audios.filter{it.format?.name.orEmpty().contains("WEBM")==isWebm}
              .maxByOrNull{it.averageBitrate} ?: audios.maxByOrNull{it.averageBitrate}
            if(audio!=null)list+=Format("${vid.resolution} · فيديو + صوت",vid.content,audio=audio.content)
          }
        return list.distinctBy{it.url+"|"+it.audio}
    }
    private fun choose(pos:Int){
        if(pos !in formats.indices)return
        val resume=if(selected>=0)player.currentPosition else 0L
        selected=pos
        val src=formats[pos]
        val ds=DefaultDataSource.Factory(this,DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true))
        fun progressive(u:String):MediaSource=ProgressiveMediaSource.Factory(ds).createMediaSource(MediaItem.fromUri(u))
        val media:MediaSource=when{
           src.mime==MimeTypes.APPLICATION_M3U8->HlsMediaSource.Factory(ds)
             .createMediaSource(MediaItem.Builder().setUri(src.url).setMimeType(MimeTypes.APPLICATION_M3U8).build())
           src.mime==MimeTypes.APPLICATION_MPD->DashMediaSource.Factory(ds)
             .createMediaSource(MediaItem.Builder().setUri(src.url).setMimeType(MimeTypes.APPLICATION_MPD).build())
           src.audio!=null->MergingMediaSource(progressive(src.url),progressive(src.audio))
           else->progressive(src.url)
        }
        status.text="جارٍ تشغيل ${src.label}"
        player.setMediaSource(media)
        player.prepare()
        if(resume>0)player.seekTo(resume)
        player.playWhenReady=true
        if(quality.selectedItemPosition!=pos)quality.setSelection(pos)
    }
    private fun resize(){
      val landscape=resources.configuration.orientation==Configuration.ORIENTATION_LANDSCAPE
      val params=view.layoutParams
      params.height=if(landscape)ViewGroup.LayoutParams.MATCH_PARENT else (240*resources.displayMetrics.density).toInt()
      view.layoutParams=params
      val visibility=if(landscape)View.GONE else View.VISIBLE
      title.visibility=visibility;quality.visibility=visibility;status.visibility=visibility;advert.visibility=visibility
      window.decorView.systemUiVisibility=if(landscape)
        View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        else 0
    }
    override fun onConfigurationChanged(config:Configuration){super.onConfigurationChanged(config);resize()}
    override fun onDestroy(){
      view.player=null
      player.release()
      advert.destroy()
      worker.shutdownNow()
      super.onDestroy()
    }
}
private data class Format(val label:String,val url:String,val audio:String?=null,val mime:String?=null)
