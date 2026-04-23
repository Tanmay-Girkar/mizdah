const io = require('socket.io-client');

const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';
const MEETING_CODE = 'tgidlezdsq';
const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48';

const socket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

socket.on('connect', () => {
    console.log("🟢 Connected. Emitting join-meeting as MULTIPLE ARGS...");
    // Passing as separate arguments
    socket.emit('join-meeting', MEETING_CODE, HOST_ID, "Host User", true, "client_dart");
});

socket.on('join-confirmation', (data) => {
    console.log("📥 Received join-confirmation:", JSON.stringify(data));
});

socket.onAny((event, data) => {
    console.log(`📡 EVENT: ${event} | DATA:`, JSON.stringify(data));
});

setTimeout(() => { process.exit(0); }, 10000);
