import 'dart:convert';

/// Build 31 stored Base64(UTF8("SHA256:...")) under another SHA256 prefix.
/// Recognize only that exact encoding of a 32-byte digest; never accept a
/// different key or reinterpret arbitrary malformed data as a trusted key.
String normalizeStoredFingerprint(String value) {
  if (!value.startsWith('SHA256:')) return value;
  try {
    final decoded = utf8.decode(
      base64.decode(base64.normalize(value.substring(7))),
    );
    if (RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(decoded) &&
        base64.decode(base64.normalize(decoded.substring(7))).length == 32) {
      return decoded;
    }
  } on FormatException {
    // Already canonical, or malformed: keep it so comparison still fails safe.
  }
  return value;
}
