import 'dart:js_interop';
import 'dart:typed_data';

@JS('cmExtractPdfText')
external JSPromise<JSString> _cmExtractPdfText(JSUint8Array data);

Future<String> extractPdfText(Uint8List bytes) async =>
    (await _cmExtractPdfText(Uint8List.fromList(bytes).toJS).toDart).toDart;
