const io = require('socket.io-client');

const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';

const MEETING_CODE = 'tntuzonhee'; // Existing code from user logs
const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48';
const GUEST_ID = 'guest-' + Math.random().toString(36).substring(7);

console.log(`🚀 Testing with EXISTING Meeting: ${MEETING_CODE}`);

const hostSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

hostSocket.on('connect', () => {
    console.log("🟢 HOST Connected. Emitting join-meeting...");
    // [meetingCode, userId, name, isHost, clientId]
    hostSocket.emit('join-meeting', [MEETING_CODE, HOST_ID, "Host User", true, "host_client_id"]);
});

hostSocket.on('join-confirmation', (data) => {
    console.log("📥 HOST Received join-confirmation:", JSON.stringify(data));
});

hostSocket.on('request-to-join', (data) => {
    console.log("\n🔔🔔🔔 HOST RECEIVED REQUEST TO JOIN:", JSON.stringify(data));
    const participant = Array.isArray(data) ? data[0] : data;
    console.log(`✅ Admitting ${participant.name}...`);
    hostSocket.emit('admit-user', { socketId: participant.socketId });
});

hostSocket.on('waiting-list-update', (data) => {
    console.log("📥 HOST Received waiting-list-update:", data.length, "participants waiting");
});

// Guest logic
setTimeout(() => {
    console.log(`\n🚀 Connecting GUEST (${GUEST_ID})...`);
    const guestSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

    guestSocket.on('connect', () => {
        console.log("🟢 GUEST Connected. Emitting join-meeting...");
        guestSocket.emit('join-meeting', [MEETING_CODE, GUEST_ID, "Guest User", false, "guest_client_id"]);
    });

    guestSocket.on('join-confirmation', (data) => {
        console.log("📥 GUEST Received join-confirmation:", data.status);
    });
}, 3000);

setTimeout(() => {
    console.log("\n--- Test Finished ---");
    process.exit(0);
}, 15000);
