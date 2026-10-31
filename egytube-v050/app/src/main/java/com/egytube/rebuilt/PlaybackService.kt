package com.egytube.rebuilt

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle
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
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
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
  companion object {
    private const val COMMAND_CLOSE="com.egytube.rebuilt.CLOSE_MEDIA_PLAYER"
  }
  private val closeCommand=SessionCommand(COMMAND_CLOSE,Bundle.EMPTY)
  private var session:MediaSession?=null
  private var servicePlayer:ExoPlayer?=null
  private val main=Handler(Looper.getMainLooper())
  private val recoveryWorker=Executors.newSingleThreadExecutor()
  private var recoveryToken=0
  private var previousRecoveryAt=0L
  private var previousRecoveryId=""
  // The Stop button is an explicit *close player* action: remove the media
  // item to dismiss Android's card, then terminate the service. Pausing does
  // not close the player or reset its position.
  private val mediaCallback=object:MediaSession.Callback {
    override fun onConnect(
      session:MediaSession,controller:MediaSession.ControllerInfo
    ):MediaSession.ConnectionResult {
      return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
        .setAvailableSessionCommands(
          MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
            .add(closeCommand).build()
        ).build()
    }

    override fun onCustomCommand(
      session:MediaSession,controller:MediaSession.ControllerInfo,
      customCommand:SessionCommand,args:Bundle
    ):ListenableFuture<SessionResult> {
      if(customCommand.customAction!=COMMAND_CLOSE)
        return Futures.immediateFuture(SessionResult(SessionResult.RESULT_ERROR_NOT_SUPPORTED))
      recoveryToken++
      servicePlayer?.apply {
        pause()
        stop()
        clearMediaItems()
      }
      // Clearing the player timeline removes the media card immediately.
      stopSelf()
      return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
    }
  }

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
        .setSessionCommand(closeCommand).build()
    )
    // This app starts PlaybackService directly with startService(), not by
    // binding a MediaController. Without addSession() the service has no
    // registered session to observe and Media3 may never post a media card.
    val mediaProvider=DefaultMediaNotificationProvider.Builder(this)
      .setChannelId("egytube_media_playback_v2")
      .build()
    mediaProvider.setSmallIcon(R.drawable.ic_app)
    setMediaNotificationProvider(mediaProvider)
    val built=MediaSession.Builder(this,player)
      .setCallback(mediaCallback)
      .setSessionActivity(reopen)
      .setMediaButtonPreferences(commands)
      .build()
    session=built
    addSession(built)
    val registered=isSessionAdded(built)
    getSharedPreferences("EGYTUBE_MEDIA_STATUS",MODE_PRIVATE).edit()
      .putString("service_state",if(registered)"registered" else "session_missing")
      .putLong("service_started_at",System.currentTimeMillis())
      .apply()
    Log.i("EGYTUBE.Media","Playback service initialized; registered session=$registered")
  }

  override fun onUpdateNotification(
    session:MediaSession,startInForegroundRequired:Boolean
  ){
    // Use Media3's managed media-style notification and proper foreground
    // lifecycle. Do not post a competing generic NotificationCompat alert.
    Log.d("EGYTUBE.Media","Media notification update: foreground=$startInForegroundRequired")
    getSharedPreferences("EGYTUBE_MEDIA_STATUS",MODE_PRIVATE).edit()
      .putLong("last_notification_update_at",System.currentTimeMillis())
      .putBoolean("notification_foreground_requested",startInForegroundRequired)
      .apply()
    super.onUpdateNotification(session,startInForegroundRequired)
  }

  override fun onGetSession(controllerInfo:MediaSession.ControllerInfo):MediaSession?=session

  override fun onTaskRemoved(rootIntent:Intent?){
    val player=servicePlayer
    // Removing the app from Recents is NOT an explicit Stop command.
    // Keep the existing Android media foreground service and session alive
    // while playback is ongoing; Android keeps its native media card visible.
    if(player!=null && player.currentMediaItem!=null &&
       player.playbackState!=Player.STATE_ENDED && isPlaybackOngoing()){
      PlaybackCore.setAudioOnlyBackground(true)
      return
    }
    // Android requires us to let Media3 stop a service that's no longer in
    // the foreground (e.g. idle/paused beyond the OS grace period).
    super.onTaskRemoved(rootIntent)
  }

  override fun onDestroy(){
    recoveryToken++
    servicePlayer?.removeListener(listener)
    servicePlayer=null
    recoveryWorker.shutdownNow()
    session?.release()
    session=null
    getSharedPreferences("EGYTUBE_MEDIA_STATUS",MODE_PRIVATE).edit()
      .putString("service_state","stopped")
      .putLong("service_stopped_at",System.currentTimeMillis()).apply()
    PlaybackCore.disposeWhenUnused()
    super.onDestroy()
  }
}
