import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'social_models.dart';

const _quotePrefix = '「引用」';
const _quoteDivider = '\n——\n';
const _savedMessageIdsPrefix = 'social_saved_message_ids_v1_';
const _savedMessagesPrefix = 'social_saved_messages_v1_';

/// A compact, readable representation of the message being quoted.
///
/// Quotes remain understandable in clients that have not yet upgraded: the
/// encoded text starts with the human-readable `「引用」` label rather than an
/// opaque machine payload.
class ChatMessageQuote {
  const ChatMessageQuote({required this.excerpt, required this.content});

  final String excerpt;
  final String content;
}

/// A local, durable snapshot for a saved chat message.
///
/// The chat backend deliberately owns the live conversation. Saved messages,
/// however, are a personal local collection so that a user can still browse
/// their saved content after the original conversation has moved on.
class SavedChatMessage {
  const SavedChatMessage({
    required this.id,
    required this.conversationUid,
    required this.senderUid,
    required this.authorName,
    required this.kind,
    required this.text,
    required this.sentAt,
    this.mediaUrl,
    this.thumbnailUrl,
  });

  final String id;
  final String conversationUid;
  final String senderUid;
  final String authorName;
  final SocialMessageKind kind;
  final String text;
  final DateTime sentAt;
  final String? mediaUrl;
  final String? thumbnailUrl;

  factory SavedChatMessage.fromMessage(
    SocialMessage message, {
    required String conversationUid,
    required String authorName,
  }) => SavedChatMessage(
    id: message.id,
    conversationUid: conversationUid,
    senderUid: message.senderUid,
    authorName: authorName,
    kind: message.kind,
    text: message.text,
    sentAt: message.sentAt,
    mediaUrl: message.mediaUrl,
    thumbnailUrl: message.thumbnailUrl,
  );

  factory SavedChatMessage.fromJson(Map<String, Object?> json) {
    final rawKind = json['kind']?.toString() ?? SocialMessageKind.text.name;
    final rawSentAt = json['sent_at']?.toString() ?? '';
    return SavedChatMessage(
      id: json['id']?.toString().trim() ?? '',
      conversationUid: json['conversation_uid']?.toString().trim() ?? '',
      senderUid: json['sender_uid']?.toString().trim() ?? '',
      authorName: json['author_name']?.toString().trim() ?? '好友',
      kind: SocialMessageKind.values.firstWhere(
        (value) => value.name == rawKind,
        orElse: () => SocialMessageKind.text,
      ),
      text: json['text']?.toString() ?? '',
      sentAt:
          DateTime.tryParse(rawSentAt)?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      mediaUrl: _optionalText(json['media_url']),
      thumbnailUrl: _optionalText(json['thumbnail_url']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'conversation_uid': conversationUid,
    'sender_uid': senderUid,
    'author_name': authorName,
    'kind': kind.name,
    'text': text,
    'sent_at': sentAt.toUtc().toIso8601String(),
    'media_url': mediaUrl,
    'thumbnail_url': thumbnailUrl,
  };
}

String savedChatMessageIdsKey(String uid) =>
    '$_savedMessageIdsPrefix${uid.trim()}';

String savedChatMessagesKey(String uid) => '$_savedMessagesPrefix${uid.trim()}';

Set<String> readSavedChatMessageIds(SharedPreferences preferences, String uid) {
  if (uid.trim().isEmpty) return <String>{};
  return preferences
          .getStringList(savedChatMessageIdsKey(uid))
          ?.map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet() ??
      <String>{};
}

Future<void> writeSavedChatMessageIds(
  SharedPreferences preferences,
  String uid,
  Set<String> messageIds,
) {
  final normalizedUid = uid.trim();
  if (normalizedUid.isEmpty) return Future<void>.value();
  final values = messageIds.toList()..sort();
  return preferences.setStringList(
    savedChatMessageIdsKey(normalizedUid),
    values,
  );
}

List<SavedChatMessage> readSavedChatMessages(
  SharedPreferences preferences,
  String uid,
) {
  final normalizedUid = uid.trim();
  if (normalizedUid.isEmpty) return const <SavedChatMessage>[];
  final raw = preferences.getString(savedChatMessagesKey(normalizedUid));
  if (raw == null || raw.isEmpty) return const <SavedChatMessage>[];
  final cached = _savedSnapshotCache[preferences]?[normalizedUid];
  if (cached?.$1 == raw) return cached!.$2;
  final decoded = _decodeSavedMessages(raw);
  (_savedSnapshotCache[preferences] ??= {})[normalizedUid] = (raw, decoded);
  return decoded;
}

final _savedSnapshotCache =
    Expando<Map<String, (String, List<SavedChatMessage>)>>(
      'saved-message-snapshots',
    );

/// Only the stored text crosses to the worker. Preferences and account state
/// remain on the caller; the raw-keyed cache cannot reuse another user's list.
Future<List<SavedChatMessage>> readSavedChatMessagesAsync(
  SharedPreferences preferences,
  String uid,
) async {
  final raw = preferences.getString(savedChatMessagesKey(uid.trim()));
  if (uid.trim().isEmpty || raw == null || raw.isEmpty) return const [];
  final cached = _savedSnapshotCache[preferences]?[uid.trim()];
  if (cached?.$1 == raw) return cached!.$2;
  final values = raw.length < 128 * 1024
      ? _decodeSavedMessages(raw)
      : await compute(
          _decodeSavedMessages,
          raw,
          debugLabel: 'saved-chat-messages',
        );
  final cache = _savedSnapshotCache[preferences] ??= {};
  if (cache.length >= 4) cache.remove(cache.keys.first);
  cache[uid.trim()] = (raw, values);
  return values;
}

List<SavedChatMessage> _decodeSavedMessages(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <SavedChatMessage>[];
    final messages = <String, SavedChatMessage>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final message = SavedChatMessage.fromJson(
        Map<String, Object?>.from(item),
      );
      if (message.id.isNotEmpty && message.conversationUid.isNotEmpty) {
        messages[message.id] = message;
      }
    }
    final values = messages.values.toList()
      ..sort((left, right) => right.sentAt.compareTo(left.sentAt));
    return List.unmodifiable(values);
  } on FormatException {
    return const <SavedChatMessage>[];
  }
}

