#!/usr/bin/env bash
# Prepara REA (LBNM-ONE/rea) in una sessione cloud di Claude Code con rete aperta.
# Idempotente: si può rieseguire senza danni.
#
# Uso:   bash /home/user/nebo-rea/scripts/setup-rea.sh
# Opzioni (variabili d'ambiente):
#   REA_DIR=/home/user/rea   checkout della repo rea
#   TOOLS_DIR=/root/rea-tools  dove finiscono JADX, apktool, Ghidra
#   SKIP_GHIDRA=1            non scaricare Ghidra (~450 MB, serve solo per le librerie native .so)
set -euo pipefail

REA_DIR="${REA_DIR:-/home/user/rea}"
TOOLS_DIR="${TOOLS_DIR:-/root/rea-tools}"
NODE_VERSION="24.18.0"
GHIDRA_TAG="Ghidra_12.1.4_build"
GHIDRA_DIR_NAME="ghidra_12.1.4_PUBLIC"
BIN_DIR="/root/.local/bin"
ENV_FILE="/root/.rea-env"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

# Scarica $1 in $2; se $3 è un SHA-256 lo verifica, altrimenti stampa quello calcolato.
download() {
  local url=$1 out=$2 sha=${3:--}
  curl -fL --retry 4 --retry-delay 2 -o "$out.partial" "$url"
  if [ "$sha" != "-" ]; then
    echo "$sha  $out.partial" | sha256sum -c --quiet - ||
      { rm -f "$out.partial"; die "SHA-256 non corrispondente per $url"; }
  else
    echo "ATTENZIONE: GitHub non ha fornito un digest; SHA-256 calcolato: $(sha256sum "$out.partial" | cut -d' ' -f1)"
  fi
  mv "$out.partial" "$out"
}

# Stampa "<url> <sha256|->" dell'asset di una release GitHub ($2 = tag oppure "latest").
gh_asset() {
  local api="https://api.github.com/repos/$1/releases/tags/$2" json
  [ "$2" = latest ] && api="https://api.github.com/repos/$1/releases/latest"
  json=$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api") ||
    die "API GitHub non raggiungibile ($api): la rete della sessione deve consentire api.github.com e github.com"
  printf '%s' "$json" | node -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const re = new RegExp(process.argv[1]);
      const asset = JSON.parse(s).assets.find((a) => re.test(a.name));
      if (!asset) { console.error(`asset non trovato: ${process.argv[1]}`); process.exit(1); }
      console.log(`${asset.browser_download_url} ${(asset.digest ?? "").replace(/^sha256:/, "") || "-"}`);
    });' "$3"
}

[ -d "$REA_DIR/.git" ] || die "repo rea non trovata in $REA_DIR (imposta REA_DIR)"
mkdir -p "$TOOLS_DIR" "$BIN_DIR"

log "1/7 Node.js $NODE_VERSION (versione fissata in .nvmrc della repo)"
export NVM_DIR="${NVM_DIR:-/opt/nvm}"
[ -s "$NVM_DIR/nvm.sh" ] || die "nvm non trovato in $NVM_DIR"
set +eu
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install "$NODE_VERSION" >/dev/null
set -eu
for b in node npm npx corepack; do
  ln -sf "$NVM_DIR/versions/node/v$NODE_VERSION/bin/$b" "$BIN_DIR/$b"
done
export PATH="$BIN_DIR:$PATH"
hash -r
[ "$(node -v)" = "v$NODE_VERSION" ] ||
  die "node attivo $(node -v), atteso v$NODE_VERSION: $BIN_DIR deve precedere /opt/node22/bin nel PATH"

log "2/7 Correzione della build (bug su main del 13/10/2026, commit c45d912)"
schema="$REA_DIR/src/domain/android/androidAnalysis.ts"
if grep -q 'direct_invokes_exhaustive: z.boolean().nullable().optional()' "$schema"; then
  sed -i 's/direct_invokes_exhaustive: z\.boolean()\.nullable()\.optional()/direct_invokes_exhaustive: z.boolean().nullable().exactOptional()/' "$schema"
  echo "Applicata in locale: è lo stesso cambio del commit d357803 (branch claude/repo-rea-setup-ytq9z7)."
