import 'package:flutter/material.dart';

/// Compact visual circle, generous semantic target, and inline links share a
/// baseline. Wrap keeps enlarged text reachable without shrinking the type.
class BetaConsentRow extends StatelessWidget {
  const BetaConsentRow({
    required this.accepted,
    required this.onChanged,
    required this.onAgreement,
    required this.onPrivacy,
    super.key,
  });
  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onAgreement, onPrivacy;
  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final style = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: ink.withValues(alpha: .78),
    );
    Widget link(String label, VoidCallback action) => Semantics(
      link: true,
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Text(
            label,
            style: style.copyWith(color: ink, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 0,
        children: [
          Semantics(
            checked: accepted,
            label: '我已阅读并同意用户协议和隐私政策',
            child: InkResponse(
              onTap: () => onChanged(!accepted),
              radius: 22,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ink.withValues(alpha: .6)),
                      color: accepted ? ink : Colors.transparent,
                    ),
                    child: accepted
                        ? Icon(
                            Icons.check,
                            size: 10,
                            color: Theme.of(context).colorScheme.surface,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
          Text('我已阅读并同意 ', style: style),
          link('用户协议', onAgreement),
          Text(' 和 ', style: style),
          link('隐私政策', onPrivacy),
        ],
      ),
    );
  }
}
