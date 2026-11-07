import 'package:flutter/widgets.dart';
import 'qishui_qr_login_page.dart';

/// Keep welcome/account/navigation callers on one stable entry route.
/// Only official-app QR login is offered. This wrapper never constructs the
/// retired phone client, reads a phone number or sends a verification code.
class QishuiLoginPage extends StatelessWidget {
  const QishuiLoginPage({super.key});

  @override
  Widget build(BuildContext context) => const QishuiQrLoginPage();
}
