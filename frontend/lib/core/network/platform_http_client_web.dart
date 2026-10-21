import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client platformHttpClient({required bool credentials}) =>
    BrowserClient()..withCredentials = credentials;
