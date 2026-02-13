This is a comprehensive blueprint for building **"Mizdah"**, a production-ready Flutter clone of Google Meet.

Below is the **End-to-End User Flow** documenting every interaction, followed by the **"Anti-Gravity" Prompt** you can use to generate the complete codebase.

---

### **Part 1: The Mizdah Application Architecture**

**Core Tech Stack:**

* **Framework:** Flutter (Mobile - Android/iOS).
* **Design System:** Material 3 (Matches the screenshots provided).
* **State Management:** Riverpod or Provider (Recommended for Theme switching & User data).
* **Navigation:** GoRouter (For handling deep links like `mizdah.com/abc-def-ghi`).
* **Theme Engine:** A custom `ThemeManager` that listens to System Default but allows manual override in Settings.

---

### **Part 2: End-to-End User Flow (The Map)**

This flow ensures no "dead clicks." Every button has a destination.

#### **1. Splash & Authentication (Entry Point)**

* **Screen:** **Splash Screen**
* *Action:* Checks for existing Auth Token.
* *If Null:* Go to **Login Screen**.
* *If Valid:* Go to **Home Screen**.


* **Screen:** **Login Screen** (Implied)
* **Button:** "Sign in with Google" / "Email" -> Calls Auth API -> On Success -> Navigate to **Home Screen**.



#### **2. Home Screen (`image_a21401.png`)**

* **UI Component:** **Top Bar**
* **Button: Hamburger Menu (Top Left)** -> Opens **Navigation Drawer**.
* **Button: Search Bar ("Search contacts")** -> Opens **Global Search Delegate** (Keyboard opens, list filters).
* **Button: Avatar (Top Right)** -> Opens **Account Switcher Modal**.


* **UI Component:** **Main Body**
* **Empty State/History List:**
* *If History Exists:* List of recent calls. Tapping a list item -> **Re-join Meeting** or **Call Details**.
* *If Empty:* "Your latest activity will appear here" illustration.




* **UI Component:** **Floating Action Button (FAB)**
* **Button: "New" (Bottom Right)** -> Navigates to **Start a Call Screen**.



#### **3. Navigation Drawer (`image_a210bb.png`)**

* **Button: "Privacy in Meet"** -> Navigates to **Privacy Screen**.
* **Button: "Settings"** -> Navigates to **Settings Screen**.
* **Button: "Help and feedback"** -> Opens internal Webview with Help URL.

#### **4. Start a Call Screen (`image_a213e2.png`)**

* **UI Component:** **Action Buttons (Top)**
* **Button: "Create link"** -> Calls API to generate Room ID -> Opens **Share Link Modal**.
* **Button: "Schedule"** -> Navigates to **Schedule Meeting Screen**.
* **Button: "Group call"** -> Navigates to **Group Selection Screen**.


* **UI Component:** **Suggestions List**
* **Item: Contact Row** -> Tapping a contact -> Navigates to **Pre-Call Lobby** (Camera check) -> Then **Meeting Room**.



#### **5. Share Link Modal (`image_a213bf.png`)**

* *Triggered by "Create link"*
* **Display:** Generated Meeting Code (e.g., `vpm-mwrh-fjc`).
* **Button: Copy Icon** -> Copies link to clipboard. shows "Copied" snackbar.
* **Button: "Share"** -> Opens System Share Sheet (WhatsApp, Slack, etc.).
* **Button: "Join"** -> Navigates to **Meeting Room** immediately.
* **Button: "Dismiss"** -> Closes modal.

#### **6. Schedule Meeting Screen (`image_a213a1.png`)**

* **Input:** Title, Date, Time, Repeat, Color.
* **Button: "Close" (X)** -> Returns to previous screen without saving.
* **Button: "Save"** ->
* 1. Calls `createMeetingAPI(date, time, title)`.


* 2. Shows "Meeting Scheduled" confirmation.


* 3. Navigates back to **Home Screen**.





#### **7. Group Selection Screen (`image_a21381.png`)**

* **Action:** Tap Contact -> Adds Checkmark (Selects contact).
* **Button: "Start" / "Next" (Top Right)** ->
* 1. Creates a Room ID.


* 2. Invites selected User IDs.


* 3. Navigates to **Meeting Room**.





#### **8. Account Switcher (`image_a21364.png`)**

* **Button: "Add another account"** -> Opens Login Flow.
* **Button: "Manage accounts"** -> Opens System Account Settings.
* **Button: Tapping a different profile** -> Switches active User Context -> Reloads **Home Screen**.

#### **9. Settings Screen (`image_a21064.png`)**

* **Button: "General"** -> Opens **General Settings**.
* **Toggle: "Theme"** -> Opens Modal: [Light | Dark | System Default].


