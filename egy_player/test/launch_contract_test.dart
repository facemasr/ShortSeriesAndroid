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
}
