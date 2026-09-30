import 'dart:typed_data';
import 'dart:ui' as ui;

Future<Uint8List> prepareIdentificationPhoto(Uint8List original) async {
  if (original.length > 25 * 1024 * 1024) {
    throw const FormatException('Photo is too large.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(original);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = longest > 1024 ? 1024 / longest : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round().clamp(1, 1024),
      targetHeight: (descriptor.height * scale).round().clamp(1, 1024),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        // Re-encoding pixels strips EXIF/location metadata from the camera file.
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null || data.lengthInBytes > 2 * 1024 * 1024) {
          throw const FormatException(
            'Photo is too detailed. Try a closer view.',
          );
        }
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}
