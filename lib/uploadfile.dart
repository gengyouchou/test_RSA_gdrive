import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future handleUploadData(Map headers, String filename, String path) async {
  final file = new File(path);
  final fileLength = file.lengthSync().toString();
  String sessionUri;

  Uri uri = Uri.parse(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable');

  String body = json.encode({'name': filename});

  final initialStreamedRequest = new http.StreamedRequest('POST', uri)
    ..headers.addAll({
      'Authorization': headers['Authorization'],
      'Content-Length': utf8.encode(body).length.toString(),
      'Content-Type': 'application/json; charset=UTF-8',
      'X-Upload-Content-Type': 'application/json',
      'X-Upload-Content-Length': fileLength
    });

  initialStreamedRequest.sink.add(utf8.encode(body));
  initialStreamedRequest.sink.close();

  http.StreamedResponse response = await initialStreamedRequest.send();
  print("response: " + response.statusCode.toString());
  response.stream.transform(utf8.decoder).listen((value) {
    print(value);
  });

  if (response.statusCode == 200) {
    sessionUri = response.headers['location'];
    print(sessionUri);
  }

  Uri sessionURI = Uri.parse(sessionUri);
  final fileStreamedRequest = new http.StreamedRequest('PUT', sessionURI)
    ..headers.addAll({
      'Content-Length': fileLength,
      'Content-Type': 'application/json',
    });

  await for (List<int> data in file.openRead()) {
    print("DataReceived: ${data.length}");
    fileStreamedRequest.sink.add(data);
  }
  print("perpare to close");
  fileStreamedRequest.sink.close();
  print("perpare to upload");
  http.StreamedResponse fileResponse = await fileStreamedRequest.send();
  print("file response: " + fileResponse.statusCode.toString());
  fileResponse.stream.transform(utf8.decoder).listen((value) {
    print(value);
  });

  //List<int> temp = file.readAsBytesSync();

  //temp = null;
  print("seccess");

  // http.StreamedResponse fileResponse = await fileStreamedRequest.send();
  // print("file response: " + fileResponse.statusCode.toString());
  // fileResponse.stream.transform(utf8.decoder).listen((value) {
  //   print(value);
  // });
}
