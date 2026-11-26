class Message {
  final String text;
  final bool isSent;
  final String time;
  final bool delivered;

  /// Path of a picture file for picture messages; null for text.
  final String? imagePath;
  final String? caption;

  const Message({
    required this.text,
    required this.isSent,
    required this.time,
    this.delivered = true,
    this.imagePath,
    this.caption,
  });
}
