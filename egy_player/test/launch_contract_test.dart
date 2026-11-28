import 'package:flutter_test/flutter_test.dart';
import 'package:player/main.dart';
import 'package:player/site_watch_view.dart';
void main(){
  test('accepts movies and episodes only',(){
    expect(PlayTarget.parse('egyplayer://play?type=movie&id=12&lang=en')?.id,12);
    expect(PlayTarget.parse('egyplayer://play?type=episode&id=5')?.type,'episode');
    expect(PlayTarget.parse('egyplayer://play?type=channel&id=1'),isNull);
    expect(PlayTarget.parse('https://egyshow.com/watch?type=movie&id=1'),isNull);
    expect(PlayTarget.parse('egyplayer://play?type=movie&id=-1'),isNull);
  });
  test('universal direct links preserve query and reject unsafe input',(){
    expect(parseDirectMedia(' https://example.com/live.m3u8?token=abc ' )?.query,'token=abc');
    expect(parseDirectMedia('https://example.com/movie.mp4')?.host,'example.com');
    expect(parseDirectMedia('http://example.com/movie.mp4'),isNull);
    expect(parseDirectMedia('https://user:pass@example.com/video'),isNull);
    expect(parseDirectMedia('file:///private/video.mp4'),isNull);
    expect(parseDirectMedia('javascript:alert(1)'),isNull);
    expect(parseLocalMedia('content://media/external/video/media/123')?.scheme,'content');
    expect(parseLocalMedia('https://example.com/video.mp4'),isNull);
    expect(parseLocalMedia('file:///private/video.mp4'),isNull);
    expect(formatFor(Uri.parse('https://example.com/STREAM.M3U8?x=1')).toString(),'VideoFormat.hls');
    expect(formatFor(Uri.parse('https://example.com/video.mpd')).toString(),'VideoFormat.dash');
  });
  test('site route uses official HTTPS and includes parent episode ID',(){
    final target=PlayTarget.parse('egyplayer://play?type=episode&id=15&media_id=8&mode=reels&lang=ar');
    expect(target?.mediaId,8);
    expect(target?.reels,isTrue);
    final url=siteWatchEntry('episode',15,8,true);
    expect(url.host,'egyshow.com');
    expect(url.path,'/mobile-player');
    expect(isOfficialWatch(url),isTrue);
    expect(url.queryParameters['episode_id'],'15');
    expect(url.queryParameters['media_id'],'8');
    expect(isOfficialWatch(Uri.parse('https://egyshow.com/watch/abcdefghijklmnopqrstuvwxyz123456')),isTrue);
    expect(isOfficialWatch(Uri.parse('https://example.org/watch/abcdefghijklmnopqrstuvwxyz123456')),isFalse);
    expect(isOfficialSite(Uri.parse('https://egyshow.com.example.org/watch')),isFalse);
    expect(isCatalogueEntry(Uri.parse('https://egyshow.com/ar/series/demo/season/1/episode/2')),isTrue);
  });
  test('language preference takes priority over device locale',(){
    expect(useArabic(null,'ar'),isTrue);
    expect(useArabic(null,'en'),isFalse);
    expect(useArabic(null,'hi'),isFalse);
    expect(useArabic('ar','en'),isTrue);
    expect(useArabic('en','ar'),isFalse);
    expect(useArabic('invalid','ar'),isTrue);
  });
}
