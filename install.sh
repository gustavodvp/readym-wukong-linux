#!/usr/bin/env bash
#
# readym-wukong-linux — one-command setup for WukongMP (ReadyM) on Linux.
#
# Runs the Windows "ReadyM Launcher" inside Black Myth: Wukong's own Proton
# prefix and wires up everything that Wine/Proton does not handle on its own:
#
#   1. installs the launcher into the game's Proton prefix
#   2. forces WebView2 to render in software (fixes a blank UI / invisible cursor)
#   3. registers the  readym://  OAuth callback scheme so the login flow can
#      finish (the browser hands the token back to the launcher)
#   4. drops steam_appid.txt in the game folder so the modded game does not
#      bounce off Steam's "relaunch me through Steam" check
#   5. installs the `readym-wukong` launcher command + desktop entry
#
# Re-running is safe (idempotent).
#
set -uo pipefail   # no -e: this script shells out to flaky things (wine, pkill,
                   # protontricks) and handles their failures explicitly.

APPID=2358720
GAME_NAME="Black Myth: Wukong"
LAUNCHER_EXE_REL='drive_c/users/steamuser/AppData/Local/ReadyM.Launcher/current/ReadyM.Launcher.exe'
WEBVIEW2_FLAGS='--disable-gpu --disable-gpu-compositing --disable-software-rasterizer'

BINDIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONDIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
say()  { printf '%s==>%s %s\n'  "$c_ok"   "$c_off" "$*"; }
warn() { printf '%s!!%s  %s\n'  "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%sxx%s  %s\n'  "$c_err"  "$c_off" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- args ---------
INSTALLER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) INSTALLER="${2:-}"; shift 2 ;;
    --installer=*) INSTALLER="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "argumento desconhecido: $1  (use --installer CAMINHO.exe)" ;;
  esac
done

# ---------------------------------------------------------- dependencies -------
say "Verificando dependências"
command -v steam        >/dev/null || die "Steam não encontrado no PATH."
command -v xdg-mime     >/dev/null || die "xdg-utils não encontrado (pacote: xdg-utils)."
command -v unzip        >/dev/null || warn "unzip ausente — não é crítico, mas recomendado."

PT_LAUNCH=()
if command -v protontricks-launch >/dev/null; then
  PT_LAUNCH=(protontricks-launch)
elif flatpak info com.github.Matoking.protontricks >/dev/null 2>&1; then
  PT_LAUNCH=(flatpak run --command=protontricks-launch com.github.Matoking.protontricks)
  warn "Usando protontricks via Flatpak — se o launcher não achar o jogo, instale a versão nativa."
else
  die "protontricks não encontrado. Instale o pacote 'protontricks' (traz 'protontricks-launch')."
fi

# ---------------------------------------------------- locate steam / game -----
say "Localizando o Steam e o $GAME_NAME"
STEAM_ROOT=""
for d in "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.steam/root" \
         "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  [ -f "$d/steamapps/libraryfolders.vdf" ] && { STEAM_ROOT="$d"; break; }
done
[ -n "$STEAM_ROOT" ] || die "Não achei a instalação do Steam (libraryfolders.vdf)."

LIBS=$(printf '%s\n' "$STEAM_ROOT"
       grep -oE '"path"[[:space:]]*"[^"]+"' "$STEAM_ROOT/steamapps/libraryfolders.vdf" 2>/dev/null \
         | sed -E 's/.*"([^"]+)"$/\1/')
LIB=""
while IFS= read -r cand; do
  [ -n "$cand" ] || continue
  if [ -f "$cand/steamapps/appmanifest_${APPID}.acf" ]; then LIB="$cand"; break; fi
done <<EOF
$LIBS
EOF
[ -n "$LIB" ] || die "$GAME_NAME (appid $APPID) não está instalado pelo Steam."

