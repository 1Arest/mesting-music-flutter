import 'package:flutter/widgets.dart';
import 'beta_root_tab_viewport.dart';

/// A page supplies search behavior; the persistent shell supplies the one
/// official glass field. No music/book repository or route is owned here.
class BetaPageSearchController extends ChangeNotifier {
  BetaPageSearchController({
    required this.hintText,
    required this.onSubmitted,
    required this.onCleared,
    this.onChanged,
  });

  final String hintText;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCleared;
  final ValueChanged<String>? onChanged;
  final text = TextEditingController();
  final focus = FocusNode();
  bool _active = false, _hasResults = false;
  bool get active => _active;
  bool get hasResults => _hasResults;

  set hasResults(bool value) {
    if (_hasResults == value) return;
    _hasResults = value;
    notifyListeners();
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) focus.unfocus();
    notifyListeners();
  }

  void changed(String value) {
    onChanged?.call(value);
    if (value.trim().isEmpty && hasResults) clearResults();
    if (onChanged != null && value.trim().isNotEmpty) hasResults = true;
  }

  void submit(String value) {
    if (value.trim().isEmpty) return;
    hasResults = true;
    onSubmitted(value.trim());
    focus.unfocus();
  }

  void clearResults() {
    text.clear();
    focus.unfocus();
    hasResults = false;
    onCleared();
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}

/// Registrations belong to mounted pages, not global providers. Covered pages
/// stay registered for restoration, but cannot capture another route's field.
class BetaBottomSearchHost extends ChangeNotifier {
  BetaBottomSearchHost({required this.location, required this.openMusicSearch});
  String location;
  final VoidCallback openMusicSearch;
  final _bindings =
      <
        Object,
        ({
          String location,
          ModalRoute<dynamic>? route,
          BetaPageSearchController controller,
        })
      >{};

  BetaPageSearchController? get current {
    for (final binding in _bindings.values.toList().reversed) {
      if (binding.location == Uri.parse(location).path &&
          (binding.route?.isCurrent ?? true)) {
        return binding.controller;
      }
    }
    return null;
  }

  void register(
    Object owner,
    BetaPageSearchController controller, {
    required String location,
    required ModalRoute<dynamic>? route,
  }) {
    final old = _bindings[owner];
    if (old?.controller != controller) {
      old?.controller.removeListener(_changed);
      controller.addListener(_changed);
    }
    _bindings[owner] = (
      location: location,
      route: route,
      controller: controller,
    );
    notifyListeners();
  }

  void unregister(Object owner) {
    _bindings.remove(owner)?.controller.removeListener(_changed);
    notifyListeners();
  }

  void _changed() => notifyListeners();

  @override
  void dispose() {
    for (final binding in _bindings.values) {
      binding.controller.removeListener(_changed);
    }
    _bindings.clear();
    super.dispose();
  }
}

class BetaBottomSearchScope extends InheritedWidget {
  const BetaBottomSearchScope({
    required this.host,
    required super.child,
    super.key,
  });
  final BetaBottomSearchHost host;

  static BetaBottomSearchHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BetaBottomSearchScope>()?.host;

  @override
  bool updateShouldNotify(BetaBottomSearchScope oldWidget) =>
      host != oldWidget.host;
}

/// Bind after mounting and unbind on disposal. Watching ModalRoute also handles
/// Navigator-pushed album pages, which do not change GoRouter's location.
class BetaBottomSearchBinding extends StatefulWidget {
  const BetaBottomSearchBinding({
    required this.controller,
    required this.child,
    super.key,
  });
  final BetaPageSearchController controller;
  final Widget child;
  @override
  State<BetaBottomSearchBinding> createState() =>
      _BetaBottomSearchBindingState();
}

class _BetaBottomSearchBindingState extends State<BetaBottomSearchBinding> {
  BetaBottomSearchHost? _host;
  String? _location;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = BetaBottomSearchScope.maybeOf(context);
    if (host != _host) {
      _host?.unregister(this);
      _host = host;
      _location = host == null
          ? null
          : context
                    .getInheritedWidgetOfExactType<BetaTabVisibility>()
                    ?.location ??
                Uri.parse(host.location).path;
    }
    _register();
  }

  void _register() {
    if (!BetaTabVisibility.of(context)) {
      _host?.unregister(this);
      return;
    }
    _host?.register(
      this,
      widget.controller,
      location: _location!,
      route: ModalRoute.of(context),
    );
  }

  @override
  void didUpdateWidget(covariant BetaBottomSearchBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _register();
  }

  @override
  void dispose() {
    _host?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
