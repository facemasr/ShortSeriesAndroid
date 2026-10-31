package com.egytube.rebuilt

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.util.concurrent.Executors
import kotlin.math.abs

/**
 * Genuine Media3 mediaPlayback foreground service. Android owns the lock-screen
 * media notification with Play/Pause, 10s seek and Stop controls. Does not use
 * a permanent wakelock, suppress battery settings, or keep paused audio playing.
 */
@OptIn(UnstableApi::class)
class PlaybackService:MediaSessionService(){
  private var session:MediaSession?=null
  private var servicePlayer:ExoPlayer?=null
  private val main=Handler(Looper.getMainLooper())
  private val recoveryWorker=Executors.newSingleThreadExecutor()
  private var recoveryToken=0
  private var previousRecoveryAt=0L
  private var previousRecoveryId=""
  private val listener=object:Player.Listener {
    override fun onPlayerError(error:PlaybackException){
      // The attached watch UI already handles source fallback. Recover only
      // sessions orphaned from the Activity, e.g. app removed from Recents.
      val player=servicePlayer?:return
      if(PlaybackCore.hasAttachedUi() || !player.playWhenReady)return
      val id=player.currentMediaItem?.mediaId.orEmpty()
      if(!id.matches(Regex("[A-Za-z0-9_-]{11}")))return
      val now=SystemClock.elapsedRealtime()
      if(previousRecoveryId==id && now-previousRecoveryAt<90_000L)return
      previousRecoveryId=id
      previousRecoveryAt=now
      val token=++recoveryToken
      val position=player.currentPosition.coerceAtLeast(0L)
      val metadata=player.currentMediaItem?.mediaMetadata
      recoveryWorker.execute{
        try{
          try{NewPipe.init(HttpDownloader())}catch(_:Exception){}
          val fresh=StreamInfo.getInfo("https://www.youtube.com/watch?v=$id")
          val source=fresh.videoStreams
            .filter{it.isUrl && !it.isVideoOnly && it.content.startsWith("https://")}
            .sortedBy{
              val mp4=it.format?.name.orEmpty().contains("MP4",true)
              (if(mp4)0 else 10000)+abs(it.height.coerceAtLeast(0)-720)
            }.firstOrNull()?.content
          if(source==null)return@execute
          main.post{
            val active=servicePlayer
            if(session==null || token!=recoveryToken ||
              active==null || PlaybackCore.hasAttachedUi() ||
              active.currentMediaItem?.mediaId!=id || !active.playWhenReady)return@post
            val item=MediaItem.Builder().setMediaId(id).setUri(source)
              .apply{metadata?.let{setMediaMetadata(it)}}.build()
            active.setMediaItem(item,position)
            active.prepare()
            active.play()
          }
        }catch(e:Exception){Log.w("EGYTUBE.Background","Unable to refresh an expired background source",e)}
      }
    }
  }

  override fun onCreate(){
    super.onCreate()
    val player=PlaybackCore.get(this)
    servicePlayer=player
    player.addListener(listener)
    val launch=Intent(this,MainActivity::class.java)
      .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    val flag=PendingIntent.FLAG_UPDATE_CURRENT or
      (if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.M)PendingIntent.FLAG_IMMUTABLE else 0)
    val reopen=PendingIntent.getActivity(this,0,launch,flag)

    // The central Play/Pause control is supplied by Android; 10-second seek
    // and Stop are advertised as media session controls in the notification.
    val commands=listOf(
      CommandButton.Builder(CommandButton.ICON_SKIP_BACK_10)
        .setPlayerCommand(Player.COMMAND_SEEK_BACK).build(),
      CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD_10)
        .setPlayerCommand(Player.COMMAND_SEEK_FORWARD).build(),
      CommandButton.Builder(CommandButton.ICON_STOP)
        .setPlayerCommand(Player.COMMAND_STOP).build()
    )
    session=MediaSession.Builder(this,player)
      .setSessionActivity(reopen)
      .setMediaButtonPreferences(commands)
      .build()
  }

  override fun onGetSession(controllerInfo:MediaSession.ControllerInfo):MediaSession?=session

  override fun onTaskRemoved(rootIntent:Intent?){
    val player=servicePlayer
    if(player!=null && player.currentMediaItem!=null && player.playWhenReady &&
       player.playbackState!=Player.STATE_ENDED)return
    super.onTaskRemoved(rootIntent)
  }

  override fun onDestroy(){
    recoveryToken++
    servicePlayer?.removeListener(listener)
    servicePlayer=null
    recoveryWorker.shutdownNow()
    session?.release()
    session=null
    PlaybackCore.disposeWhenUnused()
    super.onDestroy()
  }
}
