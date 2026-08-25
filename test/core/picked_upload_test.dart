import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enersol_customer/core/api/api_client.dart';
import 'package:enersol_customer/core/models/picked_upload.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What a customer picks, and what leaves the phone when they send it.
///
/// The regression suite for a sheet that could not upload at all on the web
/// build: `XFile.path` is a `blob:` URL there, so the file list showed the
/// blob's uuid where a name belongs and the send died inside dart2js's stub
/// `File` — reaching the customer as "Something went wrong. Please try again."
void main() {
  group('PickedUpload naming', () {
    test('a file keeps the name the browser gave it', () {
      // What the sheet used to show instead was `file.uri.pathSegments.last` of
      // a `blob:` URL: the uuid in the bug report, for a file the customer had
      // just chosen by name.
      final pick = PickedUpload.fromPlatformFile(PlatformFile(
        name: 'March bill.pdf',
        size: 3,
        bytes: Uint8List.fromList([1, 2, 3]),
      ));

      expect(pick!.name, 'March bill.pdf');
      expect(pick.mimeType, 'application/pdf');
      expect(pick.bytes, isNotNull);
    });

    test('a name with no extension is not given a made-up one', () {
      // `PlatformFile.extension` is `name.split('.').last`, which for a name
      // with no dot returns the whole name — trusting it produced `bill.bill`.
      final pick = PickedUpload.fromPlatformFile(PlatformFile(
        name: 'c2063d96-07fd-4736-a681-4192769bff51',
        size: 1,
        bytes: Uint8List.fromList([1]),
      ));

      expect(pick!.name, 'c2063d96-07fd-4736-a681-4192769bff51');
      expect(pick.mimeType, isNull);
    });

    test('a photo the browser did not name is still named a jpeg', () {
      // `Enersol Upload` decides what a file IS from its extension: an
      // extensionless name matches no allow-list and comes back "File type not
      // allowed", however good the bytes are. A capture is always a photo, so
      // the picker's own factory passes `jpg` as the fallback.
      expect(
        PickedUpload.nameFor('capture', 'image/jpeg', fallbackExtension: 'jpg'),
        'capture.jpg',
      );
      // The MIME type wins over the fallback when the picker knew one.
      expect(
        PickedUpload.nameFor('capture', 'image/png', fallbackExtension: 'jpg'),
        'capture.png',
      );
    });

    test('a hidden-file dot is not an extension', () {
      expect(
        PickedUpload.nameFor('.bill', 'image/png', fallbackExtension: 'jpg'),
        '.bill.png',
      );
    });

    test('an unnamed pick still gets a name', () {
      final name =
          PickedUpload.nameFor('', 'image/jpeg', fallbackExtension: 'jpg');
      expect(name, startsWith('upload-'));
      expect(name, endsWith('.jpg'));
    });

    test('a file on disk is streamed from its path, not read into memory',
        () async {
      final file = File('${Directory.systemTemp.path}/enersol-test-bill.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => file.deleteSync());

      final pick = await PickedUpload.fromXFile(XFile(file.path));

      expect(pick.path, file.path);
      expect(pick.bytes, isNull, reason: 'a phone streams it off disk');
      expect(pick.size, 3);
      expect(pick.mimeType, 'image/jpeg');
    });

    test('a row with neither bytes nor a path is dropped, not sent', () {
      expect(
        PickedUpload.fromPlatformFile(PlatformFile(name: 'x.pdf', size: 0)),
        isNull,
      );
    });
  });

  group('ApiClient.uploadFile', () {
    test('sends bytes, the real name and a real content type', () async {
      late http.Request seen;
      final api = ApiClient(httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'data': {'uploadPath': '/f?id=1', 'fileId': '1'},
          }),
          200,
        );
      }));

      await api.uploadFile(
        PickedUpload(
          name: 'bill.jpg',
          size: 3,
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        folder: 'document-requests',
      );

      final body = utf8.decode(seen.bodyBytes, allowMalformed: true);
      expect(body, contains('filename="bill.jpg"'));
      // Untyped, the server stores a photograph as a document: no thumbnail, no
      // resize, and a Content-Type that downloads rather than opens.
      expect(body, contains('image/jpeg'));
      expect(body, contains('document-requests'));
    });

    test('a transport failure is an ApiException, not a raw error', () async {
      // The sheet translates an ApiException into the server's own sentence and
      // everything else into "Something went wrong. Please try again." — this
      // was the one call in the app that could throw the second kind.
      final api = ApiClient(httpClient: MockClient((_) async {
        throw http.ClientException('connection closed');
      }));

      expect(
        () => api.uploadFile(PickedUpload(
          name: 'bill.jpg',
          size: 1,
          bytes: Uint8List.fromList([1]),
        )),
        throwsA(isA<ApiException>()),
      );
    });

    test('the server sentence survives a failed upload', () async {
      final api = ApiClient(httpClient: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'errors': [
              {'message': 'File type not allowed'},
            ],
          }),
          400,
        );
      }));

      await expectLater(
        api.uploadFile(PickedUpload(
          name: 'bill.zip',
          size: 1,
          bytes: Uint8List.fromList([1]),
        )),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          'File type not allowed',
        )),
      );
    });
  });
}
