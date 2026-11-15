/// Una illustrazione disponibile per una carta sul sito online.
class ArtOption {
  final int imageId;
  final String url;
  final String smallUrl;

  const ArtOption({
    required this.imageId,
    required this.url,
    required this.smallUrl,
  });
}

class ArtResult {
  final List<ArtOption> options;
  final bool networkError;

  const ArtResult({this.options = const [], this.networkError = false});
}
