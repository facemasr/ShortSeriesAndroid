import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'yacine_channel_resolver.dart';

/// The Android equivalent of EGY TV Sport's *device-local* VLC relay.
/// It is NOT a remote EGYSHOW proxy. It binds solely to 127.0.0.1, keeps
/// provider-declared headers in RAM, and never asks for DRM keys or bypasses
/// provider authentication. A stable playlist URL survives routine API token
/// rotation so the VLC decoder need not be recreated.
class YacineLocalRelay {
  YacineLocalRelay({
    http.Client? client,
    this.onSourceFailure,
    this.allowLoopbackForTests = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final void Function()? onSourceFailure;
  final bool allowLoopbackForTests;
  HttpServer? _server;
  YacinePlaybackSource? _source;
  int _version = 0;
  final String _token = List<int>.generate(
      24, (_) => Random.secure().nextInt(256))
      .map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  final Map<String, _Manifest> _manifests = {};
  final Map<String, _OldAsset> _assets = {};

  bool get isRunning => _server != null;
  String get _base => 'http://127.0.0.1:' + _server!.port.toString();

  Uri get playlistUri => Uri.parse(_base + '/p/' + _token + '/r.m3u8');
  Uri get directUri => Uri.parse(_base + '/d/' + _token + '/stream');

  /// VLC supports only HTTP UA/Referer options reliably on all Android builds.
  /// Other provider-declared headers must be attached on the device to EVERY
  /// HLS manifest, segment and byte-range request.
  static bool needsRelay(YacinePlaybackSource source) {
    final path = source.uri.path.toLowerCase();
    final isHls = path.endsWith('.m3u8') ||
        source.providerMode?.toString() == '3';
    // Android VLC does not always apply its Referer to nested HLS
    // playlists/segments; on-device HTTP preserves the provider declaration.
    // For progressive sources VLC's ordinary UA/Referer options remain direct.
    return source.headers.keys.any((k) =>
        !const {'User-Agent', 'Referer'}.contains(k)) ||
        (isHls && source.headers.containsKey('Referer'));
  }

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((req) => unawaited(_serve(req)));
  }

  void setSource(YacinePlaybackSource source) {
    if (_source?.uri != source.uri ||
        !_sameHeaders(_source?.headers, source.headers)) {
      _version++;
      _manifests.clear();
      // Retain recent media-sequence mappings briefly: VLC may still be
      // requesting segments from the previous live playlist window.
      _assets.removeWhere((_, a) =>
          DateTime.now().difference(a.at) > const Duration(seconds: 90));
    }
    _source = source;
  }

  static bool _sameHeaders(Map<String, String>? a, Map<String, String> b) =>
      a != null && a.length == b.length &&
      b.entries.every((e) => a[e.key] == e.value);

  Future<void> close() async {
    final server = _server;
    _server = null;
    _source = null;
    _manifests.clear();
    _assets.clear();
    await server?.close(force: true);
    _client.close();
  }

  bool _safeUri(Uri uri) {
    if (!(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
    if (allowLoopbackForTests) return true;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local')) return false;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return true;
    if (ip.isLoopback || ip.isLinkLocal) return false;
    final bytes = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0], b = bytes[1];
      if (a == 0 || a == 10 || a == 127 || a >= 224 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) || (a == 169 && b == 254)) {
        return false;
      }
    }
    if (ip.type == InternetAddressType.IPv6 &&
        (bytes[0] & 0xfe) == 0xfc) return false;
    return true;
  }

