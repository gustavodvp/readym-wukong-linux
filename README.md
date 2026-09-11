# readym-wukong-linux

Run **WukongMP** (the [ReadyM](https://ready.mp) multiplayer mod for *Black Myth:
Wukong*) on Linux with a **single install command**.

ReadyM has no native Linux client. This project runs the official Windows
**ReadyM Launcher** inside the game's own Proton prefix and pre-applies every
fix needed for the login, the UI and the game launch to work — so you don't
have to debug any of it. Once installed you just run `readym-wukong`, log in,
pick a server and play. Co-op and PvP both work. The game connects **directly**
to the server (its normal netcode over your network / VPN); nothing is proxied.

> **Status:** unofficial community wrapper. Not affiliated with ReadyM or Game
> Science. Tested on Arch/CachyOS + Proton Experimental. Please open an issue
> with your distro + Proton version if something breaks.

---

## What you need

| Requirement | Notes |
|---|---|
| **Black Myth: Wukong** on **Steam**, launched once | so the Proton prefix exists. Proton **Experimental** or a recent **GE-Proton** recommended. |
| **`protontricks`** (provides `protontricks-launch`) | `pacman -S protontricks` · `apt install protontricks` · or `flatpak install com.github.Matoking.protontricks` |
| **`xdg-utils`** | for the `readym://` login callback |
| **A ReadyM account** | free — <https://portal.ready.mp> |
| **The ReadyM Launcher installer** | download from <https://portal.ready.mp> (needs login, so it can't be auto-downloaded). Save the `.exe` anywhere. |
| **Network access to the server** | if it's on a private mesh (ZeroTier / Tailscale / WireGuard), join that first. |

You do **not** need Steam launch options, a second Steam entry, Lutris, or a
separate Wine prefix.

---

## Install

```bash
git clone https://github.com/<you>/readym-wukong-linux
cd readym-wukong-linux
./install.sh --installer ~/Downloads/ReadyM.Launcher-stable-Setup.exe
```

If the installer `.exe` is in `~/Downloads` or next to `install.sh`, you can
omit `--installer` and it will be found automatically.

The script is **idempotent** — re-run it any time (e.g. after a launcher
update) without harm.

<details>
<summary>What <code>install.sh</code> actually does</summary>

1. **Installs the ReadyM Launcher into the game's Proton prefix**
   (`.../steamapps/compatdata/2358720/pfx`) via `protontricks-launch`.
2. **Forces WebView2 to render in software** — sets
   `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu …` in the prefix's
   `HKCU\Environment`. Without this the launcher window is blank / the mouse
   cursor is invisible under Wine.
3. **Registers the `readym://` scheme** to a tiny forwarder
   (`readym-uri-handler`). The launcher's OAuth redirect is
   `readym://oauth/callback`; a Linux browser can't dispatch that, so the
   login token never returns. The forwarder hands the URL to the launcher
   process running inside the prefix.
4. **Writes `steam_appid.txt` (`2358720`)** into `b1/Binaries/Win64/` and the
   game root, so the modded game doesn't bounce off Steam's
   `SteamAPI_RestartAppIfNecessary` check and exit immediately.
5. **Installs `readym-wukong` + `readym-uri-handler`** into `~/.local/bin` and
   `.desktop` entries into `~/.local/share/applications`.

Nothing is installed system-wide; no `sudo`. See
[`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) for the full story.
</details>

---

## Play

1. **Start Steam** and keep it running (the game authenticates through it).
2. If the server is on a private network, **connect to that VPN / mesh**.
3. Launch:

   ```bash
   readym-wukong
   ```

   or start **"ReadyM Launcher (Black Myth: Wukong)"** from your app menu.

4. **Log in.** Your browser opens the ReadyM sign-in page. When it finishes it
   asks which app should open the `readym://` link — pick **"ReadyM URI
   Handler"** and tick *remember*. The launcher completes the login.
   *(The session is saved; next time it logs in automatically.)*
5. Click **Black Myth: Wukong**. If it asks for the game folder, point it at
   your install, e.g.
   `…/steamapps/common/BlackMythWukong` (the folder with `b1` and `Engine`).
6. **Server list** → *Join*, or **Direct connect** → `IP:9050`.
7. The launcher downloads the mods, injects the loader and starts the game.
   **Keep the launcher window open while you play** (like FiveM).

---

## Hosting a server

The dedicated server *does* have a native Linux build (and a Docker image) —
that part needs no workarounds. See the official docs:
<https://docs.ready.mp/wukong-mp/docs/quick-start>. In short:

```bash
# .NET 10 runtime required (or use the Docker image)
curl -LO https://readycodestorage.blob.core.windows.net/wukong-server-releases/wukong-server-linux64-0.4.1.zip
unzip wukong-server-linux64-*.zip -d wukong-server && cd wukong-server
chmod +x server && ./server        # co-op enabled by default; admin panel on :9050
```

Then players connect to `your-host:9050`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| **Login never completes / browser tab just sits there** | The `readym://` handler isn't wired up. Re-run `./install.sh`. When the browser prompts for an app to open the link, choose **ReadyM URI Handler**. Check `~/.local/state/readym-uri-handler.log`. |
| **Launcher window is blank or the cursor is invisible** | `install.sh` sets the WebView2 software-render flag; make sure it ran without errors. If the cursor is *still* invisible, your compositor is hiding the hardware cursor over Xwayland — enable **software cursors**: Hyprland → `cursor { no_hardware_cursors = 1 }`; wlroots → `WLR_NO_HARDWARE_CURSORS=1`; KDE/GNOME usually unaffected. |
| **"Falha ao obter o ticket de conexão" / connect times out** | You can't reach the server's IP. `ping <IP>`, check your VPN/mesh is up and this device is authorized. The server also needs port **9050 (TCP+UDP)** reachable. |
| **Game opens then closes after a few seconds** | `steam_appid.txt` missing from `b1/Binaries/Win64/`. Re-run `install.sh`. A Steam *"Verify integrity of game files"* deletes it — re-run afterwards. |
| **"ReadyM Launcher não está instalado no prefixo"** | You haven't run `install.sh`, or the game is on a different Steam library that changed. Re-run `install.sh`. |
| **protontricks is the Flatpak version and can't see the game** | Grant it access: `flatpak override --user --filesystem=~/.local/share/Steam com.github.Matoking.protontricks` — or install native `protontricks`. |
| **Bad performance** | The game runs inside the launcher's `protontricks-launch` session, so Steam launch options (gamemode, MangoHud, gamescope) don't apply. This is a known limitation of v1. |

Logs worth checking:

- `~/.local/state/readym-uri-handler.log` — the login-callback bridge
- `…/compatdata/2358720/pfx/drive_c/users/steamuser/AppData/Roaming/ReadyM.Launcher/WukongMP/CSharpLog.txt` — the in-game mod loader (shows the actual server connection)

---

## Uninstall

```bash
./uninstall.sh
```

Removes the commands, desktop entries, the `readym://` association and the
`steam_appid.txt` files. The launcher inside the Proton prefix is left in place;
the script prints how to remove that too.

---

## Credits & license

- **WukongMP / ReadyM** — <https://ready.mp> (their work; go support it).
- This wrapper: MIT license, see [`LICENSE`](LICENSE).
