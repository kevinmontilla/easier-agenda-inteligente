// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions have not been configured for this platform yet.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCugnc_BYCoZ2EQXPKbyYJDWH_Ovvu-EY4',
    appId: '1:169055342670:web:8616598e957a2ea89d331f',
    messagingSenderId: '169055342670',
    projectId: 'easier-agenda',
    authDomain: 'easier-agenda.firebaseapp.com',
    storageBucket: 'easier-agenda.firebasestorage.app',
    measurementId: 'G-FRNZRTCS3S',
  );
}