INSTALLDIR=$(grep -oE '"installdir"[[:space:]]*"[^"]+"' "$LIB/steamapps/appmanifest_${APPID}.acf" \
             | sed -E 's/.*"([^"]+)"$/\1/')
GAME_DIR="$LIB/steamapps/common/$INSTALLDIR"
PREFIX="$LIB/steamapps/compatdata/${APPID}/pfx"

[ -d "$GAME_DIR/b1/Binaries/Win64" ] || die "Pasta do jogo estranha: $GAME_DIR (sem b1/Binaries/Win64)."
[ -d "$PREFIX" ] || die "Prefixo Proton ainda não existe. Abra o $GAME_NAME pelo Steam uma vez e feche."

say "Jogo:    $GAME_DIR"
say "Prefixo: $PREFIX"

# ------------------------------------------------- find the launcher .exe -----
if [ -z "$INSTALLER" ]; then
  for cand in "$SELF_DIR"/ReadyM*Setup*.exe "$SELF_DIR"/ReadyM*.exe \
              "$HOME/Downloads"/ReadyM*Setup*.exe "$HOME/Downloads"/ReadyM*.exe; do
    [ -f "$cand" ] && { INSTALLER="$cand"; break; }
  done
fi
if [ -z "$INSTALLER" ] || [ ! -f "$INSTALLER" ]; then
  cat >&2 <<MSG

${c_err}Instalador do ReadyM Launcher não encontrado.${c_off}

  1. Baixe em:  https://portal.ready.mp   (faça login → download do Launcher)
  2. Rode de novo apontando o arquivo:

       $SELF_NAME --installer ~/Downloads/ReadyM.Launcher-stable-Setup.exe

MSG
  exit 1
fi
say "Instalador: $INSTALLER"

# ----------------------------------------------------- helpers in-prefix ------
pfx_run() {  # roda um .exe do Windows dentro do prefixo do jogo
  "${PT_LAUNCH[@]}" --appid "$APPID" "$@"
}
REG_EXE="$PREFIX/drive_c/windows/system32/reg.exe"

# 1) instala o launcher no prefixo ------------------------------------------------
if [ -f "$PREFIX/$LAUNCHER_EXE_REL" ]; then
  say "ReadyM Launcher já instalado no prefixo — pulando instalador"
else
  say "Instalando o ReadyM Launcher no prefixo (pode abrir e fechar janelas)"
  # O instalador Velopack abre o app no fim; esperamos o .exe aparecer, depois
  # encerramos o instalador e o app.
  #
  # NB: os padrões de pkill abaixo são deliberadamente estreitos. "ReadyM.Launcher"
  # sozinho casaria com o caminho do próprio instalador (…ReadyM.Launcher-stable-
  # Setup.exe) e mataria este script. 'ReadyM\.Launcher\.exe' (ponto literal) não.
  ( timeout 200 "${PT_LAUNCH[@]}" --appid "$APPID" "$INSTALLER" >/dev/null 2>&1 ) &
  ipid=$!
  ok=0
  for _ in $(seq 1 90); do
    if [ -f "$PREFIX/$LAUNCHER_EXE_REL" ]; then ok=1; sleep 3; break; fi
    kill -0 "$ipid" 2>/dev/null || break
    sleep 2
  done
  pkill -f 'ReadyM\.Launcher\.exe'            2>/dev/null
  pkill -f "protontricks-launch .*--appid $APPID" 2>/dev/null
  pkill -f "reaper .*AppId=$APPID"            2>/dev/null
  wait "$ipid" 2>/dev/null
  [ "$ok" = 1 ] && [ -f "$PREFIX/$LAUNCHER_EXE_REL" ] \
    || die "A instalação não produziu o ReadyM.Launcher.exe no prefixo."
fi

# 2) WebView2 em software (UI/cursor) ------------------------------------------
say "Configurando WebView2 para renderizar em software"
pfx_run "$REG_EXE" add 'HKCU\Environment' /v WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS \
        /d "$WEBVIEW2_FLAGS" /f >/dev/null 2>&1 || warn "Falha ao gravar a chave WEBVIEW2 (siga assim mesmo)."

