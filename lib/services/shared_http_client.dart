import 'package:http/http.dart' as http;

/// #553: one HTTP client for the whole app, reused by the services that
/// aren't handed one (tests inject theirs). A client created per call and
/// never closed kept its sockets open until garbage collection; a shared
/// one also reuses connections to the same hosts (OSM, Wikipedia).
final http.Client sharedHttpClient = http.Client();
