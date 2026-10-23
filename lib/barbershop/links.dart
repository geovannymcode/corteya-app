String? shopSlug(String input, {String appLinkHost = ''}) {
  final text = input.trim();
  if (RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(text) &&
      text.length <= 100) {
    return text;
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.hasQuery || uri.hasFragment) return null;
  final parts = uri.pathSegments;
  String? slug;
  if (uri.scheme == 'corteya' && uri.host == 'b' && parts.length == 1) {
    slug = parts.single;
  }
  if (uri.scheme == 'https' &&
      appLinkHost.isNotEmpty &&
      uri.host == appLinkHost &&
      parts.length == 2 &&
      parts.first == 'b') {
    slug = parts.last;
  }
  return slug != null &&
          RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug) &&
          slug.length <= 100
      ? slug
      : null;
}
