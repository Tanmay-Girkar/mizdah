const io = require('socket.io-client');
const axios = require('axios');

const BASE_URL = 'https://mizdah-backend.ogoul.cloud';
const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';
const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48';

async function testWithDelay() {
    const code = Math.random().toString(36).substring(2, 12);
    console.log("🚀 Creating Meeting:", code);
    
    await axios.post(`${BASE_URL}/api/meetings/create`, {
        hostId: HOST_ID,
        title: 'Delayed Join Test',
        meeting_code: code,
        id: code
    });

    console.log("⏳ Waiting 5 seconds for DB synchronization...");
    await new Promise(r => setTimeout(r, 5000));

    console.log(`🚀 Joining HOST to ${code}...`);
    const socket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

    socket.on('connect', () => {
        socket.emit('join-meeting', [code, HOST_ID, "Host User", true, "host_client_1"]);
    });

    socket.on('join-confirmation', (data) => {
        console.log("📥 Received join-confirmation:", JSON.stringify(data));
        process.exit(0);
    });

    setTimeout(() => { process.exit(1); }, 10000);
}

testWithDelay();