else
  echo "Non necessaria: il codice è già corretto."
fi

log "3/7 Dipendenze e build di REA"
cd "$REA_DIR"
npm ci --no-audit --no-fund
npm run build:cached
ln -sf "$REA_DIR/scripts/rea.mjs" "$BIN_DIR/rea"

log "4/7 JADX headless 0.7.1 + APK di prova (script della repo, verifica SHA-256)"
npm run fixtures:android -- "$TOOLS_DIR"
JADX_JAR="$TOOLS_DIR/jadx-headless-mcp-0.7.1-all.jar"

log "5/7 apktool (ultima release)"
APKTOOL_JAR="$TOOLS_DIR/apktool.jar"
if [ ! -f "$APKTOOL_JAR" ]; then
  asset=$(gh_asset iBotPeaches/Apktool latest '^apktool_[0-9.]+\.jar$')
  read -r url sha <<<"$asset"
  download "$url" "$APKTOOL_JAR" "$sha"
fi
cat >"$TOOLS_DIR/apktool" <<EOF
#!/usr/bin/env bash
exec java -jar "$APKTOOL_JAR" "\$@"
EOF
chmod +x "$TOOLS_DIR/apktool"

GHIDRA_DIR=""
if [ "${SKIP_GHIDRA:-0}" != 1 ]; then
  log "6/7 Ghidra 12.1.4 (per le librerie native .so)"
  GHIDRA_DIR="$TOOLS_DIR/$GHIDRA_DIR_NAME"
  if [ ! -x "$GHIDRA_DIR/support/analyzeHeadless" ]; then
    asset=$(gh_asset NationalSecurityAgency/ghidra "$GHIDRA_TAG" '^ghidra_12\.1\.4_PUBLIC_[0-9]+\.zip$')
    read -r url sha <<<"$asset"
    download "$url" "$TOOLS_DIR/ghidra.zip" "$sha"
    unzip -q -o "$TOOLS_DIR/ghidra.zip" -d "$TOOLS_DIR"
    rm -f "$TOOLS_DIR/ghidra.zip"
  fi
else
  log "6/7 Ghidra saltato (SKIP_GHIDRA=1)"
fi

log "7/7 Variabili d'ambiente, registrazione in Claude Code, verifica"
JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
{
  echo "export PATH=\"$BIN_DIR:\$PATH\""
  echo "export JAVA_HOME=\"$JAVA_HOME_DIR\""
  echo "export REA_JADX_MCP_JAR=\"$JADX_JAR\""
  echo "export REA_APKTOOL_COMMAND=\"$TOOLS_DIR/apktool\""
  if [ -n "$GHIDRA_DIR" ]; then echo "export GHIDRA_INSTALL_DIR=\"$GHIDRA_DIR\""; fi
} >"$ENV_FILE"
grep -qxF ". $ENV_FILE" /root/.bashrc || echo ". $ENV_FILE" >>/root/.bashrc
# shellcheck disable=SC1090
. "$ENV_FILE"

rea setup --client claude_code --yes --filter-output status,appliedActions

echo
echo "--- Prova: inspect-android-package sull'APK di prova ApiDemos ---"
rea inspect-android-package "$TOOLS_DIR/ApiDemos-debug.apk" --token-limit 300 || echo "(prova JADX fallita: vedi sopra)"
echo
echo "--- apktool ---"
rea inspect-apktool-client --token-limit 200 || true
if [ -n "$GHIDRA_DIR" ]; then
  echo
  echo "--- Ghidra (doctor) ---"
  rea doctor --provider ghidra --filter-output providerInspections || true
fi

cat <<EOF

Fatto. Nelle prossime chiamate Bash le variabili arrivano da $ENV_FILE (caricato da ~/.bashrc);
se mancano: source $ENV_FILE
Comando: rea <comando>   (es. rea inspect-android-package /percorso/app.apk)
EOF
