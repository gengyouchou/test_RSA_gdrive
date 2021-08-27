import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as ga;
//import 'package:googleapis/vision/v1.dart';
import 'package:http/http.dart' as http;
//import 'package:path/path.dart' as path;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gdrive/RSAUtils.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'dart:io' as io;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Drive',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: MyHomePage(title: 'Google Drive'),
    );
  }
}

class GoogleHttpClient extends IOClient {
  Map<String, String> _headers;

  GoogleHttpClient(this._headers) : super();

  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) =>
      super.send(request..headers.addAll(_headers));

  @override
  Future<http.Response> head(Object url, {Map<String, String> headers}) =>
      super.head(url, headers: headers..addAll(_headers));
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);
  final String title;
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final storage = new FlutterSecureStorage();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn googleSignIn =
      GoogleSignIn(scopes: ['https://www.googleapis.com/auth/drive.appdata']);
  GoogleSignInAccount googleSignInAccount;
  ga.FileList list;
  var signedIn = false;

  Future<void> _loginWithGoogle() async {
    signedIn = await storage.read(key: "signedIn") == "true" ? true : false;
    googleSignIn.onCurrentUserChanged
        .listen((GoogleSignInAccount googleSignInAccount) async {
      if (googleSignInAccount != null) {
        _afterGoogleLogin(googleSignInAccount);
      }
    });
    if (signedIn) {
      try {
        googleSignIn.signInSilently().whenComplete(() => () {});
      } catch (e) {
        storage.write(key: "signedIn", value: "false").then((value) {
          setState(() {
            signedIn = false;
          });
        });
      }
    } else {
      final GoogleSignInAccount googleSignInAccount =
          await googleSignIn.signIn();
      _afterGoogleLogin(googleSignInAccount);
    }
  }

  Future<void> _afterGoogleLogin(GoogleSignInAccount gSA) async {
    googleSignInAccount = gSA;
    final GoogleSignInAuthentication googleSignInAuthentication =
        await googleSignInAccount.authentication;

    final AuthCredential credential = GoogleAuthProvider.getCredential(
      accessToken: googleSignInAuthentication.accessToken,
      idToken: googleSignInAuthentication.idToken,
    );

    final AuthResult authResult = await _auth.signInWithCredential(credential);
    final FirebaseUser user = authResult.user;

    assert(!user.isAnonymous);
    assert(await user.getIdToken() != null);

    final FirebaseUser currentUser = await _auth.currentUser();
    assert(user.uid == currentUser.uid);

    print('signInWithGoogle succeeded: $user');

    storage.write(key: "signedIn", value: "true").then((value) {
      setState(() {
        signedIn = true;
      });
    });
  }

  void _logoutFromGoogle() async {
    googleSignIn.signOut().then((value) {
      print("User Sign Out");
      storage.write(key: "signedIn", value: "false").then((value) {
        setState(() {
          signedIn = false;
        });
      });
    });
  }

  _uploadFileToGoogleDrive() async {
    var client = GoogleHttpClient(await googleSignInAccount.authHeaders);
    var drive = ga.DriveApi(client);
    ga.File fileToUpload = ga.File();
    //var file = await FilePicker.getFile();
    var file = await FilePicker.getDirectoryPath();
    FilePicker.clearTemporaryFiles();

    print('pick folder:$file');

    //encrypt here

    final directory = await getExternalStorageDirectory();
    //print(file.parent.path);

    final dataDir = Directory(file);
    // final files = [File(file.path)];
    //print("test0${file.parent.path}");
    //print("test1${file.path}");
    try {
      final zipFile = File(directory.path + '/money.zip');

      // await ZipFile.createFromFiles(
      //     sourceDir: dataDir, files: files, zipFile: zipFile);
      await ZipFile.createFromDirectory(
          sourceDir: dataDir, zipFile: zipFile, recurseSubDirs: true);
    } catch (e) {
      print(e);
    }

    //test

    // final zipFile = File(directory.path + '/money.zip');
    // final destinationDir = Directory(directory.path);
    // try {
    //   await ZipFile.extractToDirectory(
    //       zipFile: zipFile, destinationDir: destinationDir);
    //   print(directory.path);
    //   print(destinationDir);
    // } catch (e) {
    //   print(e);
    //   print('FUCK');
    // }

    //endtest
    RSAUtils rsa;
    if (await File(directory.path + '/pubKey.pem').exists()) {
      final File file = File(directory.path + '/pubKey.pem');
      String publicPem = await file.readAsString();
      //final File file2 = File(directory.path + '/priKey.pem');
      //String privatePem = await file2.readAsString();
      rsa = RSAUtils.getInstance(publicPem, null);
    } else {
      var list = RSAUtils.generateKeys(1024);
      rsa = RSAUtils.getInstance(list[0], list[1]);
      final File file0 = File(directory.path + '/pubKey.pem');
      await file0.writeAsString(list[0]);
      final File file2 = File(directory.path + '/priKey.pem');
      await file2.writeAsString(list[1]);
    }

    Uint8List encData = await _readData(directory.path + '/money.zip');

    var res = await rsa.encryptByPublicKey(encData);

    String pathData = await _writeData(res, directory.path + '/rsa.aes');
    print("file encrypted sucessfully: $pathData");
    print(res);
    //end encrypt

    fileToUpload.parents = ["appDataFolder"];
    fileToUpload.name = file;

    var filetoupload = File(directory.path + '/rsa.aes');
    var response = await drive.files.create(
      fileToUpload,
      uploadMedia: ga.Media(filetoupload.openRead(), filetoupload.lengthSync()),
    );
    print(response);
    _listGoogleDriveFiles();
    final dir = Directory(directory.path + '/money.zip');
    dir.deleteSync(recursive: true);
    final dir2 = Directory(directory.path + '/rsa.aes');
    dir2.deleteSync(recursive: true);
  }

  Future<String> _writeData(dataToWrite, fileNamewithPath) async {
    print("Writing Data");
    io.File f = io.File(fileNamewithPath);
    await f.writeAsBytes(dataToWrite);
    return f.absolute.toString();
  }

  Future<Uint8List> _readData(fileNamewithPath) async {
    print("Reading Data");
    io.File f = io.File(fileNamewithPath);
    return await f.readAsBytes();
  }

  Future<void> _listGoogleDriveFiles() async {
    var client = GoogleHttpClient(await googleSignInAccount.authHeaders);
    var drive = ga.DriveApi(client);
    drive.files.list(spaces: 'appDataFolder').then((value) {
      setState(() {
        list = value;
      });
      for (var i = 0; i < list.files.length; i++) {
        print("Id: ${list.files[i].id} File Name:${list.files[i].name}");
      }
    });
  }

  Future<String> _downloadGoogleDriveFile(String fName, String gdID) async {
    var client = GoogleHttpClient(await googleSignInAccount.authHeaders);
    var drive = ga.DriveApi(client);
    ga.Media file = await drive.files
        .get(gdID, downloadOptions: ga.DownloadOptions.FullMedia);
    print(file.stream);

    final directory = await getExternalStorageDirectory();
    print(directory.path);
    final saveFile = File('${directory.path}/A');
    List<int> dataStore = [];
    await for (List<int> data in file.stream) {
      print("DataReceived: ${data.length}");
      dataStore.insertAll(dataStore.length, data);
    }

    await saveFile.writeAsBytes(dataStore);

    // // print("File saved at ${saveFile.path}");
    // file.stream.listen((data) {
    //   print("DataReceived: ${data.length}");
    //   dataStore.insertAll(dataStore.length, data);
    // }, onDone: () {
    //   print("Task Done");
    //   saveFile.writeAsBytes(dataStore);
    //   print("File saved at ${saveFile.path}");
    // }, onError: (error) {
    //   print("Some Error");
    // });

    return saveFile.path;
  }

  Future<void> downloadAndDecrypt(String fName, String gdID) async {
    final directory = await getExternalStorageDirectory();
    String saveFilePath = await _downloadGoogleDriveFile(fName, gdID);
//decrypt here

    Uint8List encData = await _readData(saveFilePath);
    print(saveFilePath);
    final File file0 = File(directory.path + '/pubKey.pem');
    String publicPem = await file0.readAsString();
    final File file2 = File(directory.path + '/priKey.pem');
    String privatePem = await file2.readAsString();
    //print(privatePem);
    var D = RSAUtils.getInstance(publicPem, privatePem);
    var res = D.decryptByPrivateKey(encData);
    print(encData);
    print(res);

    //print(utf8.decode(res));
    //var plainData = await _encryptData(encData);
    //String plainData = String.fromCharCodes(res);
    // final File file3 = File(d.path + '/tempurl.txt');
    // String url = await file3.readAsString();
    //await Directory(url).create(recursive: true);
    String pathData = await _writeData(res, directory.path + '/money.zip');
    print("file decrypted sucessfully: $pathData");

    final zipFile = File(directory.path + '/money.zip');
    final destinationDir = Directory(directory.path);
    try {
      await ZipFile.extractToDirectory(
          zipFile: zipFile, destinationDir: destinationDir);
      //print(directory.path);
      //print(destinationDir);
    } catch (e) {
      print(e);
      print('FUCK');
    }
    final dir = Directory(saveFilePath);
    dir.deleteSync(recursive: true);
    final dir2 = Directory(directory.path + '/money.zip');
    dir2.deleteSync(recursive: true);
    //end decrypt
  }

  Future<void> _deleteGoogleDriveFile(String fName, String gdID) async {
    var client = GoogleHttpClient(await googleSignInAccount.authHeaders);
    var drive = ga.DriveApi(client);
    await drive.files.delete(gdID);
    _listGoogleDriveFiles();
  }

  List<Widget> generateFilesWidget() {
    List<Widget> listItem = List<Widget>();
    if (list != null) {
      for (var i = 0; i < list.files.length; i++) {
        listItem.add(Row(
          children: <Widget>[
            Container(
              width: MediaQuery.of(context).size.width * 0.05,
              child: Text('${i + 1}'),
            ),
            Expanded(
              child: Text(list.files[i].name),
            ),
            Container(
              width: MediaQuery.of(context).size.width * 0.3,
              child: FlatButton(
                child: Text(
                  'Download',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
                color: Colors.indigo,
                onPressed: () {
                  downloadAndDecrypt(list.files[i].name, list.files[i].id);
                },
              ),
            ),
            Container(
              width: MediaQuery.of(context).size.width * 0.2,
              child: FlatButton(
                child: Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.green,
                  ),
                ),
                color: Colors.indigo,
                onPressed: () {
                  _deleteGoogleDriveFile(list.files[i].name, list.files[i].id);
                },
              ),
            ),
          ],
        ));
      }
    }
    return listItem;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            (signedIn
                ? FlatButton(
                    child: Text('Upload File to Google Drive'),
                    onPressed: _uploadFileToGoogleDrive,
                    color: Colors.green,
                  )
                : Container()),
            (signedIn
                ? FlatButton(
                    child: Text('List Google Drive Files'),
                    onPressed: _listGoogleDriveFiles,
                    color: Colors.green,
                  )
                : Container()),
            (signedIn
                ? Expanded(
                    flex: 10,
                    child: Column(
                      children: generateFilesWidget(),
                    ),
                  )
                : Container()),
            (signedIn
                ? FlatButton(
                    child: Text('Google Logout'),
                    onPressed: _logoutFromGoogle,
                    color: Colors.green,
                  )
                : FlatButton(
                    child: Text('Google Login'),
                    onPressed: _loginWithGoogle,
                    color: Colors.red,
                  )),
          ],
        ),
      ),
    );
  }
}
