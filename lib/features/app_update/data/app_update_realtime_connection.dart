import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class AppUpdateRealtimeConnection {
  Future<void> get ready;
  Stream<dynamic> get stream;
  Future<void> close();
}

typedef AppUpdateRealtimeConnector =
    AppUpdateRealtimeConnection Function(Uri uri);

class WebSocketAppUpdateRealtimeConnection
    implements AppUpdateRealtimeConnection {
  WebSocketAppUpdateRealtimeConnection._(this._channel);

  factory WebSocketAppUpdateRealtimeConnection.connect(Uri uri) {
    return WebSocketAppUpdateRealtimeConnection._(
      WebSocketChannel.connect(uri),
    );
  }

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}
