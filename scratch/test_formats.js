const io = require('socket.io-client');
const axios = require('axios');

const BASE_URL = 'https://mizdah-backend.ogoul.cloud';
const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';
const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48';

async function testFormat(code) {
    console.log(`\n🚀 Testing Format: ${code}`);
    try {
        await axios.post(`${BASE_URL}/api/meetings/create`, {
            hostId: HOST_ID,
            title: 'Format Test',
            meeting_code: code,
            id: code
        });
    } catch (e) {}

    return new Promise((resolve) => {
        const socket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });
        socket.on('connect', () => {
            socket.emit('join-meeting', [code, HOST_ID, "Host User", true, "client_" + Math.random().toString(36).substring(7)]);
        });
        socket.on('join-confirmation', (data) => {
            console.log(`📥 Confirmation for ${code}:`, JSON.stringify(data));
            socket.disconnect();
            resolve(data);
        });
        setTimeout(() => { socket.disconnect(); resolve(null); }, 5000);
    });
}

async function run() {
    await testFormat("abc-defg-hij"); // 3-4-3
    await testFormat("abcdefghij");   // 10 char
}

run();
