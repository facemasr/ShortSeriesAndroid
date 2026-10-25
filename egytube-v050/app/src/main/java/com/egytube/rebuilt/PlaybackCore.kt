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
  /** Read the live media session without creating a player just to display Home. */
  @Synchronized fun peek():ExoPlayer?=instance
  @Synchronized fun get(context:Context):ExoPlayer {
    val existing=instance
    if(existing!=null)return existing
    // Prefer a secondary available Android decoder if the primary decoder rejects a format.
    // This cannot play codecs unsupported by every decoder on the device.
    val renderers=DefaultRenderersFactory(context.applicationContext)
      .setEnableDecoderFallback(true)
    val buffers=DefaultLoadControl.Builder()
      .setBufferDurationsMs(12_000,35_000,1_000,2_000)
      .build()
    val created=ExoPlayer.Builder(context.applicationContext)
      .setRenderersFactory(renderers)
      .setLoadControl(buffers)
      .setWakeMode(C.WAKE_MODE_NETWORK)
      .setAudioAttributes(AudioAttributes.DEFAULT,true)
      .build()
    instance=created
    return created
  }
  @Synchronized fun dispose(){
    instance?.release()
    instance=null
  }
}
