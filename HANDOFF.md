# Handoff: analisi di un APK con REA

Aggiornato il 13/10/2026, alla fine della sessione "Preparazione repo rea".

## Obiettivo

Analizzare con **REA** (repo `LBNM-ONE/rea`, "Reverse Engineer Anything") un APK
Android dell'utente. L'APK è troppo grande per allegarlo in chat dal telefono:
l'utente lo carica su **Google Drive**, lo condivide come "Chiunque abbia il link"
e incolla il link nella sessione.

## Cosa fare nella nuova sessione

1. **Prepara REA** (3–5 minuti, ~1,5 GB su disco con Ghidra):
   ```bash
   bash /home/user/nebo-rea/scripts/setup-rea.sh
   ```
   Installa Node 24.18.0, esegue `npm ci` e la build di REA, scarica JADX 0.7.1
   (SHA-256 verificato) e un APK di prova, scarica apktool e Ghidra 12.1.4, scrive le
   variabili in `/root/.rea-env`, registra REA in Claude Code e installa la skill
   `reverse-engineer-anything`. Alla fine fa una prova con JADX sull'APK di prova.
   `SKIP_GHIDRA=1` salta Ghidra, che serve solo per le librerie native `.so`.
   Se i percorsi delle repo sono diversi, controlla con `ls /home/user` e passa `REA_DIR=...`.

2. **Scarica l'APK** dal link Drive che l'utente incolla:
   ```bash
   bash /home/user/nebo-rea/scripts/get-apk.sh '<link Drive>'   # → /root/targets/app.apk
   ```
   Lo script si ferma se Drive restituisce una pagina HTML invece del file, di solito
   perché il file non è condiviso pubblicamente. Se l'utente carica più file (APK
   divisi: base + split, oppure `.apks`/`.xapk`), scaricali tutti con nomi diversi
   passando il secondo argomento.

3. **Analizza** con il CLI (`rea <comando> --help` per gli argomenti) e carica la
   skill `reverse-engineer-anything` per il flusso di lavoro consigliato:
   - `rea inspect-android-package <apk>`: package, SDK, permessi, manifest
   - `rea decode-android-resources <apk>`: manifest e stringhe decodificati con apktool
   - `rea search-android-classes`, `rea inspect-android-class`,
     `rea inspect-android-method`, `rea trace-android-references`: codice Java/Kotlin
     tramite JADX
   - `rea identify-flutter-build <apk>`: se l'app è Flutter
   - librerie native: estrai le `.so` (`unzip`, oppure `rea extract-artifact`) e
     analizzale con `rea analyze <lib.so> --provider ghidra`
   - gli output sono lunghi: usa `--token-limit <n>` e `--filter-output <chiavi>`

   Il server MCP di REA viene registrato in `/root/.claude.json`, ma entra in gioco
   solo nelle sessioni avviate dopo. Nella sessione corrente usa il CLI, che offre
   gli stessi strumenti.

## Rete richiesta

La sessione precedente (ambiente cloud **Rea-nebo**) bloccava github.com, Google
Drive e gli altri servizi di file sharing. Serve un ambiente con rete **Full**,
oppure **Custom** con "Also include default list of common package managers" e
questi domini:

```
github.com
api.github.com
objects.githubusercontent.com
release-assets.githubusercontent.com
drive.google.com
drive.usercontent.google.com
```

## Stato lasciato dalla sessione precedente

- **Correzione della build di REA**: il `main` di `LBNM-ONE/rea` al commit `c45d912`
  non compila (`direct_invokes_exhaustive` usa `.optional()` invece di
  `.exactOptional()` in `src/domain/android/androidAnalysis.ts`). La correzione è il
  commit `d357803`, già pushato sul branch `claude/repo-rea-setup-ytq9z7` di `LBNM-ONE/rea`.
  `setup-rea.sh` la applica in locale se il checkout non la contiene ancora. In quel
  caso il controllo di fine turno chiederà di committarla: committala sul branch
  della sessione con lo stesso messaggio
  (`fix(android): keep direct invoke coverage JSON-compatible`).
- **Hook pre-push di rea**: `npm run check:fast` fallisce per 4 errori di lint
  (`max-lines-per-function`) già presenti su `main`, in file di test:
  `tests/boundary/providers/ghidra/ghidraLauncher.test.ts`,
  `src/ghidra/GhidraFunctionValues.test.ts`, `tests/composition/idaProvider.test.ts`,
  `src/domain/webBundleAnalyzer.test.ts`. Nella sessione precedente l'utente ha
  autorizzato `git push --no-verify` una volta: chiedi di nuovo prima di rifarlo.
- **GitHub**: la Claude GitHub App è installata sull'account `LBNM-ONE` e il push funziona.
- **Verificato**: Node 24.18.0 / npm 11.16.0, `npm ci`, build, typecheck, test
  `tests/boundary/android/JadxAnalysis.test.ts` (9/9), server MCP (`rea` 6.4.0, 191
  strumenti), `rea inspect-android-package` con JADX 0.7.1 su ApiDemos (2876 classi,
  Java 21).
- **Non disponibili**: Hopper e IDA, commerciali e da fornire a parte.
  Ghidra è gratuito e lo installa lo script.

## Regole da rispettare

- Non committare APK, JAR, output di analisi o altri binari, né in `rea` né qui
  (vedi `AGENTS.md` di rea). Tieni i file analizzati in `/root/targets/`.
- In `rea` usa i Conventional Commits; i file di pianificazione non vanno in `rea`.
- L'ambiente è temporaneo: tutto ciò che installa lo script va rifatto in ogni nuova
  sessione rieseguendolo.
