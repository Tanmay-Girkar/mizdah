import 'package:socket_io_client/socket_io_client.dart' as io;

void main() async {
  print("Connecting to socket...");
  final socket = io.io("https://mizdah-backend.ogoul.cloud", 
    io.OptionBuilder()
      .setTransports(['websocket'])
      .setPath('/signaling-fresh')
      .build()
  );

  socket.onConnect((_) {
    print("Host Connected!");
    socket.emit('join-meeting', ["tgidlezdsq", "a7bae225-5f5a-40b6-b177-36cf1c0d3e48", "Host Dart", true, "client_dart"]);
  });

  socket.on('request-to-join', (data) {
    print(">>> HOST GOT REQUEST TO JOIN: $data");
  });

  socket.on('join-confirmation', (data) {
    print("Host Received join-confirmation: $data");
  });

  socket.onAny((event, data) {
    print("EVENT: $event, DATA: $data");
  });

  await Future.delayed(Duration(seconds: 120));
  print("Done");
}

