// Unit tests for the pure helpers ported from teams_util.c.

import 'package:flutter_test/flutter_test.dart';
import 'package:teams_lite/core/teams_util.dart';

void main() {
  group('stripUserPrefix', () {
    test('drops 8: prefix', () {
      expect(TeamsUtil.stripUserPrefix('8:orgid:abc'), 'orgid:abc');
    });
    test('drops 1: prefix', () {
      expect(TeamsUtil.stripUserPrefix('1:user@example.com'),
          'user@example.com');
    });
    test('keeps 2: prefix', () {
      expect(TeamsUtil.stripUserPrefix('2:foo'), '2:foo');
    });
    test('leaves bare names untouched', () {
      expect(TeamsUtil.stripUserPrefix('orgid:abc'), 'orgid:abc');
    });
  });

  group('contactUrlToName', () {
    test('strips numeric prefix on 8:', () {
      expect(
        TeamsUtil.contactUrlToName(
            'https://teams.live.com/v1/users/ME/contacts/8:orgid:abc'),
        'orgid:abc',
      );
    });
    test('keeps prefix on 48:', () {
      expect(
        TeamsUtil.contactUrlToName('https://x/v1/users/48:calllogs'),
        '48:calllogs',
      );
    });
    test('returns null when no user segment', () {
      expect(TeamsUtil.contactUrlToName('https://x/v1/users/ME'), isNull);
    });
  });

  group('threadUrlToName', () {
    test('extracts 19: thread id', () {
      expect(
        TeamsUtil.threadUrlToName(
            'https://teams.live.com/v1/users/ME/conversations/19:abc@unq.gbl.spaces'),
        '19:abc@unq.gbl.spaces',
      );
    });
    test('returns null without a thread segment', () {
      expect(TeamsUtil.threadUrlToName('https://x/v1/users/ME'), isNull);
    });
  });

  group('directConversationId', () {
    // Mirrors the plugin: only colon-free names get the 8: prefix.
    test('prefixes colon-free names with 8:', () {
      expect(TeamsUtil.directConversationId('johnsmith'), '8:johnsmith');
    });
    test('leaves ids containing a colon alone', () {
      expect(TeamsUtil.directConversationId('live:.cid.x'), 'live:.cid.x');
      expect(TeamsUtil.directConversationId('8:foo'), '8:foo');
    });
  });
}
