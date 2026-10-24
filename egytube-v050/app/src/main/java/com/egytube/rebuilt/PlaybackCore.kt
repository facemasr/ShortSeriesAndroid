package com.egytube.rebuilt

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.exoplayer.ExoPlayer

/**
 * A single app process player. The MediaSessionService owns its lifetime.
 * UI views must detach without releasing the active background audio session.
 */
object PlaybackCore {
  private var instance:ExoPlayer?=null
  @Synchronized fun get(context:Context):ExoPlayer {
    val existing=instance
    if(existing!=null)return existing
    val created=ExoPlayer.Builder(context.applicationContext)
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
