import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

final googleSignIn = new GoogleSignIn();
final analytics = new FirebaseAnalytics();
final auth = FirebaseAuth.instance;
var currentUserEmail;
var _scaffoldContext;

void main() => runApp(new FlutterChatApp());

class FlutterChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: "Flutter Chat App",
      theme: defaultTargetPlatform == TargetPlatform.iOS ? kIOSTheme : kDefaultTheme,
      home: new ChatScreen(),
    );
  }
}

final ThemeData kIOSTheme = new ThemeData(
  primarySwatch: Colors.blue,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.blue,
  accentColor: Colors.blue[400],
);

class ChatScreen extends StatefulWidget {
  @override
  ChatScreenState createState() {
    return new ChatScreenState();
  }
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textEditingController =
      new TextEditingController();
  bool _isComposingMessage = false;
  final reference = FirebaseDatabase.instance.reference().child('messages');

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: new AppBar(
          title: new Text("Flutter Chat App"),
          actions: <Widget>[
            new IconButton(
                icon: new Icon(Icons.exit_to_app), onPressed: _signOut)
          ],
        ),
        body: new Column(
          children: <Widget>[
            new Flexible(
              child: new FirebaseAnimatedList(
                query: reference,
                padding: const EdgeInsets.all(8.0),
                reverse: true,
                sort: (a, b) => b.key.compareTo(a.key),
                //comparing timestamp of messages to check which one would appear first
                itemBuilder: (_, DataSnapshot messageSnapshot,
                    Animation<double> animation) {
                  return new ChatMessage(
                    messageSnapshot: messageSnapshot,
                    animation: animation,
                  );
                },
              ),
            ),
            new Divider(height: 1.0),
            new Container(
              decoration: new BoxDecoration(color: Theme.of(context).cardColor),
              child: _buildTextComposer(),
            ),
            new Builder(builder: (BuildContext context) {
              _scaffoldContext = context;
              return new Container(width: 0.0, height: 0.0);
            })
          ],
        ));
  }

  Widget _buildTextComposer() {
    return new IconTheme(
        data: new IconThemeData(
          color: _isComposingMessage
              ? Theme.of(context).accentColor
              : Theme.of(context).disabledColor,
        ),
        child: new Container(
            margin: const EdgeInsets.symmetric(horizontal: 8.0),
            child: new Row(
              children: <Widget>[
                new Container(
                  margin: new EdgeInsets.symmetric(horizontal: 4.0),
                  child: new IconButton(
                      icon: new Icon(
                        Icons.photo_camera,
                        color: Theme.of(context).accentColor,
                      ),
                      onPressed: () async {
                        await _ensureLoggedIn();
                        File imageFile = await ImagePicker.pickImage();
                        int timestamp =
                            new DateTime.now().millisecondsSinceEpoch;
                        StorageReference storageReference = FirebaseStorage
                            .instance
                            .ref()
                            .child("img_" + timestamp.toString() + ".jpg");
                        StorageUploadTask uploadTask =
                            storageReference.put(imageFile);
                        Uri downloadUrl = (await uploadTask.future).downloadUrl;
                        _sendMessage(
                            messageText: null,
                            imageUrl: downloadUrl.toString());
                      }),
                ),
                new Flexible(
                  child: new TextField(
                    controller: _textEditingController,
                    onChanged: (String messageText) {
                      setState(() {
                        _isComposingMessage = messageText.length > 0;
                      });
                    },
                    onSubmitted: _textMessageSubmitted,
                    decoration: new InputDecoration.collapsed(
                        hintText: "Send a message"),
                  ),
                ),
                new Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: new IconButton(
                    icon: new Icon(Icons.send),
                    onPressed: () => _isComposingMessage
                        ? _textMessageSubmitted(_textEditingController.text)
                        : null,
                  ),
                )
              ],
            )));
  }

  Future<Null> _textMessageSubmitted(String text) async {
    _textEditingController.clear();

    setState(() {
      _isComposingMessage = false;
    });

    await _ensureLoggedIn();
    _sendMessage(messageText: text, imageUrl: null);
  }

  void _sendMessage({String messageText, String imageUrl}) {
    reference.push().set({
      'text': messageText,
      'email': googleSignIn.currentUser.email,
      'imageUrl': imageUrl,
      'senderName': googleSignIn.currentUser.displayName,
      'senderPhotoUrl': googleSignIn.currentUser.photoUrl,
    });

    analytics.logEvent(name: 'send_message');
  }

  Future<Null> _ensureLoggedIn() async {
    GoogleSignInAccount signedInUser = googleSignIn.currentUser;
    if (signedInUser == null)
      signedInUser = await googleSignIn.signInSilently();
    if (signedInUser == null) {
      await googleSignIn.signIn();
      analytics.logLogin();
    }

    currentUserEmail = googleSignIn.currentUser.email;

    if (await auth.currentUser() == null) {
      GoogleSignInAuthentication credentials =
          await googleSignIn.currentUser.authentication;
      await auth.signInWithGoogle(
          idToken: credentials.idToken, accessToken: credentials.accessToken);
    }
  }

  Future _signOut() async {
    await auth.signOut();
    googleSignIn.signOut();
    Scaffold
        .of(_scaffoldContext)
        .showSnackBar(new SnackBar(content: new Text('User logged out')));
  }
}

class ChatMessage extends StatelessWidget {
  final DataSnapshot messageSnapshot;
  final Animation animation;

  ChatMessage({this.messageSnapshot, this.animation});

  @override
  Widget build(BuildContext context) {
    return new SizeTransition(
      sizeFactor:
          new CurvedAnimation(parent: animation, curve: Curves.decelerate),
      child: new Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: new Row(
          children: currentUserEmail == messageSnapshot.value['email']
              ? getSentMessageLayout()
              : getReceivedMessageLayout(),
        ),
      ),
    );
  }

  List<Widget> getSentMessageLayout() {
    return <Widget>[
      new Expanded(
        child: new Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            new Text(messageSnapshot.value['senderName'],
                style: new TextStyle(
                    fontSize: 14.0,
                    color: Colors.black,
                    fontWeight: FontWeight.bold)),
            new Container(
              margin: const EdgeInsets.only(top: 5.0),
              child: messageSnapshot.value['imageUrl'] != null
                  ? new Image.network(
                      messageSnapshot.value['imageUrl'],
                      width: 250.0,
                    )
                  : new Text(messageSnapshot.value['text']),
            ),
          ],
        ),
      ),
      new Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          new Container(
              margin: const EdgeInsets.only(left: 8.0),
              child: new CircleAvatar(
                backgroundImage:
                    new NetworkImage(messageSnapshot.value['senderPhotoUrl']),
              )),
        ],
      ),
    ];
  }

  List<Widget> getReceivedMessageLayout() {
    return <Widget>[
      new Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          new Container(
              margin: const EdgeInsets.only(right: 8.0),
              child: new CircleAvatar(
                backgroundImage:
                    new NetworkImage(messageSnapshot.value['senderPhotoUrl']),
              )),
        ],
      ),
      new Expanded(
        child: new Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            new Text(messageSnapshot.value['senderName'],
                style: new TextStyle(
                    fontSize: 14.0,
                    color: Colors.black,
                    fontWeight: FontWeight.bold)),
            new Container(
              margin: const EdgeInsets.only(top: 5.0),
              child: messageSnapshot.value['imageUrl'] != null
                  ? new Image.network(
                      messageSnapshot.value['imageUrl'],
                      width: 250.0,
                    )
                  : new Text(messageSnapshot.value['text']),
            ),
          ],
        ),
      ),
    ];
  }
}
