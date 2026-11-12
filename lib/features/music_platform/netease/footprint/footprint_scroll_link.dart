import 'package:flutter/widgets.dart';

/// One collapse amount belongs to the page header; each period keeps its body
/// position. Preparing a horizontal transition aligns only the header portion
/// of the other positions before they paint, including a lazily mounted page.
class FootprintScrollLink extends ChangeNotifier {
  FootprintScrollLink() {
    _controllers = List.generate(
      3,
      (index) => _LinkedPeriodScroll(this, index),
    );
    for (var i = 0; i < controllers.length; i++) {
      _controllers[i].addListener(() => _scrolled(i));
    }
  }
  late final List<_LinkedPeriodScroll> _controllers;
  List<ScrollController> get controllers => _controllers;
  double range = 116;
  double _collapse = 0;
  double get collapse => _collapse.clamp(0, range);
  int _active = 0;
  bool _aligning = false;
  final _last = [0.0, 0.0, 0.0];

  void _scrolled(int index) {
    final control = _controllers[index];
    if (!control.hasClients) return;
    final offset = control.offset.clamp(0, double.infinity).toDouble();
    final delta = offset - _last[index];
    control.saved = offset;
    _last[index] = offset;
    if (_aligning || index != _active) return;
    final next = offset <= 0
        ? 0.0
        : (_collapse + delta).clamp(0, range).toDouble();
    if (next == _collapse) return;
    _collapse = next;
    notifyListeners();
  }

  void preparePages() {
    _aligning = true;
    try {
      for (var i = 0; i < controllers.length; i++) {
        if (i == _active) continue;
        final control = _controllers[i];
        final offset = control.hasClients ? control.offset : control.saved;
        final oldHeader = control.headerPart;
        final body = (offset - oldHeader).clamp(0, double.infinity);
        final target = body + collapse;
        control.saved = target;
        control.headerPart = collapse;
        _last[i] = target;
        if (control.hasClients && (control.offset - target).abs() > .01) {
          control.jumpTo(target);
        }
      }
      _controllers[_active].headerPart = collapse;
    } finally {
      _aligning = false;
    }
  }

  void select(int index) {
    if (index == _active) return;
    preparePages();
    _active = index;
    _last[index] = _controllers[index].hasClients
        ? _controllers[index].offset
        : _controllers[index].saved;
    notifyListeners();
  }

  void reset() {
    _active = 0;
    _collapse = 0;
    _aligning = true;
    for (var i = 0; i < controllers.length; i++) {
      final control = _controllers[i];
      control.saved = 0;
      control.headerPart = 0;
      _last[i] = 0;
      if (control.hasClients) control.jumpTo(0);
    }
    _aligning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final control in _controllers) {
      control.dispose();
    }
    super.dispose();
  }
}

class _LinkedPeriodScroll extends ScrollController {
  _LinkedPeriodScroll(this.link, this.index) : super(keepScrollOffset: false);
  final FootprintScrollLink link;
  final int index;
  double saved = 0, headerPart = 0;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => ScrollPositionWithSingleContext(
    physics: physics,
    context: context,
    initialPixels: oldPosition?.pixels ?? saved,
    keepScrollOffset: false,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}
