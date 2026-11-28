// FORK: bouton-mise-a-jour — streams the APK to disk with progress, idle timeout and cancellation.
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import '../../utils/platform_http_client_stub.dart'
    if (dart.library.io) '../../utils/platform_http_client_io.dart'
    as platform;
import 'fork_release.dart';

enum ForkDownloadFailure { network, storage, cancelled }

class ForkDownloadException implements Exception {
  const ForkDownloadException(this.failure, [this.cause]);

  final ForkDownloadFailure failure;
  final Object? cause;

  @override
  String toString() => 'ForkDownloadException($failure${cause != null ? ': $cause' : ''})';
}

/// Writes [data] into [file] (replaceable in tests to simulate a full disk).
typedef ForkApkWriter = Future<void> Function(File file, Stream<List<int>> data);

Future<void> _defaultWriter(File file, Stream<List<int>> data) async {
  final sink = file.openWrite();
  try {
    await sink.addStream(data);
    await sink.close();
  } catch (_) {
    try {
      await sink.close();
    } catch (_) {}
    rethrow;
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class ForkApkDownloader {
  ForkApkDownloader({
    http.Client Function()? clientFactory,
    ForkApkWriter? writer,
    this.idleTimeout = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _clientFactory = clientFactory ?? platform.createPlatformClient,
       _writer = writer ?? _defaultWriter,
       _now = now ?? DateTime.now;

  static const progressInterval = Duration(milliseconds: 250);

  final http.Client Function() _clientFactory;
  final ForkApkWriter _writer;
  final Duration idleTimeout;
  final DateTime Function() _now;

  /// Downloads [asset] into [partFile], then renames it to [apkFile].
  /// Throws [ForkDownloadException]; on any failure [partFile] is removed.
  Future<void> download(
    ForkApkAsset asset,
    File partFile,
    File apkFile, {
    required void Function(int received, int total) onProgress,
    required Future<void> abortTrigger,
  }) async {
    final client = _clientFactory();
    var cancelled = false;
    final requestAbort = Completer<void>();
    void abortRequest() {
      if (!requestAbort.isCompleted) requestAbort.complete();
    }

    void Function()? cancelStream;
    unawaited(
      abortTrigger.then((_) {
        cancelled = true;
        abortRequest();
        cancelStream?.call();
      }, onError: (Object _) {}),
    );
    try {
      final req = http.AbortableRequest('GET', Uri.parse(asset.url), abortTrigger: requestAbort.future);
      final http.StreamedResponse response;
      try {
        response = await client.send(req).timeout(idleTimeout);
      } on TimeoutException {
        abortRequest();
        throw const ForkDownloadException(ForkDownloadFailure.network, 'no response');
      }
      if (cancelled) throw const _Cancelled();
      if (response.statusCode != 200) {
        throw ForkDownloadException(ForkDownloadFailure.network, 'HTTP ${response.statusCode}');
      }
      final length = response.contentLength;
      if (length != null && length != asset.size) {
        throw ForkDownloadException(ForkDownloadFailure.network, 'Content-Length $length != ${asset.size}');
      }

      final total = asset.size;
      var received = 0;
      var lastPercent = -1;
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      void report({bool force = false}) {
        final percent = total > 0 ? received * 100 ~/ total : 0;
        final at = _now();
        if (force || percent > lastPercent || at.difference(lastReport) >= progressInterval) {
          lastPercent = percent;
          lastReport = at;
          onProgress(received, total);
        }
      }

      // Relay the response through a controller so that cancellation and the
      // idle timer can interrupt a stalled connection.
      final controller = StreamController<List<int>>();
      Timer? idle;
      StreamSubscription<List<int>>? sub;
      void fail(Object error) {
        idle?.cancel();
        sub?.cancel();
        if (!controller.isClosed) {
          controller.addError(error);
          controller.close();
        }
      }

      void armIdle() {
        idle?.cancel();
        idle = Timer(idleTimeout, () {
          abortRequest();
          fail(const ForkDownloadException(ForkDownloadFailure.network, 'idle timeout'));
        });
      }

      cancelStream = () => fail(const _Cancelled());
      sub = response.stream.listen(
        (chunk) {
          armIdle();
          received += chunk.length;
          if (received > total) {
            fail(const ForkDownloadException(ForkDownloadFailure.network, 'more bytes than expected'));
            return;
          }
          controller.add(chunk);
          report();
        },
        onError: (Object e) => fail(e),
        onDone: () {
          idle?.cancel();
          if (!controller.isClosed) controller.close();
        },
        cancelOnError: true,
      );
      armIdle();
      if (cancelled) cancelStream();

      await _writer(partFile, controller.stream);
      idle?.cancel();
      if (cancelled) throw const _Cancelled();
      if (received != total) {
        throw ForkDownloadException(ForkDownloadFailure.network, 'received $received of $total bytes');
      }
      final onDisk = await partFile.length();
      if (onDisk != total) {
        throw ForkDownloadException(ForkDownloadFailure.network, 'file is $onDisk of $total bytes');
      }
      report(force: true);
      await partFile.rename(apkFile.path);
    } catch (e) {
      await _deleteQuietly(partFile);
      if (e is ForkDownloadException && e.failure != ForkDownloadFailure.network) rethrow;
      if (cancelled || e is _Cancelled) throw const ForkDownloadException(ForkDownloadFailure.cancelled);
      if (e is ForkDownloadException) {
        appLogger.w('Update download failed', error: e);
        rethrow;
      }
      if (e is FileSystemException) {
        appLogger.w('Update download: storage error', error: e);
        throw ForkDownloadException(
          e.osError?.errorCode == 28 ? ForkDownloadFailure.storage : ForkDownloadFailure.network,
          e,
        );
      }
      appLogger.w('Update download failed', error: e);
      throw ForkDownloadException(ForkDownloadFailure.network, e);
    } finally {
      client.close();
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      // Synchronous on purpose: tiny, and usable under fakeAsync in tests.
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Best effort.
    }
  }
}
