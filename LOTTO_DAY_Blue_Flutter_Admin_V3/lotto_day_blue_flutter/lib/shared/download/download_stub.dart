/// Non-web platforms: returns false so the caller can show the text instead.
Future<bool> downloadText(String filename, String content, {String mime = 'text/csv'}) async => false;
