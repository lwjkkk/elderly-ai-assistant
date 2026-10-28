import 'voice_temp_cleanup_stub.dart'
    if (dart.library.io) 'voice_temp_cleanup_io.dart'
    if (dart.library.html) 'voice_temp_cleanup_web.dart' as platform;

Future<void> removeVoiceTemporaryFile(String path) =>
    platform.removeVoiceTemporaryFile(path);
