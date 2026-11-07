import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/social/domain/chat_message_actions.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('quoted messages keep a readable fallback and decode safely', () {
    final encoded = encodeChatMessageQuote(excerpt: '原始消息', content: '这是我的回复');

    expect(encoded, '「引用」原始消息\n——\n这是我的回复');
    expect(
      decodeChatMessageQuote(encoded),
      isA<ChatMessageQuote>()
          .having((quote) => quote.excerpt, 'excerpt', '原始消息')
          .having((quote) => quote.content, 'content', '这是我的回复'),
    );
    expect(decodeChatMessageQuote('普通文字'), isNull);
  });

  test('flattened received quotes keep the same reply presentation', () {
    final compact = decodeChatMessageQuote('「引用」Mesti：😊——你好');
    final escaped = decodeChatMessageQuote(r'「引用」Mesti：😊\n——\n你好');

    expect(compact, isNotNull);
    expect(compact!.excerpt, 'Mesti：😊');
    expect(compact.content, '你好');
    expect(escaped, isNotNull);
    expect(escaped!.excerpt, 'Mesti：😊');
    expect(escaped.content, '你好');
  });

  test('quoted voice uses a concise semantic excerpt', () {
    final voice = SocialMessage(
      id: 'voice',
      senderUid: 'friend',
      receiverUid: 'me',
      kind: SocialMessageKind.voice,
      text: '3200',
      sentAt: DateTime(2026, 8, 27),
    );

    expect(chatMessageQuoteExcerpt(voice), '语音消息');
    expect(savedChatMessageIdsKey(' me '), 'social_saved_message_ids_v1_me');
  });

  test(
    'saved message snapshots persist enough content for the collection',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final message = SavedChatMessage(
        id: 'saved-1',
        conversationUid: 'friend',
        senderUid: 'me',
        authorName: 'Mesting',
        kind: SocialMessageKind.text,
        text: '留在收藏中的消息',
        sentAt: DateTime(2026, 8, 27, 20, 10),
      );

      await writeSavedChatMessages(preferences, ' me ', [message]);

      expect(savedChatMessagesKey(' me '), 'social_saved_messages_v1_me');
      expect(
        readSavedChatMessages(preferences, 'me'),
        isA<List<SavedChatMessage>>()
            .having((messages) => messages, 'messages', hasLength(1))
            .having((messages) => messages.single.id, 'id', 'saved-1')
            .having((messages) => messages.single.text, 'text', '留在收藏中的消息'),
      );
    },
  );
}
