# How it works

The short version: **the Windows ReadyM Launcher runs inside Black Myth:
Wukong's own Proton prefix**, and four small things are pre-configured so the
parts Wine/Proton don't handle by themselves just work.

## The pieces

### 1. The launcher runs in the game's prefix

`protontricks-launch --appid 2358720 ReadyM.Launcher.exe`

The launcher is a [Velopack](https://velopack.io/) app using
[Photino](https://www.tryphotino.io/) + WebView2 (Chromium via Edge runtime).
It must share **one** Wine prefix and **one** `wineserver` with the game,
because when you hit *Join* it:

- writes `AppData/Roaming/ReadyM.Launcher/wukong_handshake.env`
  (server IP/port, a JWT, a one-shot ticket, the mod folder path),
- drops proxy DLLs (`dxgi.dll`, `version.dll`, `stringzilla_shared.dll`) into
  `b1/Binaries/Win64/`,
- starts `b1.exe` as a child process.

The game loads the proxy `dxgi.dll`, which bootstraps the **CSharpLoader**
(Harmony + Mono.Cecil), which reads the handshake and connects to the server.

Running the game *through Steam* instead doesn't work here: Steam would spin up
a second, separate Proton session on the same prefix and deadlock on the prefix
lock while the launcher holds it. Letting the launcher spawn the game in its
own session sidesteps that.

### 2. WebView2 software rendering

Set once in the prefix registry:

```
HKCU\Environment\WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS =
    --disable-gpu --disable-gpu-compositing --disable-software-rasterizer
```

With GPU compositing on, WebView2 under Wine renders nothing (blank window) and
the mouse cursor disappears over the client area. Forcing software rendering
fixes both. `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` is a documented Microsoft
env var; putting it in `HKCU\Environment` makes Wine hand it to the launcher
process and its WebView2 children.

### 3. The `readym://` login bridge

The launcher signs in with OpenID Connect and a **custom-scheme redirect URI**:
`readym://oauth/callback`. That scheme is registered *inside* the Wine prefix
(`HKCU\Software\Classes\readym\shell\open\command`), but the browser that
handles the login is the **host's** browser, which has never heard of
`readym://`. So the token never comes back and the launcher sits on "signing
in…".

`install.sh` registers `x-scheme-handler/readym` on the host to
`readym-uri-handler`, which:

1. finds the pressure-vessel **bus name** of the running launcher container
   (`com.github.Matoking.protontricks.App2358720_*`, from the
   `steam-runtime-launch-client` cmdline),
2. runs `steam-runtime-launch-client --bus-name=<bus> -- wine
   ReadyM.Launcher.exe "<url>"` — i.e. launches a *second* launcher process
   **inside the same container**.

That second process starts, Velopack's self-locate succeeds (same PID
namespace), the deep link is handed to the already-running instance via
single-instance IPC, and the login finishes. Doing this via a fresh
`protontricks-launch` instead crashes in `Velopack.VelopackApp.Run()` because a
new pressure-vessel container has a different PID namespace and
`EnumProcessModules` returns `ACCESS_DENIED` — hence the in-container approach.

The session is then persisted to
`AppData/Roaming/ReadyM.Launcher/secure_storage.bin` (DPAPI, which Wine *does*
implement), so subsequent starts log in automatically. `PasswordVault` (WinRT),
which the launcher tries first, is not implemented by Wine — you'll see
`Refresh token is not saved` on the very first run; it's harmless.

### 4. `steam_appid.txt`

Black Myth: Wukong calls `SteamAPI_RestartAppIfNecessary(2358720)`. Launched
by the mod launcher rather than by Steam, it tries to relaunch itself through
Steam and exits (`"restarted by the platform"`). Dropping a `steam_appid.txt`
containing `2358720` next to the executable makes the Steam API skip that check
and initialise against the already-running Steam client. Standard technique for
modded Steam games.

## What is *not* hacked

- The game's multiplayer connection is **direct** to the server
  (UDP 9050 for game traffic, HTTP 9050 for tickets/saves). Nothing is proxied
  or MITM'd.
- The **dedicated server** has an official native Linux build and Docker image.
- No files in the vanilla game are modified except the added proxy DLLs and
  `steam_appid.txt` (all removable; a Steam file-verify restores stock state).

## Known limitations

- The game inherits the `protontricks-launch` environment, so Steam launch
  options (gamemode / MangoHud / gamescope) don't apply.
- First launch after a Proton version change is slow (prefix + container
  rebuild).
- Tied to `protontricks`' layout for the in-container `wine` path. If a future
  protontricks changes that, `readym-uri-handler` needs a one-line update.
