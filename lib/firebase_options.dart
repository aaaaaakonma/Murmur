import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase options with environment variable support for Vercel / CI deployments.
/// Falls back to default Murmur project credentials if environment variables are omitted.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyAQ8H2xvOPPkNEOmnXgeT6Am0H5H5VC98M'),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:493907665220:web:4e4332d643448b512e7711'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '493907665220'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'murmur-b7430'),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN', defaultValue: 'murmur-b7430.firebaseapp.com'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: 'murmur-b7430.firebasestorage.app'),
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyBO4G_xZwmZTTV4S7CViW4PT3DtNUHgSOQ'),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:493907665220:android:1a3090457b49ecff2e7711'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '493907665220'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'murmur-b7430'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: 'murmur-b7430.firebasestorage.app'),
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyAQ8H2xvOPPkNEOmnXgeT6Am0H5H5VC98M'),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:493907665220:web:4e4332d643448b512e7711'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '493907665220'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'murmur-b7430'),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN', defaultValue: 'murmur-b7430.firebaseapp.com'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: 'murmur-b7430.firebasestorage.app'),
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyAQ8H2xvOPPkNEOmnXgeT6Am0H5H5VC98M'),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:493907665220:ios:4e4332d643448b512e7711'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '493907665220'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'murmur-b7430'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: 'murmur-b7430.firebasestorage.app'),
  );
}
