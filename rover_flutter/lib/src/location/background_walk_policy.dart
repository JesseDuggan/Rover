import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool get supportsBackgroundWalking =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool shouldPauseWalking(AppLifecycleState state) =>
    state == AppLifecycleState.detached ||
    (state == AppLifecycleState.paused && !supportsBackgroundWalking);