Future<void> writeSavedChatMessages(
  SharedPreferences preferences,
  String uid,
  Iterable<SavedChatMessage> messages,
) async {
  final normalizedUid = uid.trim();
  if (normalizedUid.isEmpty) return Future<void>.value();
  final input = messages.toList(growable: false);
  final snapshot = input.length < 100
      ? _encodeSavedSnapshot(input)
      : await compute(
          _encodeSavedSnapshot,
          input,
          debugLabel: 'saved-chat-write',
        );
  await preferences.setString(savedChatMessagesKey(normalizedUid), snapshot.$1);
  (_savedSnapshotCache[preferences] ??= {})[normalizedUid] = snapshot;
}

(String, List<SavedChatMessage>) _encodeSavedSnapshot(
  List<SavedChatMessage> messages,
) {
  final deduplicated = <String, SavedChatMessage>{
    for (final message in messages)
      if (message.id.trim().isNotEmpty && message.conversationUid.isNotEmpty)
        message.id: message,
  };
  final values = deduplicated.values.toList()
    ..sort((left, right) => right.sentAt.compareTo(left.sentAt));
  return (
    jsonEncode(values.map((message) => message.toJson()).toList()),
    List.unmodifiable(values),
  );
}

/// Removes one personal collection entry without touching the live message or
/// any media object referenced by it.
///
/// Saved IDs and readable snapshots are persisted separately for backwards
/// compatibility. They must be updated together or the conversation can still
/// render the removed message as collected after this page has hidden it.
Future<bool> removeSavedChatMessage(
  SharedPreferences preferences,
  String uid,
  String messageId,
) async {
  final normalizedUid = uid.trim();
  final normalizedMessageId = messageId.trim();
  if (normalizedUid.isEmpty || normalizedMessageId.isEmpty) return false;

  final messageIds = readSavedChatMessageIds(preferences, normalizedUid);
  final removedId = messageIds.remove(normalizedMessageId);
  final messages = await readSavedChatMessagesAsync(preferences, normalizedUid);
  final remainingMessages = messages
      .where((message) => message.id != normalizedMessageId)
      .toList(growable: false);
  final removedSnapshot = remainingMessages.length != messages.length;
  if (!removedId && !removedSnapshot) return false;

  await Future.wait([
    writeSavedChatMessageIds(preferences, normalizedUid, messageIds),
    writeSavedChatMessages(preferences, normalizedUid, remainingMessages),
  ]);
  return true;
}

String chatMessageQuoteExcerpt(SocialMessage message) {
  final source = switch (message.kind) {
    SocialMessageKind.voice => '语音消息',
    SocialMessageKind.image => '图片',
    SocialMessageKind.video => '视频',
    SocialMessageKind.emoji => message.text,
    SocialMessageKind.text => message.text,
  };
  final compact = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 56) return compact.isEmpty ? '消息' : compact;
  return '${compact.substring(0, 55)}…';
}

String encodeChatMessageQuote({
  required String excerpt,
  required String content,
}) => '$_quotePrefix${excerpt.trim()}$_quoteDivider${content.trim()}';

ChatMessageQuote? decodeChatMessageQuote(String raw) {
  if (!raw.startsWith(_quotePrefix)) return null;
  // Messages sent by this client use [_quoteDivider]. Older message records
  // and some service responses can flatten its line breaks (or return literal
  // `\\n` sequences), which used to make a sent quote fall back to one large
  // raw text bubble after the optimistic sending state was replaced.
  final quotedBody = raw
      .substring(_quotePrefix.length)
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final divider = RegExp(r'\s*——\s*');
  final match = divider.firstMatch(quotedBody);
  if (match == null) return null;
  final excerpt = quotedBody.substring(0, match.start).trim();
  final content = quotedBody.substring(match.end).trim();
  if (excerpt.isEmpty || content.isEmpty) return null;
  return ChatMessageQuote(excerpt: excerpt, content: content);
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
