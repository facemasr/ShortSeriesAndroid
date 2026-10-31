package com.egytube.rebuilt

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.DefaultLoadControl

/**
 * A single app process player. The MediaSessionService owns its lifetime.
 * UI views must detach without releasing the active background audio session.
 */
object PlaybackCore {
  private var instance:ExoPlayer?=null
  private var attachedUiCount=0
  @Synchronized fun attachUi(){attachedUiCount++}
  @Synchronized fun detachUi(){attachedUiCount=(attachedUiCount-1).coerceAtLeast(0)}
  @Synchronized fun hasAttachedUi():Boolean=attachedUiCount>0
  /**
   * Preserve the current media item, timestamp and audio session while
   * disabling only video decoding/rendering when the Activity is backgrounded.
   * No transcoding, new stream URL, seek or restart is necessary.
   * In PiP callers keep this false so the picture remains visible.
   */
  // Keep the currently selected video source so opening the app can restore
  // the same media and position instead of restarting the whole video.
  private var foregroundSource:MediaSource?=null
  private var foregroundVideoId=""
  private var backgroundAudioUrl:String?=null
  private var audioStreamActive=false
  private var backgroundRequested=false

  @Synchronized fun setForegroundSource(id:String,source:MediaSource,audioOnlyUrl:String?){
    foregroundVideoId=id
    foregroundSource=source
    backgroundAudioUrl=audioOnlyUrl?.takeIf{it.startsWith("https://")}
    audioStreamActive=false
  }

  @Synchronized fun hasForegroundSource(id:String):Boolean=
    id==foregroundVideoId && foregroundSource!=null

  /**
   * When an audio-only URL is available, really stop requesting video bytes
   * in the background. Disabling the VIDEO renderer alone on a progressive MP4
   * does not prevent downloading its video data.
   *
   * A source change may rebuffer briefly but keeps the video ID, elapsed time,
   * playback intent, MediaSession metadata, and hardware controls.
   */
  @Synchronized fun setAudioOnlyBackground(enabled:Boolean){
    backgroundRequested=enabled
    val player=instance?:return
    val item=player.currentMediaItem?:return
    val position=player.currentPosition.coerceAtLeast(0L)
    val wasPlaying=player.playWhenReady
    if(enabled && !audioStreamActive){
      val audio=backgroundAudioUrl
      if(audio!=null && item.mediaId==foregroundVideoId){
        val audioItem=MediaItem.Builder()
          .setMediaId(item.mediaId)
          .setUri(audio)
          .setMediaMetadata(item.mediaMetadata)
          .build()
        player.setMediaItem(audioItem,position)
        player.prepare()
        player.playWhenReady=wasPlaying
        audioStreamActive=true
      }
    }else if(!enabled && audioStreamActive){
      val source=foregroundSource
      if(source!=null && item.mediaId==foregroundVideoId){
        player.setMediaSource(source,position)
        player.prepare()
        player.playWhenReady=wasPlaying
      }
      audioStreamActive=false
    }
    if(player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_VIDEO)!=enabled){
      player.trackSelectionParameters=player.trackSelectionParameters.buildUpon()
        .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO,enabled)
        .build()
    }
  }

  @Synchronized fun applyPendingBackgroundMode(){
    if(backgroundRequested)setAudioOnlyBackground(true)
  }
  @Synchronized fun disposeWhenUnused(){
    // A paused MediaSessionService may be torn down even while the watch
    // Activity is visible. Do not release ExoPlayer out from under its UI.
    if(attachedUiCount==0)dispose()
  }
  @Synchronized fun get(context:Context):ExoPlayer {
    val existing=instance
    if(existing!=null)return existing
    // Prefer a secondary available Android decoder if the primary decoder rejects a format.
    // This cannot play codecs unsupported by every decoder on the device.
    val renderers=DefaultRenderersFactory(context.applicationContext)
      .setEnableDecoderFallback(true)
    // Short initial buffer for responsive starts, with adequate buffered media
    // to reduce rebuffering on fluctuating mobile connections.
    val loadControl=DefaultLoadControl.Builder()
      .setBufferDurationsMs(15_000,50_000,800,1_500)
      .build()
    val created=ExoPlayer.Builder(context.applicationContext)
      .setRenderersFactory(renderers)
      .setLoadControl(loadControl)
      .setAudioAttributes(AudioAttributes.DEFAULT,true)
      .setSeekForwardIncrementMs(10_000L)
      .setSeekBackIncrementMs(10_000L)
      .build()
    // Let Media3 manage the required wake/network locks while playback is
    // active. This is not a permanent wake lock and doesn't disable Doze.
    created.setWakeMode(C.WAKE_MODE_NETWORK)
    instance=created
    return created
  }
  @Synchronized fun peek():ExoPlayer?=instance
  @Synchronized fun dispose(){
    instance?.release()
    instance=null
    foregroundSource=null
    foregroundVideoId=""
    backgroundAudioUrl=null
    audioStreamActive=false
    backgroundRequested=false
  }
}
