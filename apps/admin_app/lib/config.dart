class Config {
  static const String _defined = String.fromEnvironment('API_URL', defaultValue: 'https://nazirhatcollegiatehighschool-2397.vercel.app');
  static const String serverUrl = _defined;
  static const String api = '$serverUrl/api';
}