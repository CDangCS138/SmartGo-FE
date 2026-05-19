import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  final String _secret =
      const String.fromEnvironment('ENCRYPTION_SECRET', defaultValue: '');
  final String _algorithm = const String.fromEnvironment('ENCRYPTION_ALGORITHM',
      defaultValue: 'aes-256-cbc');

  EncryptionService();

  bool get isAlgorithmSupported => _algorithm.toLowerCase() == 'aes-256-cbc';

  List<Uint8List> _deriveAllPossibleKeys(String secret) {
    final cleanSecret = secret.trim();
    final secretBytes = utf8.encode(cleanSecret);
    final keys = <Uint8List>[];

    // 1. Code chuẩn của BE: Hash chuỗi secret từ file .env bằng SHA-256
    final sha256Digest = crypto.sha256.convert(secretBytes).bytes;
    keys.add(Uint8List.fromList(sha256Digest));

    // 2. BACKEND BỊ LỖI: Server BE không đọc được file .env, nên nó dùng chuỗi mặc định.
    // Ta chèn thẳng hash của chuỗi này vào để tự giải cứu luôn.
    final fallbackBytes = utf8.encode('smart-go-default-aes-256-secret-key');
    final fallbackDigest = crypto.sha256.convert(fallbackBytes).bytes;
    keys.add(Uint8List.fromList(fallbackDigest));

    // 3. Đề phòng BE parse .env bị dính nháy kép
    final quotedBytes = utf8.encode('"$cleanSecret"');
    keys.add(Uint8List.fromList(crypto.sha256.convert(quotedBytes).bytes));

    return keys;
  }

  bool looksLikeWrapped(dynamic data) {
    final ok = data is Map && data['iv'] is String && data['payload'] is String;
    if (ok) {
      _log('response has iv/payload: true');
    }
    return ok;
  }

  static Object? _decryptAndDecodeInIsolate(Map<String, dynamic> args) {
    final ivBase64 = args['iv'] as String;
    final payloadBase64 = args['payload'] as String;
    final keys = args['keys'] as List<Uint8List>;

    Uint8List ivBytes;
    Uint8List cipherBytes;
    try {
      ivBytes = base64.decode(ivBase64);
      cipherBytes = base64.decode(payloadBase64);
    } catch (e) {
      return null;
    }

    for (var i = 0; i < keys.length; i++) {
      try {
        final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(keys[i]),
            mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
        final ivObj = encrypt.IV(ivBytes);
        final decrypted =
            encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: ivObj);

        final decoded = utf8.decode(decrypted, allowMalformed: true);
        final trimmed = decoded.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          return json.decode(decoded);
        }
      } catch (_) {}
    }

    return null;
  }

  static String? _decryptToStringInIsolate(Map<String, dynamic> args) {
    final ivBase64 = args['iv'] as String;
    final payloadBase64 = args['payload'] as String;
    final keys = args['keys'] as List<Uint8List>;

    Uint8List ivBytes;
    Uint8List cipherBytes;
    try {
      ivBytes = base64.decode(ivBase64);
      cipherBytes = base64.decode(payloadBase64);
    } catch (_) {
      return null;
    }

    for (var i = 0; i < keys.length; i++) {
      try {
        final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(keys[i]),
            mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
        final ivObj = encrypt.IV(ivBytes);
        final decrypted =
            encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: ivObj);

        final decoded = utf8.decode(decrypted, allowMalformed: true);
        final trimmed = decoded.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          return decoded;
        }
      } catch (_) {
        // Thử key tiếp theo
      }
    }

    return null;
  }

  String? tryDecryptPayload(String ivBase64, String payloadBase64) {
    if (_secret.isEmpty) {
      _log('decrypt fail: ENCRYPTION_SECRET is empty');
      return null;
    }
    if (!isAlgorithmSupported) {
      _log('decrypt fail: unsupported algorithm $_algorithm');
      return null;
    }

    Uint8List ivBytes;
    Uint8List cipherBytes;
    try {
      ivBytes = base64.decode(ivBase64);
      cipherBytes = base64.decode(payloadBase64);
    } catch (e) {
      _log('decrypt fail: invalid base64 encoding - $e');
      return null;
    }

    final keys = _deriveAllPossibleKeys(_secret);

    for (var i = 0; i < keys.length; i++) {
      try {
        final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(keys[i]),
            mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
        final ivObj = encrypt.IV(ivBytes);
        final decrypted =
            encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: ivObj);

        final decoded = utf8.decode(decrypted, allowMalformed: true);
        final trimmed = decoded.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          _log('decrypt success with key variant $i');
          return decoded;
        }
      } catch (_) {
        // Thử key tiếp theo
      }
    }

    _log(
        'decrypt fail: all key derivation variants failed (Invalid pad block)');
    return null;
  }

  Object? tryDecryptWrapped(Map<String, dynamic> wrapped) {
    final ivRaw = wrapped['iv'];
    final payloadRaw = wrapped['payload'];
    if (ivRaw is! String || payloadRaw is! String) {
      // Tránh in ra log lỗi khi đây chỉ là JSON thông thường
      if (ivRaw != null || payloadRaw != null) {
        _log('decrypt fail: iv/payload not string');
      }
      return null;
    }
    final decrypted = tryDecryptPayload(ivRaw, payloadRaw);
    if (decrypted == null) {
      return null;
    }
    try {
      return json.decode(decrypted);
    } catch (e) {
      _log('decrypt fail: $e');
      return null;
    }
  }

  Future<Object?> tryDecryptWrappedAsync(Map<String, dynamic> wrapped) async {
    final ivRaw = wrapped['iv'];
    final payloadRaw = wrapped['payload'];
    if (ivRaw is! String || payloadRaw is! String) {
      // Tránh in ra log lỗi khi đây chỉ là JSON thông thường
      if (ivRaw != null || payloadRaw != null) {
        _log('decrypt fail: iv/payload not string');
      }
      return null;
    }

    if (_secret.isEmpty) {
      _log('decrypt fail: ENCRYPTION_SECRET is empty');
      return null;
    }
    if (!isAlgorithmSupported) {
      _log('decrypt fail: unsupported algorithm $_algorithm');
      return null;
    }

    final keys = _deriveAllPossibleKeys(_secret);

    try {
      // Đẩy toàn bộ tác vụ giải mã và giải nén (JSON Decode) sang Isolate ngầm
      final result = await compute(_decryptAndDecodeInIsolate, {
        'iv': ivRaw,
        'payload': payloadRaw,
        'keys': keys,
      });

      if (result != null) {
        _log('decrypt success async');
      } else {
        _log(
            'decrypt fail: all key derivation variants failed (Invalid pad block)');
      }
      return result;
    } catch (e) {
      _log('decrypt fail async: $e');
      return null;
    }
  }

  Future<String?> tryDecryptWrappedToStringAsync(
    Map<String, dynamic> wrapped,
  ) async {
    final ivRaw = wrapped['iv'];
    final payloadRaw = wrapped['payload'];
    if (ivRaw is! String || payloadRaw is! String) {
      if (ivRaw != null || payloadRaw != null) {
        _log('decrypt fail: iv/payload not string');
      }
      return null;
    }

    if (_secret.isEmpty) {
      _log('decrypt fail: ENCRYPTION_SECRET is empty');
      return null;
    }
    if (!isAlgorithmSupported) {
      _log('decrypt fail: unsupported algorithm $_algorithm');
      return null;
    }

    final keys = _deriveAllPossibleKeys(_secret);

    try {
      final result = await compute(_decryptToStringInIsolate, {
        'iv': ivRaw,
        'payload': payloadRaw,
        'keys': keys,
      });

      if (result != null) {
        _log('decrypt success async');
      } else {
        _log(
            'decrypt fail: all key derivation variants failed (Invalid pad block)');
      }
      return result;
    } catch (e) {
      _log('decrypt fail async: $e');
      return null;
    }
  }

  void _log(String message) {
    try {
      debugPrint('[Encryption] $message');
    } catch (_) {}
  }
}
