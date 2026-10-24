package com.egytube.rebuilt

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Foreground media service + standard Android MediaSession playback notification.
 * Ongoing audio survives Home, lock screen, and ordinary removal from recent tasks.
 */
class PlaybackService:MediaSessionService(){
  private var session:MediaSession?=null
  override fun onCreate(){
    super.onCreate()
    val player=PlaybackCore.get(this)
    val launch=Intent(this,MainActivity::class.java)
      .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    val flag=PendingIntent.FLAG_UPDATE_CURRENT or
      (if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.M)PendingIntent.FLAG_IMMUTABLE else 0)
    val reopen=PendingIntent.getActivity(this,0,launch,flag)
    session=MediaSession.Builder(this,player).setSessionActivity(reopen).build()
  }
  override fun onGetSession(controllerInfo:MediaSession.ControllerInfo):MediaSession?=session
  override fun onDestroy(){
    session?.release()
    session=null
    PlaybackCore.dispose()
    super.onDestroy()
  }
}
