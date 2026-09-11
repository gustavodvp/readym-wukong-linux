#!/usr/bin/env bash
#
# Removes everything install.sh added. Does NOT touch your Steam install or the
# game files beyond deleting the steam_appid.txt it created.
#
set -euo pipefail

APPID=2358720
BINDIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONDIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"

say() { printf '==> %s\n' "$*"; }

say "Removendo comandos e atalhos"
rm -f "$BINDIR/readym-wukong" "$BINDIR/readym-uri-handler"
rm -f "$APPDIR/readym-wukong.desktop" "$APPDIR/readym-uri-handler.desktop"
rm -f "$ICONDIR/readym-wukong.png"
update-desktop-database "$APPDIR" >/dev/null 2>&1 || true

say "Desfazendo associação do esquema readym://"
if [ "$(xdg-mime query default x-scheme-handler/readym 2>/dev/null || true)" = "readym-uri-handler.desktop" ]; then
  # não há 'xdg-mime remove'; aponta para algo inócuo
  xdg-mime default org.freedesktop.FileManager1.desktop x-scheme-handler/readym 2>/dev/null || true
fi

say "Procurando a pasta do jogo para remover o steam_appid.txt"
for d in "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.steam/root" \
         "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  [ -f "$d/steamapps/libraryfolders.vdf" ] || continue
  LIBS=$(printf '%s\n' "$d"
         grep -oE '"path"[[:space:]]*"[^"]+"' "$d/steamapps/libraryfolders.vdf" 2>/dev/null \
           | sed -E 's/.*"([^"]+)"$/\1/')
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    acf="$cand/steamapps/appmanifest_${APPID}.acf"
    [ -f "$acf" ] || continue
    idir=$(grep -oE '"installdir"[[:space:]]*"[^"]+"' "$acf" | sed -E 's/.*"([^"]+)"$/\1/')
    game="$cand/steamapps/common/$idir"
    rm -f "$game/b1/Binaries/Win64/steam_appid.txt" "$game/steam_appid.txt"
    say "  limpo: $game"
  done <<EOF
$LIBS
EOF
done

cat <<MSG

Feito. O ReadyM Launcher continua instalado dentro do prefixo Proton do jogo
(em .../compatdata/$APPID/pfx). Para remover também:

  protontricks-launch --appid $APPID \\
    "C:\\users\\steamuser\\AppData\\Local\\ReadyM.Launcher\\Update.exe" --uninstall

ou simplesmente apague a pasta
  .../steamapps/compatdata/$APPID/pfx/drive_c/users/steamuser/AppData/Local/ReadyM.Launcher*
MSG
