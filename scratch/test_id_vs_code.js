const io = require('socket.io-client');

const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';

// From user logs
const MEETING_UUID = '2e365ec6-e9a1-4c84-9bbb-ed566bb6ad07';
const MEETING_CODE = 'tntuzonhee';
const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48';

async function testWith(idOrCode) {
    console.log(`\n🚀 Testing with: ${idOrCode}`);
    return new Promise((resolve) => {
        const socket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });
        
        socket.on('connect', () => {
            console.log(`🟢 Connected. Emitting join-meeting with ${idOrCode}...`);
            socket.emit('join-meeting', [idOrCode, HOST_ID, "Host User", true, "client_" + Math.random().toString(36).substring(7)]);
        });

        socket.on('join-confirmation', (data) => {
            console.log(`📥 Received join-confirmation for ${idOrCode}:`, JSON.stringify(data));
            socket.disconnect();
            resolve(data);
        });

        setTimeout(() => {
            console.log(`🕒 Timeout for ${idOrCode}`);
            socket.disconnect();
            resolve(null);
        }, 5000);
    });
}

async function runTests() {
    await testWith(MEETING_CODE);
    await testWith(MEETING_UUID);
}

runTests();
