import '../active_roam/active_roam_session.dart';
import '../location/rover_location.dart';

/// Conservative distance gate: small GPS jitter and implausible jumps do not count.
class StoryWalkingGap {
  RoverLatLng? _anchor;
  DateTime? _anchorAt;
  double _walked = 0;
  bool _waiting = false;

  bool get ready => !_waiting || _walked >= 50;
  int get remainingMeters => (50 - _walked).clamp(0, 50).ceil();

  void reset() {
    _anchor = null;
    _anchorAt = null;
    _walked = 0;
    _waiting = false;
  }

  void completed(RoamSession session, DateTime now) {
    reset();
    _waiting = true;
    observe(session, now);
  }

  void observe(RoamSession session, DateTime now) {
    if (!_waiting || ready) return;
    final accuracy = session.currentGpsAccuracyMeters;
    if (session.status != RoamSessionStatus.active ||
        accuracy == null ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 25) {
      _anchor = null;
      _anchorAt = null;
      return;
    }
    final point = session.simulatedLocation;
    if (!point.latitude.isFinite || !point.longitude.isFinite) return;
    final previous = _anchor;
    if (previous == null) {
      _anchor = point;
      _anchorAt = now;
      return;
    }
    final meters = previous.distanceTo(point);
    final seconds = now.difference(_anchorAt!).inMilliseconds / 1000;
    if (meters < accuracy.clamp(8, 25) || seconds <= 0) return;
    _anchor = point;
    _anchorAt = now;
    // Do not infer movement through a long tracking outage or a GPS teleport.
    if (seconds > 60 || meters > seconds * 3 + 5) return;
    _walked += meters;
  }
}
