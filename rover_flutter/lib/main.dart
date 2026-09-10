import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'src/app.dart';
import 'src/maps/mapbox_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const mapbox = MapboxConfig();
  if (mapbox.hasUsablePublicToken) {
    MapboxOptions.setAccessToken(mapbox.publicToken);
  }
  runApp(const RoverApp());
}
