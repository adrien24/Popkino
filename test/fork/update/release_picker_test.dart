import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/fork/update/fork_release.dart';
import 'package:plezy/fork/update/release_picker.dart';

Map<String, Object?> rel(
  String tag, {
  bool draft = false,
  bool pre = false,
  String date = '2026-01-01T00:00:00Z',
  bool apk = true,
  String body = '',
}) => {
  'tag_name': tag,
  'name': tag,
  'draft': draft,
  'prerelease': pre,
  'published_at': date,
  'html_url': 'https://github.com/r/$tag',
  'body': body,
  'assets': [
    if (apk)
      {
        'name': 'popkino-android-armeabi-v7a-${tag.replaceFirst('v', '')}.apk',
        'browser_download_url': 'https://x/$tag.apk',
        'size': 5,
      },
  ],
};

void main() {
  ForkRelease? pick(List<Object?> j, {String installed = '0.1.0'}) =>
      pickForkRelease(j, installedVersion: installed, supportedAbis: ['armeabi-v7a', 'armeabi'], installedTranche: 1);

  test('pre-release is proposed', () {
    expect(pick([rel('0.2.0', pre: true)])?.isPrerelease, isTrue);
  });

  test('draft ignored', () {
    expect(pick([rel('0.2.0', draft: true)]), isNull);
  });

  test('highest number wins over most recent date', () {
    final r = pick([rel('0.3.0', date: '2026-01-01T00:00:00Z'), rel('0.2.0', date: '2026-06-01T00:00:00Z')]);
    expect(r?.version, '0.3.0');
  });

  test('v prefix and 1.0.0', () {
    expect(pick([rel('v0.2.0')])?.version, '0.2.0');
    expect(pick([rel('1.0.0')])?.version, '1.0.0');
  });

  test('invalid tag ignored', () {
    expect(pick([rel('nightly'), rel('0.2.0-beta')]), isNull);
  });

  test('not newer gives null', () {
    expect(pick([rel('0.1.0')]), isNull);
    expect(pick([rel('0.2.0')], installed: '0.2.0+5'), isNull);
  });

  test('newest without apk gives null even if an older one has one', () {
    expect(pick([rel('0.3.0', apk: false), rel('0.2.0')]), isNull);
  });

  test('compareForkVersions', () {
    expect(compareForkVersions('0.10.0', '0.9.0'), greaterThan(0));
    expect(compareForkVersions('v1.0.0', '1.0.0+3'), 0);
  });

  test('releaseNotesToPlainText', () {
    const md = '## Title\n\n**bold** and `code` [link](http://a)\n- one\n* two\n\n\n\nend';
    expect(releaseNotesToPlainText(md), 'Title\n\nbold and code link\n• one\n• two\n\nend');
  });
}
