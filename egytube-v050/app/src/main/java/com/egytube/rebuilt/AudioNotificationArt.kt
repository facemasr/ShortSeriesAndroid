package com.egytube.rebuilt

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import java.io.ByteArrayOutputStream

/**
 * EGYTUBE original audio-player artwork for Android's system MediaStyle card.
 * Kept tiny, local, and cached: there are no remote image requests or media
 * stream changes when the phone enters background audio mode.
 */
object AudioNotificationArt {
  @Volatile private var cached:ByteArray?=null

  fun png():ByteArray {
    cached?.let{return it}
    return synchronized(this){
      cached?.let{return@synchronized it}
      val size=144
      val image=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888)
      val canvas=Canvas(image)
      val base=Paint(Paint.ANTI_ALIAS_FLAG).apply{color=Color.rgb(22,27,43)}
      canvas.drawRoundRect(RectF(0f,0f,144f,144f),27f,27f,base)
      val accent=Paint(Paint.ANTI_ALIAS_FLAG).apply{color=Color.rgb(240,47,73)}
      canvas.drawRoundRect(RectF(8f,8f,136f,136f),24f,24f,accent)
      val symbol=Paint(Paint.ANTI_ALIAS_FLAG).apply{
        color=Color.WHITE
        textAlign=Paint.Align.CENTER
        textSize=102f
        typeface=Typeface.create(Typeface.DEFAULT,Typeface.BOLD)
      }
      canvas.drawText("♫",72f,105f,symbol)
      val bytes=ByteArrayOutputStream().use{out->
        image.compress(Bitmap.CompressFormat.PNG,100,out)
        out.toByteArray()
      }
      image.recycle()
      cached=bytes
      bytes
    }
  }
}
