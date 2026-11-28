import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:plezy/fork/update/apk_downloader.dart';
import 'package:plezy/fork/update/fork_release.dart';

ForkApkAsset assetOf(int size) => ForkApkAsset(name: 'a.apk', url: 'https://x/a.apk', size: size, abi: 'armeabi-v7a');

void main() {
  late Directory dir;
  late File part;
  late File apk;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('upd_dl');
    part = File(p.join(dir.path, 'a.apk.part'));
    apk = File(p.join(dir.path, 'a.apk'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  http.Client clientOf(Stream<List<int>> Function() body, {int? contentLength, int status = 200}) =>
      MockClient.streaming(
        (req, _) async => http.StreamedResponse(body(), status, contentLength: contentLength, request: req),
      );

  Stream<List<int>> chunks(int n, int each) async* {
    for (var i = 0; i < n; i++) {
      yield List.filled(each, 7);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<ForkDownloadFailure?> run(ForkApkDownloader d, int size, {Future<void>? abort, List<int>? seen}) async {
    try {
      await d.download(
        assetOf(size),
        part,
        apk,
        onProgress: (r, t) => seen?.add(r),
        abortTrigger: abort ?? Completer<void>().future,
      );
      return null;
    } on ForkDownloadException catch (e) {
      return e.failure;
    }
  }

  test('downloads, reports bounded increasing progress, renames', () async {
    final seen = <int>[];
    final d = ForkApkDownloader(clientFactory: () => clientOf(() => chunks(1000, 10), contentLength: 10000));
    expect(await run(d, 10000, seen: seen), isNull);
    expect(apk.lengthSync(), 10000);
    expect(part.existsSync(), isFalse);
    expect(seen.last, 10000);
    expect(seen.length, lessThanOrEqualTo(105));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('cancellation leaves neither .part nor .apk', () async {
    final abort = Completer<void>();
    final controller = StreamController<List<int>>();
    final d = ForkApkDownloader(clientFactory: () => clientOf(() => controller.stream));
    final f = run(d, 100, abort: abort.future);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.add(List.filled(10, 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    abort.complete();
    expect(await f, ForkDownloadFailure.cancelled);
    expect(part.existsSync(), isFalse);
    expect(apk.existsSync(), isFalse);
    unawaited(controller.close());
  });

  test('connection cut mid-way is a network failure', () async {
    Stream<List<int>> cut() async* {
      yield List.filled(10, 1);
      throw const SocketException('reset');
    }

    final d = ForkApkDownloader(clientFactory: () => clientOf(cut));
    expect(await run(d, 100), ForkDownloadFailure.network);
    expect(part.existsSync(), isFalse);
    expect(apk.existsSync(), isFalse);
  });

  test('wrong final size is a network failure', () async {
    final d = ForkApkDownloader(clientFactory: () => clientOf(() => chunks(5, 10)));
    expect(await run(d, 100), ForkDownloadFailure.network);
    expect(apk.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('Content-Length mismatch and HTTP error are network failures', () async {
    var d = ForkApkDownloader(clientFactory: () => clientOf(() => chunks(10, 10), contentLength: 99));
    expect(await run(d, 100), ForkDownloadFailure.network);
    d = ForkApkDownloader(clientFactory: () => clientOf(() => chunks(10, 10), status: 404));
    expect(await run(d, 100), ForkDownloadFailure.network);
  });

  test('ENOSPC is a storage failure', () async {
    final d = ForkApkDownloader(
      clientFactory: () => clientOf(() => chunks(10, 10)),
      writer: (file, data) async {
        await data.first;
        throw FileSystemException('write failed', file.path, const OSError('No space left on device', 28));
      },
    );
    expect(await run(d, 100), ForkDownloadFailure.storage);
    expect(part.existsSync(), isFalse);
  });

  test('30 s without bytes is a network failure', () {
    fakeAsync((async) {
      // ignore: close_sinks
      final controller = StreamController<List<int>>();
      final d = ForkApkDownloader(
        clientFactory: () => clientOf(() => controller.stream),
        writer: (file, data) => data.drain<void>(),
      );
      ForkDownloadFailure? result;
      unawaited(run(d, 100).then((v) => result = v));
      async.elapse(const Duration(seconds: 10));
      controller.add(List.filled(10, 1));
      async.elapse(const Duration(seconds: 29));
      expect(result, isNull);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(result, ForkDownloadFailure.network);
      unawaited(controller.close());
    });
  });
}
