import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/kafelito.json');
}

Future<String?> loadData() async {
  final f = await _file();
  return await f.exists() ? f.readAsString() : null;
}

Future<void> saveData(String json) async {
  final f = await _file();
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(json, flush: true);
  await tmp.rename(f.path);
}
