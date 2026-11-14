class DebugLog {
  static final List<String> lines = [];

  static void add(String message) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    lines.add('${two(t.minute)}:${two(t.second)} $message');
    if (lines.length > 80) lines.removeAt(0);
  }
}
