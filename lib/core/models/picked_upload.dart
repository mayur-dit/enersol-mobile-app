import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// One file a customer has chosen but not yet sent.
///
/// ── Why this exists instead of a `dart:io` File ──────────────────────────────
/// The upload sheet used to hold `File(xfile.path)`. On a phone that is fine;
/// on the WEB build it cannot work at all. A browser never hands out a
/// filesystem path — `XFile.path` there is a `blob:` URL — so the sheet listed
/// the blob's uuid where the file name belongs
/// (`c2063d96-07fd-4736-a681-4192769bff51`), and `MultipartFile.fromPath` then
/// threw `UnsupportedError` from dart2js's stub `File` before a single byte left
/// the device. That is the "Something went wrong. Please try again." a customer
/// saw: not a server refusal, an exception thrown on their own machine.
///
/// So a pick carries whatever the platform actually gave us — a [path] to
/// stream from, or the [bytes] themselves — plus, always, a real [name].
class PickedUpload {
  const PickedUpload({
    required this.name,
    required this.size,
    this.mimeType,
    this.path,
    this.bytes,
  }) : assert(path != null || bytes != null, 'a pick needs a path or bytes');

  /// What the file is called, extension included — see [nameFor].
  final String name;

  /// How many bytes it weighs, as the picker reported them.
  final int size;

  /// Filesystem path, on the platforms that have one. Preferred over [bytes]:
  /// the http client streams it from disk, so a 100MB scan never has to sit in
  /// memory on a phone.
  final String? path;

  /// The file's contents, when there is no path to read them from (web).
  final Uint8List? bytes;

  /// What to label the multipart part.
  ///
  /// `package:http` labels an unlabelled part `application/octet-stream`, and
  /// `Enersol Upload` reads that field twice: to decide whether the file is an
  /// image worth resizing into a thumbnail, and as the Content-Type the file
  /// proxy later serves it with. An octet-stream photograph is stored full-size
  /// with no preview and downloads instead of opening — so the type is worked
  /// out here rather than left to a default.
  final String? mimeType;

  /// A camera shot or a gallery pick.
  ///
  /// The fallback extension is `jpg` because everything that reaches here is a
  /// photograph: a capture the browser named `image` (or did not name at all)
  /// is a JPEG, and saying so is better than sending it unnamed to a server
  /// that decides what a file is from its extension.
  static Future<PickedUpload> fromXFile(XFile file) async {
    // `length()` reads the blob on the web and stats the file on a phone —
    // either way it is the only size both platforms can answer.
    final size = await file.length();
    final name = nameFor(file.name, file.mimeType, fallbackExtension: 'jpg');
    final mime = file.mimeType ?? _mimeForName(name);
    // On the web `path` is a `blob:` URL — a handle for the browser, not a file
    // anything can open — so the bytes come along instead.
    final path = file.path;
    if (kIsWeb || path.isEmpty) {
      return PickedUpload(
        name: name,
        size: size,
        mimeType: mime,
        bytes: await file.readAsBytes(),
      );
    }
    return PickedUpload(name: name, size: size, mimeType: mime, path: path);
  }

  /// A row from `FilePicker`. Returns null for the one shape that is no use to
  /// anybody: neither bytes nor a path, which is what a cancelled or failed
  /// platform read looks like.
  static PickedUpload? fromPlatformFile(PlatformFile file) {
    // NO fallback extension here, and deliberately not `file.extension`: that
    // getter is `name.split('.').last`, which for a name with no dot in it
    // returns the whole name — appending it would produce `bill.bill`. The
    // picker is opened restricted to known types anyway, so a name that arrives
    // without an extension is better sent as it is and refused with the
    // server's own sentence than relabelled with a guess.
    final name = nameFor(file.name, null, fallbackExtension: '');
    final mime = _mimeForName(name);
    if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
      return PickedUpload(
        name: name,
        size: file.size,
        mimeType: mime,
        path: file.path,
      );
    }
    final bytes = file.bytes;
    if (bytes == null) return null;
    return PickedUpload(
      name: name,
      size: bytes.length,
      mimeType: mime,
      bytes: bytes,
    );
  }

  /// A file name the uploader will accept.
  ///
  /// `Enersol Upload` decides what a file IS from its extension — an
  /// extensionless name is read as one long extension, matches no allow-list
  /// and comes back "File type not allowed". A browser file input can easily
  /// hand over a name with no dot in it (a camera capture, a blob), so the
  /// extension is reconstructed from the MIME type rather than trusted to be
  /// there.
  static String nameFor(
    String? raw,
    String? mimeType, {
    String fallbackExtension = '',
  }) {
    final trimmed = (raw ?? '').trim();
    final base = trimmed.isEmpty
        ? 'upload-${DateTime.now().millisecondsSinceEpoch}'
        : trimmed;
    // A dot at position 0 is a hidden file, not an extension.
    final dot = base.lastIndexOf('.');
    if (dot > 0 && dot < base.length - 1) return base;

    final ext = _extensionFor(mimeType) ??
        (fallbackExtension.isEmpty ? null : fallbackExtension);
    return ext == null ? base : '$base.$ext';
  }

  /// The MIME type for a name the picker gave no type for — a phone pick, where
  /// `XFile.mimeType` is almost always null. Covers exactly what the sheet
  /// offers; anything else is left unlabelled rather than guessed at.
  static String? _mimeForName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument'
            '.wordprocessingml.document';
      default:
        return null;
    }
  }

  /// Only the types the sheet offers and the server accepts; anything else is
  /// better off keeping whatever name it came with than being mislabelled.
  static String? _extensionFor(String? mimeType) {
    switch ((mimeType ?? '').toLowerCase().split(';').first.trim()) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/heic':
        return 'heic';
      case 'image/heif':
        return 'heif';
      case 'application/pdf':
        return 'pdf';
      case 'application/msword':
        return 'doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return 'docx';
      default:
        return null;
    }
  }
}
