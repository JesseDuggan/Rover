class ProblemDetails {
  const ProblemDetails({
    this.type,
    this.title,
    this.status,
    this.detail,
    this.instance,
    this.errors = const {},
  });

  final String? type;
  final String? title;
  final int? status;
  final String? detail;
  final String? instance;
  final Map<String, List<String>> errors;

  String get displayMessage {
    if (detail != null && detail!.isNotEmpty) {
      return detail!;
    }
    if (title != null && title!.isNotEmpty) {
      return title!;
    }
    if (errors.isNotEmpty) {
      return errors.values.expand((messages) => messages).join(' ');
    }
    return 'The Rover API returned an error.';
  }

  factory ProblemDetails.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    final errors = <String, List<String>>{};
    if (rawErrors is Map<String, dynamic>) {
      for (final entry in rawErrors.entries) {
        final value = entry.value;
        if (value is List) {
          errors[entry.key] = value.map((item) => item.toString()).toList();
        }
      }
    }

    return ProblemDetails(
      type: json['type'] as String?,
      title: json['title'] as String?,
      status: json['status'] as int?,
      detail: json['detail'] as String?,
      instance: json['instance'] as String?,
      errors: errors,
    );
  }
}

class RoverApiException implements Exception {
  const RoverApiException(this.message, {this.statusCode, this.problem});

  final String message;
  final int? statusCode;
  final ProblemDetails? problem;

  @override
  String toString() => message;
}

class RoverApiTimeoutException extends RoverApiException {
  const RoverApiTimeoutException(super.message);
}

class RoverApiConnectionException extends RoverApiException {
  const RoverApiConnectionException(super.message);
}
