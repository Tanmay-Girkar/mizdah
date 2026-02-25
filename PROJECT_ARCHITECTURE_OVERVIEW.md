# 🚀 Google Meet Clone: Full Stack Architecture Overview

This document provides a comprehensive overview of the entire project, spanning the modern Frontend, the API Gateway, and the highly scalable Backend Microservices.

---

## 🎨 Frontend Architecture

The frontend is built with **Next.js 15 (App Router)** and **React**, focusing on high-performance real-time interactions and a premium user experience.

### 🛠️ Tech Stack
- **Framework**: Next.js 15 (React 19)
- **Styling**: Tailwind CSS + Lucide Icons
- **Real-time**: Socket.io-client
- **Media**: WebRTC (using PeerJS for signaling abstraction and Mediasoup for SFU capability)
- **State Management**: React Hooks (Custom hooks for media and peer logic)

### 🧩 Key Components & Hooks
- **`usePeer.ts`**: The core real-time engine. Manages socket connections, participant presence, and WebRTC signaling.
- **`useMediaStream.ts`**: Handles camera/microphone access, permissions, and stream management.
- **`MeetingPage`**: Optimized interface featuring:
  - Dynamic Grid Layout for participants.
  - Interactive Control Bar (Mute, Video, Screen Share, Chat, Recording).
  - Sidebar System (Chat history, Participant list).
  - Host Permission System (Waiting room modal).

### 🚦 API Gateway
The Next.js app acts as an **API Gateway** via the `app/api/` directory. It uses dynamic routing to proxy requests from the frontend to the internal microservices, abstracting the complex backend architecture from the client.

---

## 🏗️ Backend Architecture

The backend follows a **Microservices Architecture**, where each service is strictly isolated with its own domain logic, database schema, and port.

### 📡 Communication Patterns
1. **REST APIs**: Used for synchronous metadata management (Auth, Scheduling, History).
2. **WebSockets (Socket.io)**: Used for real-time signaling, chat delivery, and participant status broadcasts.
3. **SFU (Selective Forwarding Unit)**: Employs `mediasoup` to route media streams efficiently, preventing the browser from overloading in large meetings.

### 📦 The 11 Microservices

| Service | Port | Database Schema | Responsibility |
| :--- | :--- | :--- | :--- |
| **Signaling** | 4000 | - | Core WebRTC relay, Waiting Room, Host Controls. |
| **Meeting** | 4001 | `meeting` | Managing room lifecycle and metadata. |
| **Participant**| 4002 | `participant`| Tracking join/leave times and active presence. |
| **History** | 4003 | `history` | Archiving call logs and session analytics. |
| **Auth** | 4004 | `auth` | User identity, registration, and JWT issuance. |
| **Chat** | 4005 | `chat` | Persistent message storage and real-time delivery. |
| **Media** | 4006 | - | Mediasoup SFU logic for scalable video routing. |
| **Recording** | 4007 | `recording` | Managing meeting recording sessions and URLs. |
| **Notification**| 4008 | `notification`| Email invites (NodeMailer) and in-app alerts. |
| **Scheduling** | 4009 | `scheduling` | Planning future and recurring meetings. |
| **File** | 4010 | `file` | Centralized upload management and storage. |

---

## 🗄️ Database Design

We use a single **PostgreSQL** instance with **multi-schema support** enabled via Prisma. This allows:
- **Strict Data Isolation**: Services can only access their specific schema (e.g., `chat` cannot see `auth`).
- **Ease of Deployment**: All data lives in one DB instance (`mizdah`) but is logically separated.
- **Microservice Autonomy**: Each service maintains its own `schema.prisma`.

---

## 🚀 Operations

### Startup Commands
Start every service and the frontend concurrently:
```bash
npm run dev:all
```

### Database Management
Sync all service schemas with the PostgreSQL database:
```bash
npm run db:push:all
```

### Port Mapping Summary
- **Frontend/Gateway**: 3000
- **Signaling**: 4000
- **REST Services**: 4001 - 4010

---

*Verified & Synchronized: February 2026*
