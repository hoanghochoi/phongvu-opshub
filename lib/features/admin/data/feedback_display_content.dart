class FeedbackDisplayContent {
  final String body;
  final List<String> imageUrls;

  const FeedbackDisplayContent({required this.body, required this.imageUrls});

  factory FeedbackDisplayContent.fromRaw(String rawContent) {
    final bodyLines = <String>[];
    final imageUrls = <String>[];

    for (final line in rawContent.replaceAll('\r\n', '\n').split('\n')) {
      final imageMarker = _imageMarkerPattern.firstMatch(line);
      if (imageMarker == null) {
        bodyLines.add(line);
        continue;
      }

      final beforeMarker = line.substring(0, imageMarker.start).trimRight();
      final parsedLine = _parseImageLine(line.substring(imageMarker.end));
      if (parsedLine.imageUrls.isEmpty) {
        bodyLines.add(line);
        continue;
      }

      if (beforeMarker.trim().isNotEmpty) {
        bodyLines.add(beforeMarker);
      }
      imageUrls.addAll(parsedLine.imageUrls);

      if (parsedLine.leftoverText.isNotEmpty) {
        bodyLines.add('Hình ảnh: ${parsedLine.leftoverText}');
      }
    }

    return FeedbackDisplayContent(
      body: _normalizedBody(bodyLines),
      imageUrls: List.unmodifiable(_deduplicate(imageUrls)),
    );
  }
}

final _imageMarkerPattern = RegExp('Hình ảnh\\s*:', caseSensitive: false);

_ParsedFeedbackImageLine _parseImageLine(String value) {
  final imageUrls = <String>[];
  final leftovers = <String>[];

  for (final segment in value.split(';')) {
    final candidate = segment.trim();
    if (candidate.isEmpty) continue;
    if (_isDisplayableImageUrl(candidate)) {
      imageUrls.add(candidate);
    } else {
      leftovers.add(candidate);
    }
  }

  return _ParsedFeedbackImageLine(
    imageUrls: imageUrls,
    leftoverText: leftovers.join('; '),
  );
}

bool _isDisplayableImageUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  return uri.scheme == 'http' || uri.scheme == 'https';
}

String _normalizedBody(List<String> lines) {
  final body = lines.map((line) => line.trimRight()).join('\n').trim();
  return body.isEmpty ? 'Không có nội dung' : body;
}

List<String> _deduplicate(List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    if (seen.add(value)) result.add(value);
  }
  return result;
}

class _ParsedFeedbackImageLine {
  final List<String> imageUrls;
  final String leftoverText;

  const _ParsedFeedbackImageLine({
    required this.imageUrls,
    required this.leftoverText,
  });
}
