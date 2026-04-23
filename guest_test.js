const io = require("socket.io-client");
const guestSocket = io("https://mizdah-backend.ogoul.cloud", {
  path: "/signaling-fresh",
  transports: ["websocket"]
});
guestSocket.on("connect", () => {
  console.log("Guest connected!");
  guestSocket.emit("join-meeting", "tgidlezdsq", "guest-dart-5678", "Guest Test JS", false);
});
guestSocket.onAny((e, d) => console.log(e, d));
