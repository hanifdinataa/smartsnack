export 'camera_capture_view_stub.dart'
    if (dart.library.io) 'camera_capture_view_mobile.dart'
    if (dart.library.html) 'camera_capture_view_web.dart';
