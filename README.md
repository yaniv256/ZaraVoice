# ZaraVoice iOS App

Native iOS app for voice interaction with Zara. Provides the same functionality as the web app at agent-flow.net/zara but with native iOS audio handling that allows background music (Spotify, etc.) to continue playing.

## Features

- **Continuous listening mode** - Mic stays open, auto-sends on silence, immediately restarts recording
- **Audio queue** - Zara's responses queue properly, chunks play in sequence without stepping on each other
- **Echo prevention** - Recording pauses during playback so Zara's voice isn't captured by mic
- **Audio breakthrough** - Zara can speak during silent periods even with mic open
- Voice recording with push-to-talk (legacy mode still works)
- Real-time transcription via Whisper API
- TTS responses via ElevenLabs
- Google OAuth authentication with PKCE
- Sign in with Apple support
- Camera and screenshot capture
- Video Watch mode for continuous camera capture
- Session history viewing
- Calibration UI for voice detection thresholds

## Repository

- GitHub: https://github.com/yaniv256/ZaraVoice
- Clone: `git clone https://github.com/yaniv256/ZaraVoice.git`

## Requirements

- Xcode 16+ 
- iOS 17.0+ deployment target
- macOS with Apple Silicon (for simulator)

## Project Structure

```
ZaraVoice/
├── ZaraVoice.xcodeproj
├── ZaraVoice/
│   ├── ZaraVoiceApp.swift      # App entry point
│   ├── ContentView.swift        # Main tab view (shows login or main UI)
│   ├── Views/
│   │   ├── LoginView.swift      # OAuth login screen (Google + Apple)
│   │   ├── VoiceView.swift      # Main voice interface
│   │   ├── SessionView.swift    # Session history
│   │   └── SettingsView.swift   # App settings
│   ├── Services/
│   │   ├── AuthManager.swift    # Authentication state management
│   │   ├── APIService.swift     # Backend API calls with Bearer token
│   │   └── AudioService.swift   # Recording and playback
│   └── Info.plist               # URL schemes for OAuth callback
└── README.md
```

## OAuth Configuration

### Google OAuth (iOS Client)

The app uses a dedicated iOS OAuth client (not the web client):

- **iOS Client ID**: `446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c.apps.googleusercontent.com`
- **Bundle ID**: `net.agentflow.ZaraVoice`
- **Redirect URI**: `com.googleusercontent.apps.446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c:/oauth2callback`

The iOS client uses **PKCE** (Proof Key for Code Exchange) instead of a client secret:
1. App generates random code_verifier
2. Derives code_challenge via SHA256
3. Sends code_challenge in auth request
4. Sends code_verifier in token exchange
5. Google verifies they match (no secret needed)

### Backend Mobile Auth Endpoint

The backend at agent-flow.net has a dedicated mobile OAuth endpoint:

```
POST /auth/mobile/google/callback
Content-Type: application/json

{
  "code": "<authorization_code>",
  "redirect_uri": "com.googleusercontent.apps.446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c:/oauth2callback",
  "code_verifier": "<pkce_verifier>"
}

Response: { "token": "<jwt>", "email": "user@example.com" }
```

The endpoint uses the iOS client ID (no secret) and validates the PKCE code_verifier.

### Info.plist URL Scheme

The app registers a URL scheme to receive OAuth callbacks:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.446740474721-bn1j0m9g981o1hd0ul1c82mgk5m2as3c</string>
        </array>
    </dict>
</array>
```

## Building the App

### From Xcode GUI

1. Open `ZaraVoice.xcodeproj` in Xcode
2. Select target device (simulator or physical device)
3. Press Cmd+R to build and run

### From Command Line

```bash
cd /Users/agent-zara/Projects/ZaraVoice

# Build for simulator
xcodebuild -scheme ZaraVoice -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build

# The built app is at:
# ~/Library/Developer/Xcode/DerivedData/ZaraVoice-*/Build/Products/Debug-iphonesimulator/ZaraVoice.app
```

## Mac Automation Setup (for Zara/Claude)

This section documents how Zara (Claude) can build, deploy, and test the iOS app remotely.

### SSH Access to Mac

```bash
# SSH tunnel via WSL (port 2223 forwards to Mac's SSH)
ssh -i ~/.ssh/id_ed25519_mac -o IdentitiesOnly=yes -p 2223 agent-zara@localhost

