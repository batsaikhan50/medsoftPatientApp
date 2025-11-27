import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC7RPZq8xAQ8VpEoQvux6NKQU_vaC6x4Dc',
    appId: '1:460803212457:android:bd37af72339e54e8bb15b8',
    messagingSenderId: '460803212457',
    projectId: 'medsoft-patient-push-noti',
    storageBucket: 'medsoft-patient-push-noti.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBuAXDfYXPITpeSiKFY1rmqAWw9piWajyI',
    appId: '1:460803212457:ios:f1b7a2a4302483c6bb15b8',
    messagingSenderId: '460803212457',
    projectId: 'medsoft-patient-push-noti',
    storageBucket: 'medsoft-patient-push-noti.firebasestorage.app',
    iosBundleId: 'com.batsaikhan.medsoftPatient',
  );
}
