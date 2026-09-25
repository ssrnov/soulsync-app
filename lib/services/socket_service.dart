import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  IO.Socket? socket;
  final ApiService _apiService = ApiService();
  bool isConnected = false;

  // Listeners callbacks maps
  final Map<String, List<Function(dynamic)>> _listeners = {};

  SocketService._internal();

  Future<void> init() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) return;

      final socketUrl = dotenv.env['SOCKET_URL'] ?? 'https://soulsyncc.site/soulsync-system';

      socket = IO.io(socketUrl, IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setExtraHeaders({'Authorization': 'Bearer $token'})
        .build());

      socket!.onConnect((_) {
        print('Socket connected successfully!');
        isConnected = true;
        _triggerCallback('connect', null);
      });

      socket!.onDisconnect((_) {
        print('Socket disconnected');
        isConnected = false;
        _triggerCallback('disconnect', null);
      });

      socket!.onConnectError((err) => print('Socket Connect Error: $err'));
      socket!.onError((err) => print('Socket Error: $err'));

      // Bind common listeners
      _bindSocketEvents();

      socket!.connect();
    } catch (e) {
      print("Socket init failed (non-fatal): $e");
      socket = null;
      isConnected = false;
    }
  }

  void disconnect() {
    socket?.disconnect();
    socket = null;
    isConnected = false;
  }

  // Register Event Listener
  void on(String event, Function(dynamic) callback) {
    if (!_listeners.containsKey(event)) {
      _listeners[event] = [];
    }
    _listeners[event]!.add(callback);
  }

  // Remove Event Listener
  void off(String event, Function(dynamic) callback) {
    if (_listeners.containsKey(event)) {
      _listeners[event]!.remove(callback);
    }
  }

  // Emit event helper
  void emit(String event, dynamic data) {
    if (socket != null && isConnected) {
      socket!.emit(event, data);
    }
  }

  // Private bindings
  void _bindSocketEvents() {
    final events = [
      'message:new',
      'message:delivered',
      'message:typing',
      'messages:read',
      'message:reaction',
      'touch:received',
      'touch:sent',
      'heartbeat:pulse',
      'call:offer',
      'call:answer',
      'call:ice-candidate',
      'call:rejected',
      'call:ended',
      'call:busy',
      'game:started',
      'game:answer',
      'game:round-complete',
      'game:next-round',
      'game:ended'
    ];

    for (var event in events) {
      socket!.on(event, (data) {
        _triggerCallback(event, data);
      });
    }
  }

  void _triggerCallback(String event, dynamic data) {
    if (_listeners.containsKey(event)) {
      for (var callback in _listeners[event]!) {
        callback(data);
      }
    }
  }
}