# Key location: ~/.ssh/id_ed25519_mac
# User: agent-zara
# Port: 2223 (forwarded through network)
```

### Computer Use MCP

The `computer-use-mcp` server provides screen control capabilities:

- **Port**: 3456 (HTTP transport)
- **Tool**: `computer` with action `get_screenshot`
- **Permissions App**: ComputerUseMCP.app (grants accessibility permissions)

To take screenshots via MCP:
```bash
curl -s -X POST http://localhost:3456/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"computer","arguments":{"action":"get_screenshot"}}}'
```

### Running GUI Apps on Yaniv's Display

Since agent-zara connects via SSH (no GUI session), we use sudo to run apps as yaniv:

```bash
# Sudoers entry (add via sudo visudo):
agent-zara ALL=(yaniv) NOPASSWD: ALL

# Launch Simulator on Yaniv's display:
sudo -u yaniv open -a Simulator

# Run simctl commands as yaniv:
sudo -u yaniv xcrun simctl list devices booted
sudo -u yaniv xcrun simctl install <DEVICE_UUID> /path/to/app.app
sudo -u yaniv xcrun simctl launch <DEVICE_UUID> net.agentflow.ZaraVoice
sudo -u yaniv xcrun simctl io <DEVICE_UUID> screenshot /tmp/screenshot.png
```

### Installing App in Yaniv's Simulator

Since yaniv can't read agent-zara's build directory, copy app to /tmp first:

```bash
# Copy built app to shared location
cp -r ~/Library/Developer/Xcode/DerivedData/ZaraVoice-*/Build/Products/Debug-iphonesimulator/ZaraVoice.app /tmp/ZaraVoice.app
chmod -R 755 /tmp/ZaraVoice.app

# Install in yaniv's simulator
sudo -u yaniv xcrun simctl install <DEVICE_UUID> /tmp/ZaraVoice.app

# Launch
sudo -u yaniv xcrun simctl launch <DEVICE_UUID> net.agentflow.ZaraVoice
```

### Preserving OAuth Session

After logging in, backup the app data container to skip future logins:

```bash
# Get app data container path
sudo -u yaniv xcrun simctl get_app_container <DEVICE_UUID> net.agentflow.ZaraVoice data
# Returns: /Users/yaniv/Library/Developer/CoreSimulator/Devices/<UUID>/data/Containers/Data/Application/<APP_UUID>

# Backup
sudo -u yaniv cp -r "<DATA_CONTAINER_PATH>" /tmp/ZaraVoice-data-backup

# Restore (after reinstalling app)
sudo -u yaniv cp -r /tmp/ZaraVoice-data-backup/* "<NEW_DATA_CONTAINER_PATH>/"
```

### Current Simulator UUIDs

- **Yaniv's iPhone 16e**: B4EC24FC-BF06-4430-88D9-213210BA6AEF
- **Agent-zara's iPhone 17**: C2CA2A3C-05B1-4E28-BF98-4D98B7C428F8

### Complete Build-Test Workflow

```bash
# 1. Pull latest code
cd /Users/agent-zara/Projects/ZaraVoice && git pull

# 2. Build
xcodebuild -scheme ZaraVoice -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build

# 3. Copy to shared location
cp -r ~/Library/Developer/Xcode/DerivedData/ZaraVoice-*/Build/Products/Debug-iphonesimulator/ZaraVoice.app /tmp/ZaraVoice.app
chmod -R 755 /tmp/ZaraVoice.app

# 4. Launch Simulator GUI (on Yaniv's display)
sudo -u yaniv open -a Simulator

# 5. Install and launch
sudo -u yaniv xcrun simctl install B4EC24FC-BF06-4430-88D9-213210BA6AEF /tmp/ZaraVoice.app
sudo -u yaniv xcrun simctl launch B4EC24FC-BF06-4430-88D9-213210BA6AEF net.agentflow.ZaraVoice

# 6. Take screenshot to verify
sudo -u yaniv xcrun simctl io B4EC24FC-BF06-4430-88D9-213210BA6AEF screenshot /tmp/sim-screenshot.png
```

## Backend Integration

### API Endpoints

All API calls go to `https://agent-flow.net`:

- `POST /auth/mobile/google/callback` - Exchange OAuth code for JWT
- `POST /zara/transcribe` - Send audio for transcription (requires Bearer token)
- `GET /zara/generate-tts` - Get TTS audio response
- `GET /zara/session-history` - Get session history

### Authentication Header

All authenticated requests include:
```
Authorization: Bearer <jwt_token>
```

The token is stored in UserDefaults after successful login.

## Troubleshooting

### "Custom scheme URIs not allowed for web client type"
You're using the web OAuth client ID. iOS requires an iOS-type OAuth client created in Google Cloud Console.

