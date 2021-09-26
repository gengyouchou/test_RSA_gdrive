//import 'dart:ffi';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart'; //as signIn;
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
import 'package:flutter_gdrive/uploadfile.dart';

//import 'package:percent_indicator/percent_indicator.dart';
//import 'package:permission_handler/permission_handler.dart';

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
  final GoogleSignIn googleSignIn = GoogleSignIn.standard(scopes: [
    ga.DriveApi.driveFileScope
  ] /*['https://www.googleapis.com/auth/drive.appdata']*/);
  //final signIn.GoogleSignIn.standard(scopes: [drive.DriveApi.DriveScope]);
  GoogleSignInAccount googleSignInAccount;
  ga.FileList list;
  var signedIn = false;

  //final signIn.GoogleSignInAccount account = await googleSignIn.signIn();

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

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleSignInAuthentication.accessToken,
      idToken: googleSignInAuthentication.idToken,
    );

    final UserCredential authResult =
        await _auth.signInWithCredential(credential);
    final User user = authResult.user;

    assert(!user.isAnonymous);
    assert(await user.getIdToken() != null);

    final User currentUser = _auth.currentUser;
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
    ga.File fileToUpload = ga.File();

    var file = await FilePicker.getDirectoryPath();
    FilePicker.clearTemporaryFiles();
    //encrypt here
    final directory = await getExternalStorageDirectory();
    final dataDir = Directory(file);
    try {
      final zipFile = File(directory.path + '/money.zip');
      // await ZipFile.createFromFiles(
      //     sourceDir: dataDir, files: files, zipFile: zipFile);
      await ZipFile.createFromDirectory(
          sourceDir: dataDir, zipFile: zipFile, recurseSubDirs: true);
    } catch (e) {
      print(e);
    }
    RSAUtils rsa;
    if (await File(directory.path + '/pubKey.pem').exists()) {
      final File file = File(directory.path + '/pubKey.pem');
      String publicPem = await file.readAsString();
      rsa = RSAUtils.getInstance(publicPem, null);
    } else {
      var list = RSAUtils.generateKeys(1024);
      rsa = RSAUtils.getInstance(list[0], list[1]);
      final File file0 = File(directory.path + '/pubKey.pem');
      await file0.writeAsString(list[0]);
      final File file2 = File(directory.path + '/priKey.pem');
      await file2.writeAsString(list[1]);
    }

    final f = new io.File(directory.path + '/money.zip');
    List<int> res2 = [];
    await for (List<int> encData in f.openRead()) {
      res2.insertAll(res2.length, encData);
    }
    Uint8List res = Uint8List.fromList(res2);
    res2 = null;
    print("encrypt:${res.length}");
    res = rsa.encryptByPublicKey(res);

    rsa = null;
    //encData = null;

    print("res len: ${res.length}");

    final saveFile = new io.File(directory.path + '/rsa.aes');
    saveFile.writeAsBytesSync(res, mode: FileMode.append, flush: true);
    res = null;
    print("finish write");
    fileToUpload.name = file;
    await handleUploadData(
        client._headers, fileToUpload.name, directory.path + '/rsa.aes');
    print("finish upload");

    _listGoogleDriveFiles();
    final dir = Directory(directory.path + '/money.zip');
    dir.deleteSync(recursive: true);
    final dir2 = Directory(directory.path + '/rsa.aes');
    dir2.deleteSync(recursive: true);

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: Container(
              height: MediaQuery.of(context).size.height / 2,
              child: Card(
                child: Column(
                  children: [
                    Text(
                      "encryption successfull.Check at ${directory.path} You must store the private key(priKey.pem) in a safe place and put it back when you need to decrypt it\n Press Ok to continue",
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 20,
                        color: Colors.black,
                      ),
                    ),
                    RaisedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        "ok",
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
  }

  // Future<String> _writeData(dataToWrite, fileNamewithPath) async {
  //   print("Writing Data");
  //   io.File f = new io.File(fileNamewithPath);
  //   print("Writing Data2");
  //   await f.writeAsBytes(dataToWrite);
  //   print("Writing Data3");
  //   return ""; //f.absolute.toString();
  // }

  // Future<Uint8List> _readData(fileNamewithPath) async {
  //   print("Reading Data");
  //   io.File f = new io.File(fileNamewithPath);
  //   return await f.readAsBytes();
  // }

  Future<void> _listGoogleDriveFiles() async {
    var client = GoogleHttpClient(await googleSignInAccount.authHeaders);
    var drive = ga.DriveApi(client);
    drive.files.list(/*spaces: 'appDataFolder'*/).then((value) {
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
        .get(gdID, downloadOptions: ga.DownloadOptions.fullMedia);

    final directory = await getExternalStorageDirectory();
    print(directory.path);
    final saveFile = File('${directory.path}/A');
    List<int> dataStore = [];
    await for (List<int> data in file.stream) {
      dataStore.insertAll(dataStore.length, data);
    }
    print("encrypt:${dataStore.length}");
    saveFile.writeAsBytesSync(dataStore, flush: true);
    print("finish download");
    return saveFile.path;
  }

  Future<void> downloadAndDecrypt(String fName, String gdID) async {
    String saveFilePath = await _downloadGoogleDriveFile(fName, gdID);
//decrypt here
    final directory = await getExternalStorageDirectory();
    final File file0 = File(directory.path + '/pubKey.pem');
    String publicPem = await file0.readAsString();
    final File file2 = File(directory.path + '/priKey.pem');
    String privatePem = await file2.readAsString();
    final saveFile = new io.File(saveFilePath);

    List<int> res2 = [];
    await for (List<int> encData in saveFile.openRead()) {
      print("DataReceived: ${encData.length}");
      res2.insertAll(res2.length, encData);
    }

    var D = RSAUtils.getInstance(publicPem, privatePem);
    print("fromU8list:${res2.length}");
    Uint8List res = Uint8List.fromList(res2);
    print("decrypt:${res.length}");
    res2 = null;
    res = D.decryptByPrivateKey(res);
    D = null;
    print("res len:${res.length}");
    final wFile = new io.File(directory.path + '/money.zip');
    wFile.writeAsBytesSync(res, mode: FileMode.append, flush: true);
    res = null;
    final zipFile = File(directory.path + '/money.zip');
    final destinationDir = Directory(directory.path);
    try {
      await ZipFile.extractToDirectory(
          zipFile: zipFile, destinationDir: destinationDir);
    } catch (e) {
      print(e);
      print('FUCK');
    }
    final dir = Directory(saveFilePath);
    dir.deleteSync(recursive: true);
    final dir2 = Directory(directory.path + '/money.zip');
    dir2.deleteSync(recursive: true);
    //end decrypt

    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: Container(
              height: MediaQuery.of(context).size.height / 2,
              child: Card(
                child: Column(
                  children: [
                    Text(
                      "decryption successfull.Check at ${directory.path}\n Press Ok to continue",
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 20,
                        color: Colors.black,
                      ),
                    ),
                    RaisedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        "ok",
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
  }

  Future<void> _deleteGoogleDriveFile(String fName, String gdID) async {
    var client = GoogleHttpClient(await googleSignInAccount.authHeaders);
    var drive = ga.DriveApi(client);
    await drive.files.delete(gdID);
    _listGoogleDriveFiles();
  }

  List<Widget> generateFilesWidget() {
    List<Widget> listItem = [];
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
                    color: Colors.blue,
                  )
                : FlatButton(
                    child: Text('Start encrypting'),
                    onPressed: _loginWithGoogle,
                    color: Colors.green,
                  )),
          ],
        ),
      ),
    );
  }
}
