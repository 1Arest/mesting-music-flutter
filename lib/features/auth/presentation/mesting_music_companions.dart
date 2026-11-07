import 'package:flutter/material.dart';
import 'beta_companion_stage.dart';

/// Entry illustration only; authentication and startup source images stay independent.
class MestingMusicCompanions extends StatelessWidget {
  const MestingMusicCompanions({this.height = 238, super.key});
  final double height;
  @override
  Widget build(BuildContext context) => BetaCompanionStage(height: height);
}
