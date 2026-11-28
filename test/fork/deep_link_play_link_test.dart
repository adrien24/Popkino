// FORK: non-régression du lien popkino://play (contrat partagé avec WatchNextProvider.kt)
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/fork_identity.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/services/deep_links/deep_link.dart';
import 'package:plezy/services/deep_links/deep_link_service.dart';

const _server = 'ceaf682febfbec1d59d978c5338dc71dee9ed91b';
const _itemId = '16298';

Profile _local(String id, String name) => Profile.local(id: id, displayName: name, createdAt: DateTime(2026));

final _parents = _local('parents', 'Parents');
final _kids = _local('kids', 'Kids');

class _FakeHost implements DeepLinkProfileHost {
  _FakeHost({required this.activeProfileId});

  @override
  final List<Profile> profiles = [_parents, _kids];

  @override
  String? activeProfileId;

  final switches = <String>[];

  @override
  Future<bool> switchTo(Profile profile) async {
    switches.add(profile.id);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/deep_link_play_link');

  // Built from the fork identity so the scheme is never a literal in the test.
  final scheme = ForkIdentity.urlScheme;
  final playUrl = '$scheme://play?server=$_server&id=$_itemId';
  final rowUrl = '$scheme://play?content_id=plezy_${_server}_$_itemId';
  final noIdUrl = '$scheme://play?server=$_server';

  late List<String> reports;
  late DeepLinkService service;

  setUp(() {
    reports = [];
    service = DeepLinkService.forTesting(channel, report: reports.add);
  });

  tearDown(() {
    channel.setMethodCallHandler(null);
  });

  ItemPlayTarget expectedTarget() => ItemPlayTarget(serverId: ServerId(_server), itemId: _itemId);

  test('a play link names the item on its server, in next mode', () {
    final link = DeepLink.tryParse(playUrl);
    expect(link, isA<PlayLink>());
    final play = link! as PlayLink;
    expect(play.target, expectedTarget());
    expect(play.mode, PlayMode.next);
    expect(play.profile, isNull);
  });

  test('a play link without an id is not a link', () {
    expect(DeepLink.tryParse(noIdUrl), isNull);
  });

  test('a home screen row link names the same item as the manual link', () {
    final link = DeepLink.tryParse(rowUrl);
    expect(link, isA<PlayLink>());
    expect((link! as PlayLink).target, expectedTarget());
  });

  test('a delivered play link reaches one session as a PlayLink, without any report', () async {
    service.host = _FakeHost(activeProfileId: 'parents');
    final launched = <DeepLink>[];
    service.attach(DeepLinkSession(profileId: 'parents', launch: (link) async => launched.add(link)));

    service.receive(playUrl);
    await pumpEventQueue();

    expect(launched, hasLength(1));
    expect(launched.single, isA<PlayLink>());
    expect((launched.single as PlayLink).target, expectedTarget());
    expect(reports, isEmpty);
  });

  test('a play link without an id stays on the current screen and is reported', () async {
    service.host = _FakeHost(activeProfileId: 'parents');
    final launched = <DeepLink>[];
    service.attach(DeepLinkSession(profileId: 'parents', launch: (link) async => launched.add(link)));

    service.receive(noIdUrl);
    await pumpEventQueue();

    expect(launched, isEmpty);
    expect(reports, [t.deepLinks.invalid]);
  });

  test('the launcher never hands a link to Watch Together', () {
    final source = File('lib/services/deep_links/deep_link_launcher.dart').readAsStringSync();
    expect(source, isNot(contains('watch_together')));
  });
}
