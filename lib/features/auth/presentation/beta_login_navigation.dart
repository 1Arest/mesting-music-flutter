import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'beta_welcome_page.dart';

/// One destination for profile, settings and protected Beta actions. The
/// existing coordinator owns successful-login feedback above this route.
Future<void> openBetaLogin(
  BuildContext context, {
  String redirect = '/profile',
}) async {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    await router.push(
      Uri(
        path: '/auth',
        queryParameters: {'mode': 'login', 'redirect': redirect},
      ).toString(),
    );
  } else {
    await Navigator.of(context).push(
      betaEntryRoute<void>(
        Builder(
          builder: (entry) =>
              BetaWelcomePage(onExperience: () => Navigator.of(entry).pop()),
        ),
      ),
    );
  }
}
