import 'package:wakelock_plus/wakelock_plus.dart';

abstract class ScreenAwakeController {
  Future<void> enable();
  Future<void> disable();
}

class WakelockScreenAwakeController implements ScreenAwakeController {
  const WakelockScreenAwakeController();

  @override
  Future<void> disable() => WakelockPlus.disable();

  @override
  Future<void> enable() => WakelockPlus.enable();
}

class MemoryScreenAwakeController implements ScreenAwakeController {
  bool enabled = false;

  @override
  Future<void> disable() async {
    enabled = false;
  }

  @override
  Future<void> enable() async {
    enabled = true;
  }
}
