import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SPKI pin of a DER encoded X.509 certificate: `sha256/<base64>` of its
/// SubjectPublicKeyInfo, the format used by HPKP, OkHttp and Android's
/// network security config.
///
/// Pinning the public key rather than the whole certificate survives
/// certificate renewals that keep the key. Returns `null` for input that is
/// not a certificate.
String? spkiPin(Uint8List der) {
  try {
    final certificate = _sequence(der, 0);
    final tbs = _sequence(der, certificate.contentStart);
    var offset = tbs.contentStart;
    // version [0] EXPLICIT is optional.
    if (offset < der.length && der[offset] == 0xA0) {
      offset = _read(der, offset).end;
    }
    // serialNumber, signature, issuer, validity, subject.
    for (var i = 0; i < 5; i++) {
      offset = _read(der, offset).end;
    }
    final spki = _sequence(der, offset);
    final digest = sha256.convert(der.sublist(spki.start, spki.end));
    return 'sha256/${base64Encode(digest.bytes)}';
  } on FormatException {
    return null;
  }
}

/// Decides whether a TLS certificate is acceptable for a host.
///
/// Hosts without pins are not pinned (the system trust store alone decides).
/// Hosts with pins accept only a certificate whose SPKI pin is listed. List a
/// backup pin (a spare key, or the issuing CA's key) so a key rotation does
/// not lock users out.
final class CertificatePinner {
  /// Creates a pinner from `host -> pins`.
  const new(this.pins);

  /// Allowed pins per host name.
  final Map<String, List<String>> pins;

  /// Whether [host] has pins.
  bool isPinned(String host) => (pins[host] ?? const []).isNotEmpty;

  /// Whether [der] may be used for [host].
  bool allows(String host, Uint8List der) {
    final allowed = pins[host];
    if (allowed == null || allowed.isEmpty) return true;
    final pin = spkiPin(der);
    return pin != null && allowed.contains(pin);
  }
}

/// A DER element: tag, content offset and end offset in the buffer.
typedef _Element = ({int tag, int start, int contentStart, int end});

/// Reads the DER element starting at [start].
_Element _read(Uint8List bytes, int start) {
  if (start + 2 > bytes.length) throw const FormatException('truncated');
  final tag = bytes[start];
  final first = bytes[start + 1];
  var length = first;
  var header = 2;
  if (first >= 0x80) {
    final count = first & 0x7F;
    if (count == 0 || count > 4 || start + 2 + count > bytes.length) {
      throw const FormatException('length');
    }
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | bytes[start + 2 + i];
    }
    header += count;
  }
  final end = start + header + length;
  if (end > bytes.length) throw const FormatException('overflow');
  return (tag: tag, start: start, contentStart: start + header, end: end);
}

_Element _sequence(Uint8List bytes, int start) {
  final element = _read(bytes, start);
  if (element.tag != 0x30) throw const FormatException('expected SEQUENCE');
  return element;
}
