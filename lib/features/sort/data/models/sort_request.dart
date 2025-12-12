class SortRequest {
  final String text;
  final String user;

  const SortRequest({
    required this.text,
    required this.user,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'user': user,
    };
  }
}
