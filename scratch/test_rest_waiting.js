const axios = require('axios');
const io = require('socket.io-client');

const BASE_URL = 'https://mizdah-backend.ogoul.cloud';
const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';
const HOST_ID = 'host-' + Math.random().toString(36).substring(7);
const GUEST_ID = 'guest-' + Math.random().toString(36).substring(7);

async function testRestWaitingRoom() {
    console.log("🚀 Creating Meeting...");
    const code = Math.random().toString(36).substring(2, 12);
    const createRes = await axios.post(`${BASE_URL}/api/meetings/create`, {
        hostId: HOST_ID,
        title: 'REST Waiting Room Test',
        meeting_code: code,
        id: code
    });
    const meetingId = createRes.data.id; // UUID
    console.log("✅ Meeting Created. Code:", code, "UUID:", meetingId);

    console.log("\n🚀 Connecting GUEST...");
    const guestSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });
    guestSocket.on('connect', () => {
        guestSocket.emit('join-meeting', code, GUEST_ID, "Guest User", false, "guest_cli");
    });

    guestSocket.on('join-confirmation', (data) => {
        console.log("📥 GUEST Confirmation:", data.status);
    });

    await new Promise(r => setTimeout(r, 5000));

    console.log(`\n🚀 Checking Waiting Room via REST for ${code}...`);
    try {
        const waitRes = await axios.get(`${BASE_URL}/api/waiting-room/waiting/${code}`);
        console.log("📥 Waiting Room (by Code):", JSON.stringify(waitRes.data));
    } catch (e) {
        console.log("❌ Failed by Code:", e.message);
    }

    console.log(`\n🚀 Checking Waiting Room via REST for ${meetingId}...`);
    try {
        const waitRes = await axios.get(`${BASE_URL}/api/waiting-room/waiting/${meetingId}`);
        console.log("📥 Waiting Room (by UUID):", JSON.stringify(waitRes.data));
    } catch (e) {
        console.log("❌ Failed by UUID:", e.message);
    }

    process.exit(0);
}

testRestWaitingRoom();
