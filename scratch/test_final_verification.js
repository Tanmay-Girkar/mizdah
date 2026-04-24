const io = require('socket.io-client');
const axios = require('axios');

const BASE_URL = 'https://mizdah-backend.ogoul.cloud';
const SOCKET_URL = 'https://mizdah-backend.ogoul.cloud';
const PATH = '/signaling-fresh';

// Actual User ID from logs to ensure host identification works
const HOST_ID = 'a7bae225-5f5a-40b6-b177-36cf1c0d3e48'; 
const GUEST_ID = 'guest-' + Math.random().toString(36).substring(7);

async function runVerification() {
    console.log("🚀 Step 1: Creating Instant Meeting...");
    const meetingCode = 'verify' + Math.random().toString(36).substring(7);
    
    let realMeetingId;
    try {
        const createRes = await axios.post(`${BASE_URL}/api/meetings/create`, {
            hostId: HOST_ID,
            title: 'Final Verification Meeting',
            meeting_code: meetingCode,
            id: meetingCode
        });
        realMeetingId = createRes.data.id || meetingCode;
        console.log("✅ Meeting Created. Code:", meetingCode);
    } catch (e) {
        console.log("❌ Create Failed:", e.message);
        return;
    }

    console.log("\n🚀 Step 2: Connecting HOST...");
    const hostSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

    hostSocket.on('connect', () => {
        console.log("✅ HOST Socket Connected. ID:", hostSocket.id);
        // Emitting with POSITIONAL ARGUMENTS (like my new Flutter fix)
        hostSocket.emit('join-meeting', meetingCode, HOST_ID, "Flutter Host", true, hostSocket.id);
    });

    hostSocket.on('join-confirmation', (data) => {
        console.log("📥 HOST Confirmation:", JSON.stringify(data));
        if (data.status === 'JOINED' && data.isHost) {
            console.log("⭐⭐⭐ HOST IDENTIFIED CORRECTLY ⭐⭐⭐");
            connectGuest();
        } else {
            console.log("❌ HOST Identification Failed:", data.status);
        }
    });

    hostSocket.on('request-to-join', (data) => {
        console.log("\n📥 HOST RECEIVED REQUEST TO JOIN:", JSON.stringify(data));
        const guestSocketId = Array.isArray(data) ? data[0].socketId : data.socketId;
        console.log("🚀 Admitting Guest:", guestSocketId);
        hostSocket.emit('admit-user', { socketId: guestSocketId });
    });

    function connectGuest() {
        console.log("\n🚀 Step 3: Connecting GUEST...");
        const guestSocket = io(SOCKET_URL, { path: PATH, transports: ['websocket'] });

        guestSocket.on('connect', () => {
            console.log("✅ GUEST Socket Connected. ID:", guestSocket.id);
            // Guest join
            guestSocket.emit('join-meeting', meetingCode, GUEST_ID, "Web Guest", false, guestSocket.id);
        });

        guestSocket.on('join-confirmation', (data) => {
            console.log("📥 GUEST Status Update:", data.status || data);
            if (data.status === 'JOINED' || data === 'JOINED') {
                console.log("⭐⭐⭐ GUEST ADMITTED SUCCESSFULLY ⭐⭐⭐");
                console.log("\n✅ VERIFICATION COMPLETE: ALL SYSTEMS GO.");
                process.exit(0);
            }
        });
    }

    // Timeout safety
    setTimeout(() => {
        console.log("\n❌ VERIFICATION TIMEOUT: Admission flow stuck.");
        process.exit(1);
    }, 15000);
}

runVerification();
