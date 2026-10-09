# 233 Gold Trader Pro — starter prototype

This is a **starter project**, not a deployed or live trading app. It contains an Android control-panel shell, a small FastAPI server skeleton, and a copy of the EA source supplied in the conversation.

## Intended architecture
Android app → authenticated HTTPS API → MT5/VPS bridge → MT5 terminal → one selected broker (Deriv OR Exness)

## Important current status
- The Android screen is a UI prototype. Its controls do not yet send trading commands.
- The API is a local development skeleton. It does not connect to MT5 or any broker and it must not be exposed to the internet as-is.
- The EA copy is the starting source. It has not been compiled or backtested in MetaEditor here.
- Use demo accounts only until the strategy, execution, risk limits, and connection are independently tested.

## Android project
Open the `android` folder in Android Studio. Build with a current Android SDK / Gradle setup. The project uses a simple native Android Activity and does not include broker credentials.

## Development API
Python 3.10+ recommended:

```bash
cd server
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

API docs are available locally at `http://127.0.0.1:8000/docs` while the development server is running. Endpoints are informational/configuration placeholders only. They do not place trades.

## Next engineering steps
1. Compile and review the EA in MetaEditor and verify it is restricted to Gold and a single selected demo account.
2. Add a robust, authenticated bridge between EA and server (HTTPS polling or a signed command channel; MT5 WebRequest allowlist configuration required).
3. Implement server-side authentication, per-device tokens, encrypted secret storage, audit logs, command expiry, replay protection, and hard risk limits.
4. Connect the Android controls to authenticated API endpoints.
5. Run Strategy Tester and forward demo tests on each broker separately; confirm symbol naming (e.g. XAUUSD / XAUUSDm), contract size, minimum lot, margin, and stop-level rules.
6. Package/sign the Android APK and deploy the server to a secured VPS running MT5 continuously.

Never send a broker password to a chat, hard-code it in the app, or expose the development API directly to the public internet.
