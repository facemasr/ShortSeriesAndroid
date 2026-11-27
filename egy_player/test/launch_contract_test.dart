import 'package:flutter_test/flutter_test.dart';
import 'package:player/main.dart';
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
}
