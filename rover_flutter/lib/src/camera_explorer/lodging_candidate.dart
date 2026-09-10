const _lodgingTerms = <String>{
  'accommodation',
  'bed and breakfast',
  'guest house',
  'hostel',
  'hotel',
  'inn',
  'lodging',
  'motel',
  'resort',
};

bool isLodgingCandidate({required String category, required String name}) {
  return _containsLodgingTerm(category) || _containsLodgingTerm(name);
}

bool _containsLodgingTerm(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim();
  return _lodgingTerms.any(
    (term) => RegExp('(^| )${RegExp.escape(term)}( |\$)').hasMatch(normalized),
  );
}
