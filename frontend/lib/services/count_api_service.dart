import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/detected_item.dart';

class CountApiService {
  static const String defaultHost = '127.0.0.1:8080';
  String host;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _countStreamController = StreamController<CountResult>.broadcast();

  Stream<CountResult> get countStream => _countStreamController.stream;

  CountApiService({this.host = defaultHost});

  void connectWebSocket({
    required Function(CountResult) onData,
    Function(dynamic)? onError,
  }) {
    disconnectWebSocket();

    try {
      final wsUrl = Uri.parse('ws://$host/ws/count');
      _channel = WebSocketChannel.connect(wsUrl);

      _subscription = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            final result = CountResult.fromJson(data);
            onData(result);
            _countStreamController.add(result);
          } catch (e) {
            // Json parse error
          }
        },
        onError: (err) {
          if (onError != null) onError(err);
        },
      );
    } catch (e) {
      if (onError != null) onError(e);
    }
  }

  void sendFrame(Uint8List jpegBytes, {double sensitivity = 0.5, String mode = 'jewelry_pin'}) {
    if (_channel != null) {
      final base64String = base64Encode(jpegBytes);
      final payload = jsonEncode({
        'image': base64String,
        'sensitivity': sensitivity,
        'mode': mode,
      });
      _channel!.sink.add(payload);
    }
  }

  void disconnectWebSocket() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  Future<CountResult> countImageBytes(
    Uint8List imageBytes, {
    double sensitivity = 0.5,
    String mode = 'jewelry_pin',
  }) async {
    try {
      final uri = Uri.parse('http://$host/api/count_base64');
      final base64String = base64Encode(imageBytes);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image': base64String,
          'sensitivity': sensitivity,
          'mode': mode,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CountResult.fromJson(data);
      }
    } catch (e) {
      // Network error
    }
    return CountResult.empty();
  }

  void dispose() {
    disconnectWebSocket();
    _countStreamController.close();
  }
}
