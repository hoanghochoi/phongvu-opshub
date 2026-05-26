class SortRequest {
  final String text;

  const SortRequest({required this.text});

  Map<String, dynamic> toJson() {
    return {'text': text};
  }
}