### "Error 400 redirect URI mismatch"
The redirect URI must exactly match. For iOS, use the reversed client ID format:
`com.googleusercontent.apps.<CLIENT_ID>:/oauth2callback`

### "Token exchange failed"
Check that:
1. The backend is using the iOS client ID (not web)
2. The code_verifier is being sent
3. The redirect_uri matches exactly

### App crashes on launch in simulator
Check for missing permissions or entitlements. Run via Xcode to see crash logs.

### Can't install app in yaniv's simulator
Copy app to /tmp first and chmod 755. Yaniv can't read agent-zara's home directory.

## Version History

- **2026-01-17**: v2.5 - Continuous listening mode matching web app behavior
  - Mic stays open until explicitly stopped
  - Auto-send on silence, immediately restarts recording for next utterance
  - Audio queue buffers chunks during playback (no more stepping on each other)
  - Audio breaks through during silence even with mic open
  - Echo prevention: recording pauses during Zara's playback
- **2026-01-16**: v2.4 - Silence detection and auto-send, calibration UI
- **2026-01-12**: Initial release with Google OAuth + PKCE, voice recording, TTS playback

---

## Simulator Login via ComputerUseMCP

When the app loses authentication (after reinstall), use ComputerUseMCP to complete the OAuth login flow.

### Prerequisites

1. ComputerUseMCP running on Mac (port 3456)
2. iOS Simulator running with ZaraVoice launched

### Launch App in Simulator

```bash
# SSH to Mac
ssh -i ~/.ssh/id_ed25519_mac -o IdentitiesOnly=yes -p 2223 agent-zara@localhost

# Build and install
cd /Users/agent-zara/Projects/ZaraVoice && git pull && \
xcodebuild -project ZaraVoice.xcodeproj -scheme ZaraVoice \
  -destination "platform=iOS Simulator,name=iPhone 16e" \
  -derivedDataPath /tmp/ZaraVoiceBuild build && \
sudo -u yaniv xcrun simctl install "iPhone 16e" \
  /tmp/ZaraVoiceBuild/Build/Products/Debug-iphonesimulator/ZaraVoice.app && \
sudo -u yaniv xcrun simctl launch "iPhone 16e" net.agentflow.ZaraVoice
```

### Screenshot and Click Commands

**Take screenshot (from WSL):**
```bash
ssh -i ~/.ssh/id_ed25519_mac -o IdentitiesOnly=yes -p 2223 agent-zara@localhost \
  "curl -s -X POST http://localhost:3456/mcp \
   -H 'Content-Type: application/json' \
   -H 'Accept: application/json, text/event-stream' \
   -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"computer","arguments":{"action":"get_screenshot"}},"id":1}' \
   > /tmp/screenshot.json && \
   python3 -c \"import json,base64; r=json.load(open(/tmp/screenshot.json)); img=[c for c in r[result][content] if c[type]==image][0][data]; open(/tmp/mac_screenshot.png,wb).write(base64.b64decode(img))\""

scp -i ~/.ssh/id_ed25519_mac -o IdentitiesOnly=yes -P 2223 agent-zara@localhost:/tmp/mac_screenshot.png /tmp/mac_screenshot.png
```

**Click at coordinates:**
```bash
ssh -i ~/.ssh/id_ed25519_mac -o IdentitiesOnly=yes -p 2223 agent-zara@localhost \
  "curl -s -X POST http://localhost:3456/mcp \
   -H 'Content-Type: application/json' \
   -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"computer","arguments":{"action":"left_click","coordinate":[X,Y]}},"id":1}'"
```

### Login Flow Steps

1. **Screenshot** - Verify app shows login screen
2. **Click "Sign in with Google"** - Approx (694, 623)
3. **Click "Continue"** on OAuth dialog - Approx (694, 583)
4. **Wait 2-3 seconds** for Google sign-in page to load
5. **Click email account** - Approx (694, 470)
6. **Click "Continue"** on consent page - Approx (694, 600)
7. **Screenshot** - Verify Settings shows "Connected to Zara" (green dot)

**Note:** Coordinates depend on simulator window position. Always take a screenshot first to verify button locations!

### Verification After Login

Check Settings tab shows:
- ✅ Green "Connected to Zara" status
- ✅ Auth Token displayed in Debug section
- ✅ SSE Error shows "None"

### Why Login Is Lost

The auth token is stored in UserDefaults for the simulator. When you:
- Uninstall and reinstall the app
- Reset simulator content
- Switch to a different simulator device

...the token is cleared and you need to log in again.
