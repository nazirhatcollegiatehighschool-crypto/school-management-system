class Config {
  static const String _defined = String.fromEnvironment('API_URL', defaultValue: 'https://school-system-api.vercel.app');
  static const String serverUrl = _defined;
  static const String api = '$serverUrl/api';
}