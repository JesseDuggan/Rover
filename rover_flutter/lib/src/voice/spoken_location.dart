// Coordinates still travel with map and research requests. Only edit spoken copy.
const _decimal = r'[+\-−]?\d{1,3}(?:\.\d+)?';
const _degrees =
    r'(?:\s*°(?:\s*\d{1,2}[′\x27](?:\s*\d{1,2}(?:\.\d+)?[″"])?)?)?';
final _locationReading = RegExp(
  r'\b(?:latitude|lat)\s*[:=]?\s*' +
      _decimal +
      _degrees +
      r'(?:\s*[NS]\b)?[\s,;]+(?:and\s+)?(?:longitude|long|lon|lng)\s*[:=]?\s*' +
      _decimal +
      _degrees +
      r'(?:\s*[EW]\b)?' +
      r'|[+\-−]?\d{1,2}(?:\.\d+)?' +
      _degrees +
      r'\s*[NS]\b[\s,;]+' +
      _decimal +
      _degrees +
      r'\s*[EW]\b' +
      r'|[+\-−]?\d{1,2}\.\d{2,}\s*°?\s*,\s*[+\-−]?\d{1,3}\.\d{2,}(?:\s*°)?',
  caseSensitive: false,
);

String spokenLocationText(String text) {
  if (!_locationReading.hasMatch(text)) return text;
  final aside = RegExp(
    r'\s*\(\s*(?:' + _locationReading.pattern + r')\s*\)',
    caseSensitive: false,
  );
  return text
      .replaceAll(aside, '')
      .replaceAll(_locationReading, 'this location')
      .trim();
}