# limpa restos de tentativas antigas (virtual desktop) — inofensivo se não existir
pfx_run "$REG_EXE" delete 'HKCU\Software\Wine\AppDefaults\ReadyM.Launcher.exe\Explorer' /f >/dev/null 2>&1 || true

# 3) steam_appid.txt no jogo -------------------------------------------------------
say "Escrevendo steam_appid.txt na pasta do jogo"
printf '%s' "$APPID" > "$GAME_DIR/b1/Binaries/Win64/steam_appid.txt"
printf '%s' "$APPID" > "$GAME_DIR/steam_appid.txt"

# 4) comandos + atalhos ---------------------------------------------------------
# Quando este script roda de um checkout do git (tem bin/ e share/ ao lado),
# ele mesmo instala os comandos e os .desktop no diretório do usuário.
# Quando roda a partir de um pacote (AUR/pacman), esses arquivos já foram
# colocados em /usr pelo próprio pacote — não há nada a copiar aqui, só o
# passo 5 (associação por-usuário do esquema readym://) ainda é necessário.
if [ -f "$SELF_DIR/bin/readym-wukong" ]; then
  say "Instalando 'readym-wukong' e 'readym-uri-handler' em $BINDIR"
  mkdir -p "$BINDIR" "$APPDIR" "$ICONDIR"
  install -m 0755 "$SELF_DIR/bin/readym-wukong"      "$BINDIR/readym-wukong"
  install -m 0755 "$SELF_DIR/bin/readym-uri-handler" "$BINDIR/readym-uri-handler"

  # ícone (extraído do próprio launcher, se disponível)
  LOGO="$PREFIX/drive_c/users/steamuser/AppData/Local/ReadyM.Launcher/current/Assets/readym_logo.png"
  [ -f "$LOGO" ] && install -m 0644 "$LOGO" "$ICONDIR/readym-wukong.png" || true

  sed -e "s|@BIN@|$BINDIR|g" "$SELF_DIR/share/applications/readym-wukong.desktop" \
      > "$APPDIR/readym-wukong.desktop"
  sed -e "s|@BIN@|$BINDIR|g" "$SELF_DIR/share/applications/readym-uri-handler.desktop" \
      > "$APPDIR/readym-uri-handler.desktop"
  update-desktop-database "$APPDIR" >/dev/null 2>&1 || true
else
  say "Comandos e atalhos já vieram pelo pacote — nada a copiar"
fi

# 5) registra o esquema readym:// (sempre por-usuário, mesmo empacotado) -----------
say "Registrando o esquema readym:// (callback do login)"
xdg-mime default readym-uri-handler.desktop x-scheme-handler/readym

# ------------------------------------------------------------------ done -------
HAVE_PATH=no
case ":$PATH:" in *":$BINDIR:"*) HAVE_PATH=yes ;; esac

cat <<DONE

${c_ok}Pronto.${c_off}

  Iniciar:   ${c_dim}readym-wukong${c_off}   (ou pelo menu de aplicativos: "ReadyM Launcher")

  Antes de jogar:
    • deixe o Steam aberto (autenticação do jogo)
    • se o servidor estiver numa rede privada (ZeroTier/Tailscale/VPN),
      conecte-se a ela antes

  No launcher: login → escolha Black Myth: Wukong → (se pedir) aponte a pasta
  do jogo para:
      $GAME_DIR
  → Conexão direta  IP:9050  (ou escolha da lista) → Entrar.
  Mantenha o launcher aberto enquanto joga.

DONE

if [ "$HAVE_PATH" = no ]; then
  warn "$BINDIR não está no seu PATH. Adicione ao seu shell:"
  printf '       export PATH="%s:$PATH"\n\n' "$BINDIR"
fi
