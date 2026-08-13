import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the on-device crash log lives — a single flat file under the app's
/// documents directory, alongside mp3_export.dart's exports/ directory.
Future<File> crashLogFile() async {
  final docs = await getApplicationDocumentsDirectory();
  return File('${docs.path}/crash_log.txt');
}
