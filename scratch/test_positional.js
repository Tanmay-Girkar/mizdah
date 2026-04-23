const io = require('socket.io-client');
const axios = require('axios');

const BASE_URL = 'https://mizdah-backend.ogoul.cloud';
const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';
const HOST_ID = 'host-user-' + Math.random().toString(36).substring(7);
const GUEST_ID = 'guest-user-' + Math.random().toString(36).substring(7);

async function testFullFlow() {
    const code = 'test' + Math.random().toString(36).substring(7);
    console.log("🚀 Creating Meeting:", code);
    await axios.post(`${BASE_URL}/api/meetings/create`, {
        hostId: HOST_ID,
        title: 'Full Flow Test',
        meeting_code: code,
        id: code
    });

    console.log("\n🚀 1. Connecting HOST...");
    const hostSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });
    let hostSocketId;

    hostSocket.on('connect', () => {
        // Emit as separate arguments
        hostSocket.emit('join-meeting', code, HOST_ID, "The Host", true, "host_cli");
    });

    hostSocket.on('join-confirmation', (data) => {
        console.log("📥 HOST Joined:", data.status);
    });

    hostSocket.on('request-to-join', (data) => {
        console.log("\n🔔🔔🔔 HOST RECEIVED REQUEST TO JOIN:", JSON.stringify(data));
        const participant = Array.isArray(data) ? data[0] : data;
        console.log(`✅ Admitting ${participant.name} (${participant.socketId})...`);
        hostSocket.emit('admit-user', { socketId: participant.socketId });
    });

    await new Promise(r => setTimeout(r, 2000));

    console.log("\n🚀 2. Connecting GUEST...");
    const guestSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

    guestSocket.on('connect', () => {
        guestSocket.emit('join-meeting', code, GUEST_ID, "Guest User", false, "guest_cli");
    });

    guestSocket.on('join-confirmation', (data) => {
        console.log("📥 GUEST Confirmation:", data.status);
    });

    guestSocket.on('waiting-list-update', (data) => {
        console.log("📥 GUEST/HOST waiting-list-update:", data.length);
    });

    setTimeout(() => {
        console.log("\nTest complete.");
        process.exit(0);
    }, 10000);
}

testFullFlow();