  Future<_Upstream> _open(Uri first,
      Map<String, String> headers, {String? range}) async {
    var current = first;
    for (var i = 0; i < 5; i++) {
      if (!_safeUri(current)) throw const HttpException('Unsafe media URL');
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (range != null && RegExp(r'^bytes=\d*-\d*$').hasMatch(range)) {
        request.headers['Range'] = range;
      }
      final response = await _client.send(request)
          .timeout(const Duration(seconds: 12));
      if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null) throw const HttpException('Invalid redirect');
        current = current.resolve(location);
        continue;
      }
      if (const [401, 403, 404, 410].contains(response.statusCode)) {
        onSourceFailure?.call();
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.drain<void>();
        throw HttpException('Media HTTP ' + response.statusCode.toString());
      }
      return _Upstream(response, current);
    }
    throw const HttpException('Too many media redirects');
  }

  Future<_Manifest> _manifest(String lineage, [int depth = 0]) async {
    if (depth > 4 || !RegExp(r'^r(\.\d{1,3}){0,4}$').hasMatch(lineage)) {
      throw const FormatException('Invalid variant');
    }
    final current = _source;
    if (current == null) throw StateError('Channel unavailable');
    final cached = _manifests[lineage];
    if (cached != null && cached.version == _version &&
        DateTime.now().difference(cached.at) <
            const Duration(milliseconds: 1300)) return cached;

    Uri remote = current.uri;
    if (lineage != 'r') {
      final dot = lineage.lastIndexOf('.');
      final parent = await _manifest(lineage.substring(0, dot), depth + 1);
      final index = int.parse(lineage.substring(dot + 1));
      if (index >= parent.children.length) {
        throw const FormatException('Variant disappeared');
      }
      remote = parent.children[index];
    }
    final opened = await _open(remote, current.headers);
    final bytes = BytesBuilder();
    await for (final piece in opened.response.stream) {
      bytes.add(piece);
      if (bytes.length > 2000000) {
        throw const FormatException('Playlist too large');
      }
    }
    final body = utf8.decode(bytes.takeBytes(), allowMalformed: true)
        .replaceFirst('\uFEFF', '');
    if (!body.trimLeft().startsWith('#EXTM3U')) {
      throw const FormatException('Not an HLS playlist');
    }
    if (body.split('\n').any((line) =>
        line.trimLeft().startsWith('#EXT-X-SESSION-KEY:') ||
        (line.trimLeft().startsWith('#EXT-X-KEY:') &&
         !RegExp(r'\bMETHOD=NONE\b').hasMatch(line)))) {
      throw const FormatException('Protected HLS not supported by local relay');
    }

    final result = _Manifest(
        opened.finalUri, body, _version, DateTime.now());
    _rewrite(lineage, result);
    if (current == _source) _manifests[lineage] = result;
    return result;
  }

  String _uriForVariant(String lineage) =>
      _base + '/p/' + _token + '/' + lineage + '.m3u8';

  String _uriForAsset(String lineage, String key) =>
      _base + '/a/' + _token + '/' + lineage + '/' + key;

  /// One parser for both mapping and serving prevents variant-index drift.
  String _rewrite(String lineage, _Manifest m) {
    m.children.clear();
    m.assets.clear();
    final lines = m.body.split('\n');
    final output = <String>[];
    final uriAttribute = RegExp(r'URI="([^"]+)"');
    var segmentNumber = 0;
    var indexed = 0;
    var variantExpected = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        segmentNumber = int.tryParse(trimmed.split(':').last) ?? 0;
      }
      if (trimmed.startsWith('#EXT-X-STREAM-INF:')) {
        variantExpected = true;
        output.add(line);
        continue;
      }
      if (trimmed.startsWith('#EXT-X-MEDIA:') ||
          trimmed.startsWith('#EXT-X-I-FRAME-STREAM-INF:')) {
        final match = uriAttribute.firstMatch(line);
        if (match != null) {
          final child = lineage + '.' + m.children.length.toString();
          m.children.add(m.remote.resolve(match.group(1)!));
          output.add(line.replaceRange(
              match.start, match.end, 'URI="' + _uriForVariant(child) + '"'));
        } else {
          output.add(line);
        }
        continue;
      }
      if (trimmed.startsWith('#EXT-X-MAP:') ||
          trimmed.startsWith('#EXT-X-PART:') ||
          trimmed.startsWith('#EXT-X-PRELOAD-HINT:')) {
        final match = uriAttribute.firstMatch(line);
        if (match == null) {
          output.add(line);
          continue;
        }
        final key = 'i' + indexed.toString();
        indexed++;
        final remote = m.remote.resolve(match.group(1)!);
        m.assets[key] = remote;
        _assets[lineage + '/' + key] = _OldAsset(remote, DateTime.now());
        output.add(line.replaceRange(match.start, match.end,
            'URI="' + _uriForAsset(lineage, key) + '"'));
        continue;
      }
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        if (variantExpected) {
          final child = lineage + '.' + m.children.length.toString();
          m.children.add(m.remote.resolve(trimmed));
          output.add(_uriForVariant(child));
          variantExpected = false;
        } else {
          final key = 's' + segmentNumber.toString();
          segmentNumber++;
          final remote = m.remote.resolve(trimmed);
          m.assets[key] = remote;
          _assets[lineage + '/' + key] = _OldAsset(remote, DateTime.now());
          output.add(_uriForAsset(lineage, key));
        }
      } else {
        output.add(line);
      }
    }
    if (_assets.length > 5000) {
      _assets.removeWhere((_, a) =>
          DateTime.now().difference(a.at) > const Duration(seconds: 90));
    }
    return output.join('\n').trimRight() + '\n';
  }

  Future<Uri> _asset(String lineage, String key) async {
    var m = await _manifest(lineage);
    var value = m.assets[key];
    if (value == null) {
      _manifests.remove(lineage);
      m = await _manifest(lineage);
      value = m.assets[key];
    }
    if (value != null) return value;
    final old = _assets[lineage + '/' + key];
    if (old != null &&
        DateTime.now().difference(old.at) < const Duration(seconds: 90)) {
      return old.uri;
    }
    throw const HttpException('Segment outside live window');
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.connectionInfo?.remoteAddress.isLoopback != true ||
          (request.method != 'GET' && request.method != 'HEAD')) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      final parts = request.uri.pathSegments;
      if (parts.length < 3 || parts[1] != _token ||
          _source == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      response.headers.set('Cache-Control', 'no-store, private');
      if (parts[0] == 'p' && parts.length == 3 &&
          parts[2].endsWith('.m3u8')) {
        final lineage = parts[2].substring(0, parts[2].length - 5);
        final manifest = await _manifest(lineage);
        final body = utf8.encode(_rewrite(lineage, manifest));
        response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        response.contentLength = body.length;
        if (request.method == 'GET') response.add(body);
        await response.close();
        return;
      }
      Uri media;
      if (parts[0] == 'a' && parts.length == 4 &&
          RegExp(r'^[a-z]\d{1,15}$').hasMatch(parts[3])) {
        media = await _asset(parts[2], parts[3]);
      } else if (parts[0] == 'd' && parts.length == 3 &&
          parts[2] == 'stream') {
        media = _source!.uri;
      } else {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final upstream = await _open(media, _source!.headers,
          range: request.headers.value(HttpHeaders.rangeHeader));
      response.statusCode = upstream.response.statusCode;
      for (final key in [
        'content-type', 'content-length', 'content-range', 'accept-ranges'
      ]) {
        final value = upstream.response.headers[key];
        if (value != null) response.headers.set(key, value);
      }
      if (request.method == 'GET') {
        await response.addStream(upstream.response.stream);
      } else {
        await upstream.response.stream.drain<void>();
      }
      await response.close();
    } catch (_) {
      onSourceFailure?.call();
      try {
        response.statusCode = HttpStatus.serviceUnavailable;
        response.headers.contentType = ContentType.text;
        response.write('Stream temporarily unavailable');
        await response.close();
      } catch (_) {
        try { await response.close(); } catch (_) {}
      }
    }
  }
}

class _Upstream {
  const _Upstream(this.response, this.finalUri);
  final http.StreamedResponse response;
  final Uri finalUri;
}

class _Manifest {
  _Manifest(this.remote, this.body, this.version, this.at);
  final Uri remote;
  final String body;
  final int version;
  final DateTime at;
  final List<Uri> children = [];
  final Map<String, Uri> assets = {};
}

class _OldAsset {
  const _OldAsset(this.uri, this.at);
  final Uri uri;
  final DateTime at;
}
