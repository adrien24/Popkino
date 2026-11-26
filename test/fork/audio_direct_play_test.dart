// FORK: meilleure-piste-audio — CA9: choosing the audio track by channel count must never turn
// a direct play into a transcode (Plex decision, Jellyfin device profile).
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/transcode_quality_preset.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/jellyfin_client.dart';
import 'package:plezy/services/playback_initialization_types.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/track_selection_service.dart';
import 'package:plezy/utils/device_identity.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/http_fixtures.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// What a "Jusqu'à 5.1" launch hands to the resolver (see forkLaunchAudioIntent).
const _intent = AudioTrack(id: carriedAudioTrackId, language: 'en', channels: 6);

void main() {
  setUp(resetSharedPreferencesForTest);

  group('Plex', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('two English tracks (2.0 AAC, 5.1 DTS) and a 5.1 intent still direct play', () async {
      final paths = <String>[];
      final client = testPlexClient(
        serverId: ServerId('server-id'),
        handler: (request) async {
          paths.add(request.url.path);
          if (request.url.path == '/library/metadata/42') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'Metadata': [
                    {
                      'ratingKey': '42',
                      'type': 'episode',
                      'Media': [
                        {
                          'id': 7,
                          'container': 'mkv',
                          'videoCodec': 'h264',
                          'Part': [
                            {
                              'id': 99,
                              'key': '/library/parts/99/file.mkv',
                              'Stream': [
                                {'streamType': 1, 'id': 300, 'codec': 'h264'},
                                {
                                  'streamType': 2,
                                  'id': 301,
                                  'index': 0,
                                  'codec': 'aac',
                                  'languageCode': 'eng',
                                  'channels': 2,
                                  'selected': true,
                                },
                                {
                                  'streamType': 2,
                                  'id': 302,
                                  'index': 1,
                                  'codec': 'dts',
                                  'languageCode': 'eng',
                                  'channels': 6,
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('unexpected request', 500);
        },
      );
      addTearDown(client.close);

      final result = await client.getPlaybackInitialization(
        PlaybackInitializationOptions(
          metadata: testMediaItem(id: '42', backend: MediaBackend.plex, kind: MediaKind.episode, serverId: 'server-id'),
          selectedMediaIndex: 0,
          preferredAudioTrack: _intent,
          qualityPreset: TranscodeQualityPreset.original,
          sessionIdentifier: 'session-id',
          transcodeSessionId: 'transcode-id',
        ),
      );

      expect(result.isTranscoding, isFalse);
      expect(result.playMethod, 'DirectPlay');
      expect(paths, isNot(contains('/video/:/transcode/universal/decision')));
    });
  });

  group('Jellyfin', () {
    setUpAll(() => DeviceIdentityService.debugOverride(const DeviceIdentity(platform: 'Test')));
    tearDownAll(() => DeviceIdentityService.debugOverride(null));

    test('the direct play profile bans no audio codec and the file direct plays', () async {
      Map<String, dynamic>? playbackInfoBody;
      final client = JellyfinClient.forTesting(
        connection: testJellyfinConnection(),
        httpClient: MockClient((request) async {
          if (request.url.path == '/Users/user-1/Items/item-1') {
            return jsonResponse({
              'Id': 'item-1',
              'Type': 'Episode',
              'Name': 'Episode',
              'MediaSources': [_source],
            });
          }
          if (request.url.path == '/Items/item-1/PlaybackInfo') {
            playbackInfoBody = jsonDecode(request.body) as Map<String, dynamic>;
            return jsonResponse({
              'MediaSources': [
                {..._source, 'SupportsDirectPlay': true},
              ],
            });
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(client.close);

      final result = await client.getPlaybackInitialization(
        PlaybackInitializationOptions(
          metadata: testMediaItem(
            id: 'item-1',
            backend: MediaBackend.jellyfin,
            kind: MediaKind.episode,
            serverId: 'srv-1',
          ),
          selectedMediaIndex: 0,
          preferredAudioTrack: _intent,
        ),
      );

      expect(result.isTranscoding, isFalse);
      expect(result.playMethod, 'DirectPlay');

      final profile = playbackInfoBody!['DeviceProfile'] as Map<String, dynamic>;
      final directPlay = [
        for (final entry in profile['DirectPlayProfiles'] as List<dynamic>) entry as Map<String, dynamic>,
      ].where((entry) => entry['Type'] == 'Video');
      expect(directPlay, isNotEmpty);
      for (final entry in directPlay) {
        expect(entry.containsKey('AudioCodec'), isFalse, reason: 'an audio codec must never block direct play');
      }
    });
  });
}

const Map<String, Object?> _source = {
  'Id': 'src-1',
  'Container': 'mkv',
  'MediaStreams': [
    {'Index': 0, 'Type': 'Video', 'Codec': 'h264'},
    {'Index': 1, 'Type': 'Audio', 'Codec': 'aac', 'Language': 'eng', 'Channels': 2, 'IsDefault': true},
    {'Index': 2, 'Type': 'Audio', 'Codec': 'dts', 'Language': 'eng', 'Channels': 6},
  ],
};
