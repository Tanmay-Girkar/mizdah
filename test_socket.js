const io = require("socket.io-client");

const meetingCode = "tgi-dlez-dsq"; // The user's recent meeting code
const hostUserId = "a7bae225-5f5a-40b6-b177-36cf1c0d3e48"; // The host's user ID

const hostSocket = io("https://mizdah-backend.ogoul.cloud", {
  path: "/signaling-fresh",
  transports: ["websocket"]
});

hostSocket.on("connect", () => {
  console.log("Host connected!");
  // Host joining
  // Try passing [code, userId, name, isCameraOff]
  hostSocket.emit("join-meeting", meetingCode, hostUserId, "Host Test", false);
});

hostSocket.on("waiting-list-update", (data) => {
  console.log("HOST RECEIVED waiting-list-update:", data);
});

hostSocket.onAny((event, ...args) => {
  console.log(`HOST EVENT: ${event}`, args);
});

setTimeout(() => {
  const guestSocket = io("https://mizdah-backend.ogoul.cloud", {
    path: "/signaling-fresh",
    transports: ["websocket"]
  });

  guestSocket.on("connect", () => {
    console.log("Guest connected!");
    guestSocket.emit("join-meeting", meetingCode, "guest-1234", "Guest Test", false);
  });

  guestSocket.onAny((event, ...args) => {
    console.log(`GUEST EVENT: ${event}`, args);
  });
}, 2000);

setTimeout(() => {
  console.log("Done testing");
  process.exit(0);
}, 6000);
