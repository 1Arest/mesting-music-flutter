import 'package:flutter/widgets.dart';
import '../../../experience/presentation/beta_now_playing_page.dart';
import '../messages/netease_messages_repository.dart';

/// Compatibility entry for chats, links and feature shortcuts. They all open
/// the same production player and its room panel, with one audio owner.
class NeteaseTogetherPage extends StatelessWidget {
  const NeteaseTogetherPage({this.invitee, this.invitation, super.key});
  final NeteasePerson? invitee;
  final String? invitation;
  @override
  Widget build(BuildContext context) => BetaNowPlayingPage(
    togetherInitially: true,
    togetherInvitee: invitee,
    togetherInvitation: invitation,
  );
}
