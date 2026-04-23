const io = require('socket.io-client');
const axios = require('axios');

const BASE_URL = 'https://mizdah-backend.ogoul.cloud';
const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';

const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48'; // Use user's ID from logs
const GUEST_ID = 'guest-uuid-123';

async function testFullFlow() {
    console.log("🚀 1. Creating Meeting via REST...");
    const meetingCode = 'test' + Math.random().toString(36).substring(7);
    
    try {
        const createRes = await axios.post(`${BASE_URL}/api/meetings/create`, {
            hostId: HOST_ID,
            title: 'Test Integration Meeting',
            meeting_code: meetingCode,
            id: meetingCode
        });
        console.log("✅ Meeting Created:", createRes.data.meeting_code || meetingCode);
    } catch (e) {
        console.log("❌ Create Failed (might already exist):", e.message);
    }

    const code = meetingCode;

    console.log(`\n🚀 2. Connecting HOST (${HOST_ID}) to socket...`);
    const hostSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

    hostSocket.on('connect', () => {
        console.log("🟢 HOST Connected. Emitting join-meeting...");
        hostSocket.emit('join-meeting', [code, HOST_ID, "Host User", true, "host_client_id"]);
    });

    hostSocket.on('join-confirmation', (data) => {
        console.log("📥 HOST Received join-confirmation:", data.status);
    });

    hostSocket.on('request-to-join', (data) => {
        console.log("\n🔔🔔🔔 HOST RECEIVED REQUEST TO JOIN:", JSON.stringify(data));
        const participant = Array.isArray(data) ? data[0] : data;
        const guestSocketId = participant.socketId;
        
        console.log(`\n🚀 4. HOST admitting GUEST (${guestSocketId})...`);
        hostSocket.emit('admit-user', { socketId: guestSocketId });
    });

    // Wait for Host to be ready
    await new Promise(r => setTimeout(r, 2000));

    console.log(`\n🚀 3. Connecting GUEST (${GUEST_ID}) to socket...`);
    const guestSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

    guestSocket.on('connect', () => {
        console.log("🟢 GUEST Connected. Emitting join-meeting...");
        guestSocket.emit('join-meeting', [code, GUEST_ID, "Guest User", false, "guest_client_id"]);
    });

    guestSocket.on('join-confirmation', (data) => {
        console.log("📥 GUEST Received join-confirmation:", data.status);
        if (data.status === 'WAITING_FOR_APPROVAL' || data.status === 'WAITING') {
            console.log("⏳ GUEST is in Waiting Room as expected.");
        } else if (data.status === 'JOINED') {
            console.log("✅ GUEST has JOINED successfully!");
            process.exit(0);
        }
    });

    setTimeout(() => {
        console.log("\n❌ Timeout: Guest never joined.");
        process.exit(1);
    }, 15000);
}

testFullFlow();
