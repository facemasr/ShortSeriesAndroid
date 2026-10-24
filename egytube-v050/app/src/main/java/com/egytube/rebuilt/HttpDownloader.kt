package com.egytube.rebuilt

import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import java.net.HttpURLConnection
import java.net.URL

class HttpDownloader:Downloader(){
    override fun execute(request:Request):Response{
      val connection=URL(request.url()).openConnection() as HttpURLConnection
      connection.connectTimeout=18000
      connection.readTimeout=25000
      connection.instanceFollowRedirects=true
      connection.requestMethod=request.httpMethod()
      connection.setRequestProperty("User-Agent","Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
      connection.setRequestProperty("Accept-Encoding","identity")
      val lang=request.localization()?.localizationCode
      if(!lang.isNullOrBlank())connection.setRequestProperty("Accept-Language",lang)
      request.headers()?.forEach { (name,values)->values.forEach{connection.setRequestProperty(name,it)} }
      val payload=request.dataToSend()
      if(payload!=null&&payload.isNotEmpty()){
        connection.doOutput=true
        connection.outputStream.use{it.write(payload)}
      }
      try{
        val code=connection.responseCode
        val stream=if(code in 200..399)connection.inputStream else connection.errorStream
        val body=if(request.httpMethod().equals("HEAD",true))"" else
           stream?.bufferedReader(Charsets.UTF_8)?.use{it.readText()}.orEmpty()
        val headers=connection.headerFields.entries.filter{it.key!=null}
           .associate{it.key!! to it.value.orEmpty()}
        return Response(code,connection.responseMessage.orEmpty(),headers,body,connection.url.toExternalForm())
      }finally{connection.disconnect()}
    }
}