* **Button: "Account"** -> Profile details.
* **Button: "History"** -> Toggle "Save Call History".

#### **10. The Meeting Room (The Core)**

* *Note: This screen wasn't in your images, but is essential for "No dead clicks".*
* **UI:** Video Grid (using WebRTC).
* **Controls:** Mute, Camera Toggle, End Call (Returns to Home), Hand Raise.

---

### **Part 3: The "Anti-Gravity" Prompt**

Copy and paste the text below into a powerful coding LLM (like Claude 3.5 Sonnet, GPT-4o, or Gemini 1.5 Pro) to generate the project structure and code.

---

**PROMPT STARTS HERE**

> **Role:** You are a Senior Flutter Architect and UI/UX Specialist.
> **Task:** Create a complete, production-grade Flutter application named **"Mizdah"** (a Google Meet clone).
> **Constraints & Requirements:**
> 1. **Tech Stack:** Flutter (latest stable), Material 3 Design, `go_router` for navigation, `flutter_riverpod` for state management.
> 2. **Theme Engine:** Implement a robust Theme System.
> * Must support **Light Mode**, **Dark Mode**, and **System Default**.
> * Add a user preference in the Settings -> General screen to toggle this manually.
> * Persist this preference using `shared_preferences`.
> 
> 
> 3. **API Strategy (Mocked for now):** Use the Repository pattern. Create an abstract class `MizdahRepository` with methods like `getContacts()`, `createMeeting()`, `getCallHistory()`. Implement a `MockMizdahRepository` that returns dummy data so the UI is fully functional and clickable immediately.
> 4. **No Dead Clicks:** Every button, icon, and list tile must have an `onTap` that navigates to a valid screen or performs a feedback action (like a Snackbar or Modal).
> 
> 
> **Screen Specifications (Based on supplied Context):**
> * **Home Screen:** Top bar with Hamburger menu (opens Drawer), Search bar (navigates to SearchDelegate), and Avatar (opens Account Modal). Body shows a list of "Recent Calls" or an Empty State illustration if the list is empty. FAB at bottom right labeled "New" opens the "Start Call" screen.
> * **Start Call Screen:** Needs 3 top buttons: "Create Link" (opens Modal), "Schedule" (opens Form), "Group Call" (opens Contact Select). Below them, a list of contacts ("Suggestions").
> * **Share Modal:** Triggered by "Create Link". Shows a generated meeting code, Copy button, Share button, and a "Join" button that navigates to the Meeting Page.
> * **Schedule Screen:** Form fields for Title, Date/Time (use `showDatePicker`), and a "Save" button that adds the meeting to the mock list.
> * **Navigation Drawer:** Links to "Privacy" (static text page) and "Settings".
> * **Settings Screen:** Must include the "General" section where the Theme Toggle lives.
> * **Privacy Screen:** Static rich text explaining encryption (match the visual style of the reference: dark background, illustration).
> 
> 
> **Visual Style:**
> * Use the "Mizdah" branding colors: Deep Brown/Black background for Dark mode (Color `0xFF1E1A17`) and crisp White/Grey for Light mode.
> * Accent Color: A warm orange/brown (approx `0xFFE3CBA5` or similar from screenshots) for buttons.
> 
> 
> **Deliverables:**
> 1. Project file structure tree.
> 2. `main.dart` with Theme setup.
> 3. `theme_provider.dart` logic.
> 4. Code for the **Home Screen**, **Start Call Screen**, **Settings Screen**, and **Navigation Drawer**.
> 5. Mock Repository logic ensuring data flows through the app.
> 
> 
> Please write clean, modular code.

**PROMPT ENDS HERE**

---

### **Visual Reference for Layouts (Mental Model)**

When implementing the code generated by the prompt, keep these layouts in mind:

1. **The "Start Call" Layout (`image_a213e2.png`):**
* Use a `Column`.
* Top: `TextField` (Search).
* Middle: `Row` of 3 `Container` widgets (Create, Schedule, Group).
* Bottom: `ListView.builder` for Contacts.


2. **The Calendar Input (`image_a213a1.png`):**
* Use `SwitchListTile` for "All-day".
* Use `ListTile` with `onTap` triggering `showDatePicker` and `showTimePicker` for the dates.


3. **The Sidebar (`image_a210bb.png`):**
* Use a standard flutter `Drawer` widget.
* The header should contain the "Mizdah" text logo.



This plan gives you the exact logic to connect the buttons and the specific prompt to get the heavy lifting done by AI. Would you like me to simulate the **Flutter code for the "Theme Manager"** specifically, as that is the trickiest part to get right with System defaults?