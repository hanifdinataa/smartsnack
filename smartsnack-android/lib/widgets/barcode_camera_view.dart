export 'barcode_camera_view_stub.dart'
    if (dart.library.io) 'barcode_camera_view_mobile.dart'
    if (dart.library.html) 'barcode_camera_view_web.dart';
