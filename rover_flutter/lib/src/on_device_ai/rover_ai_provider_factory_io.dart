import 'dart:io';

import 'android_rover_ai_provider.dart';
import 'rover_ai_provider.dart';

RoverAiProvider createPlatformRoverAiProvider() {
  if (Platform.isAndroid) {
    return AndroidRoverAiProvider();
  }
  return const DisabledRoverAiProvider();
}
