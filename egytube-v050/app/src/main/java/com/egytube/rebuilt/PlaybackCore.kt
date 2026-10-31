package com.egytube.rebuilt

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
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
  @Synchronized fun setAudioOnlyBackground(enabled:Boolean){
    val player=instance?:return
    if(player.currentMediaItem==null)return
    if(player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_VIDEO)==enabled)return
    player.trackSelectionParameters=player.trackSelectionParameters.buildUpon()
      .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO,enabled)
      .build()
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
  }
}
