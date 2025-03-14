import 'dart:typed_data';

class ShareData {
  final Uint8List bytes;
  final String fileName;
  final String key;

  ShareData(this.bytes, this.fileName, this.key);
}
