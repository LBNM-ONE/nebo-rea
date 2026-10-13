#!/usr/bin/env bash
# Scarica un file da un link Google Drive condiviso ("Chiunque abbia il link").
# Uso: bash /home/user/nebo-rea/scripts/get-apk.sh '<link o ID Drive>' [file di destinazione]
# Destinazione predefinita: /root/targets/app.apk (fuori dalle repo: non va committato).
set -euo pipefail

[ $# -ge 1 ] || { echo "Uso: $0 '<link o ID Drive>' [destinazione]" >&2; exit 2; }
link=$1
out=${2:-/root/targets/app.apk}

# Accetta .../file/d/<ID>/..., ...?id=<ID>, oppure l'ID da solo.
if [[ $link =~ /d/([A-Za-z0-9_-]+) ]]; then id=${BASH_REMATCH[1]}
elif [[ $link =~ [?\&]id=([A-Za-z0-9_-]+) ]]; then id=${BASH_REMATCH[1]}
elif [[ $link =~ ^[A-Za-z0-9_-]{20,}$ ]]; then id=$link
else echo "Non riesco a ricavare l'ID del file da: $link" >&2; exit 2
fi

mkdir -p "$(dirname "$out")"
curl -fL --retry 4 --retry-delay 2 -o "$out.partial" \
  "https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t"

# Un APK/XAPK/APKS è un archivio ZIP: se non inizia con "PK" Drive ha restituito una pagina HTML
# (file non condiviso pubblicamente, quota superata, o link sbagliato).
if [ "$(head -c 2 "$out.partial")" != "PK" ]; then
  echo "Il download non è un archivio ZIP/APK. Inizio della risposta:" >&2
  head -c 400 "$out.partial" >&2; echo >&2
  rm -f "$out.partial"
  echo "Controlla che il file sia condiviso come 'Chiunque abbia il link'." >&2
  exit 1
fi
mv "$out.partial" "$out"
echo "Scaricato: $out"
ls -l "$out"
sha256sum "$out"
unzip -l "$out" | tail -1
