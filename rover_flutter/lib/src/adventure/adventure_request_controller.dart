import 'package:flutter/widgets.dart';

import 'adventure_request.dart';

class AdventureRequestController extends ChangeNotifier {
  AdventureRequest? _request;

  AdventureRequest? get request => _request;

  void save(AdventureRequest request) {
    _request = request;
    notifyListeners();
  }

  void reset() {
    _request = null;
    notifyListeners();
  }
}

class AdventureRequestScope
    extends InheritedNotifier<AdventureRequestController> {
  const AdventureRequestScope({
    required AdventureRequestController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AdventureRequestController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AdventureRequestScope>();
    assert(scope != null, 'No AdventureRequestScope found in context.');
    return scope!.notifier!;
  }
}
