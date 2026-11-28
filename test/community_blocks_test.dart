import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:unsync/services/community_blocks.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('blocking ignores case and the leading @', () async {
    final blocks = CommunityBlocks();
    await blocks.block('@Troll');
    expect(blocks.isBlocked('troll'), isTrue);
    expect(blocks.isBlocked('@TROLL'), isTrue);
    expect(blocks.isBlocked('someone'), isFalse);
    expect(blocks.isBlocked(null), isFalse);
  });

  test('the list survives a restart and can be undone', () async {
    final first = CommunityBlocks();
    await first.block('alice');
    await first.block('bob');

    final second = CommunityBlocks();
    await second.ensureLoaded();
    expect(second.all, ['alice', 'bob']);

    await second.unblock('@Alice');
    final third = CommunityBlocks();
    await third.ensureLoaded();
    expect(third.all, ['bob']);
  });

  test('a damaged saved list is treated as empty', () async {
    SharedPreferences.setMockInitialValues({'community_blocked_v1': 'not json'});
    final blocks = CommunityBlocks();
    await blocks.ensureLoaded();
    expect(blocks.all, isEmpty);
  });
}
