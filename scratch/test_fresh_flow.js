const io = require('socket.io-client');
const axios = require('axios');

const BASE_URL = 'https://mizdah-backend.ogoul.cloud';
const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';
const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48';

async function testFreshFlow() {
    console.log("🚀 1. Creating FRESH Meeting...");
    // The app uses 10 random chars
    const code = Math.random().toString(36).substring(2, 12);
    
    try {
        const createRes = await axios.post(`${BASE_URL}/api/meetings/create`, {
            hostId: HOST_ID,
            title: 'Fresh Integration Test',
            meeting_code: code,
            id: code
        });
        console.log("✅ Meeting Created. Code:", code);
        console.log("Response Data:", JSON.stringify(createRes.data));
    } catch (e) {
        console.log("❌ Create Failed:", e.response ? JSON.stringify(e.response.data) : e.message);
        process.exit(1);
    }

    console.log(`\n🚀 2. Joining HOST to ${code}...`);
    const socket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

    socket.on('connect', () => {
        console.log("🟢 Connected. Emitting join-meeting...");
        socket.emit('join-meeting', [code, HOST_ID, "Host User", true, "host_client_1"]);
    });

    socket.on('join-confirmation', (data) => {
        console.log("📥 Received join-confirmation:", JSON.stringify(data));
        if (data.status === 'JOINED' && data.isHost) {
            console.log("✅ SUCCESS: Host joined successfully!");
        } else {
            console.log("❌ FAILED: Host could not join correctly.");
        }
        process.exit(0);
    });

    socket.onAny((event, data) => {
        console.log(`📡 EVENT: ${event} | DATA:`, JSON.stringify(data));
    });

    setTimeout(() => {
        console.log("🕒 Timeout.");
        process.exit(1);
    }, 10000);
}

testFreshFlow();
