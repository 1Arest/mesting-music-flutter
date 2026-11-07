import 'package:flutter/material.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/beta_glass_controls.dart';

/// Keep the action visible while the credential mutation is pending. The
/// controller publishes welcome only on success; failures stay recoverable.
class BetaSignOutDialog extends StatefulWidget {
  const BetaSignOutDialog({required this.onConfirm, super.key});
  final Future<void> Function() onConfirm;
  @override
  State<BetaSignOutDialog> createState() => _BetaSignOutDialogState();
}

class _BetaSignOutDialogState extends State<BetaSignOutDialog> {
  bool _busy = false;
  String? _error;
  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = userFacingErrorMessage(error, fallback: '退出未完成，请重试');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '退出登录？',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              '云端数据会保留。退出后回到欢迎页，可选择其他登录方式或游客体验。',
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 22),
            BetaGlassButton(
              key: const ValueKey('beta10-confirm-sign-out'),
              loading: _busy,
              onPressed: _busy ? null : _confirm,
              child: const Text('退出登录'),
            ),
            const SizedBox(height: 12),
            BetaGlassButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ),
  );
}
