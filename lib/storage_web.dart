import 'package:shared_preferences/shared_preferences.dart';

const _key = 'kafelito_data';

Future<String?> loadData() async => (await SharedPreferences.getInstance()).getString(_key);

Future<void> saveData(String json) async => (await SharedPreferences.getInstance()).setString(_key, json);
