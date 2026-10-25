package com.egytube.rebuilt

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultRenderersFactory

/**
 * A single app process player. The MediaSessionService owns its lifetime.
 * UI views must detach without releasing the active background audio session.
 */
object PlaybackCore {
  private var instance:ExoPlayer?=null
  @Synchronized fun get(context:Context):ExoPlayer {
    val existing=instance
    if(existing!=null)return existing
    // Prefer a secondary available Android decoder if the primary decoder rejects a format.
    // This cannot play codecs unsupported by every decoder on the device.
    val renderers=DefaultRenderersFactory(context.applicationContext)
      .setEnableDecoderFallback(true)
    val created=ExoPlayer.Builder(context.applicationContext)
      .setRenderersFactory(renderers)
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
