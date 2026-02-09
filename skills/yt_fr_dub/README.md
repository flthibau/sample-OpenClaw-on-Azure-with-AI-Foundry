# yt_fr_dub — YouTube → doublage FR (OpenClaw skill)

Objectif : partir d’une **URL YouTube** et produire un **MP4** avec la **piste audio doublée en français**.

## Vue d’ensemble (pipeline)

1. **Download vidéo** (yt-dlp) ou **entrée MP4 locale** (`--input`)
2. **Transcription** (STT via AI Foundry / OpenAI-compatible)
3. **Traduction en français** (chat via AI Foundry / OpenAI-compatible)
4. **Synthèse vocale FR (TTS)** via **Azure Speech** (SSML)
5. **Remux** dans un MP4 final (ffmpeg)

> Important : la partie **download YouTube** peut être bloquée par l’anti-bot (*“Sign in to confirm you’re not a bot”*). Dans ce cas, il faut fournir des **cookies** à yt-dlp (voir section dédiée).

## Prérequis

- Node.js (projet déjà packagé)
- `ffmpeg` / `ffprobe`
- `yt-dlp`

## Fichiers clés

- `run.js` : script principal (download → STT → translate → TTS → remux)
- `SKILL.md` : description du skill pour OpenClaw
- `README_SETUP.md` : notes de setup (historique)
- `STATUS.md` : état courant / next steps (à tenir à jour)

## Utilisation (dev / test)

### Test basique

```bash
cd skills/yt_fr_dub
node run.js "https://youtu.be/<id>" --out out/french_dub.mp4 --voice fr-FR-DeniseNeural
```

### Utiliser un MP4 local en entrée (skip yt-dlp)

```bash
node run.js "https://youtu.be/<id>" --input /path/to/input.mp4 --out out/french_dub.mp4
```

### Upload Azure Blob (retourne une URL SAS dans stdout)

✅ Par défaut, le script uploade le résultat sur Blob et retourne une URL SAS.
Pour désactiver : `--no-blobUpload`.

Prérequis : la VM doit pouvoir faire `az login --identity` et avoir le rôle **Storage Blob Data Contributor**.

```bash
node run.js "https://youtu.be/<id>" \
  --input /path/to/input.mp4 \
  --out out/french_dub.mp4 \
  --blobUpload \
  --blobAccount stopenclawmedia \
  --blobContainer media \
  --blobName french_dub.mp4 \
  --blobSasDays 7
```

## YouTube anti-bot & cookies (important)

Note : sur YouTube récent, `yt-dlp` peut nécessiter un runtime JS + composants EJS.
Dans nos tests, ça marche avec :

- `--no-js-runtimes --js-runtimes "node:/usr/bin/node"`
- `--remote-components ejs:github`

Quand YouTube bloque yt-dlp, solutions recommandées :

### Option A (la plus safe)
Télécharger **en local** (sur ta machine) puis fournir le MP4 au pipeline.

Exemple :
- `yt-dlp --cookies-from-browser chrome "<URL>"`

### Option B (cookies dédiés)
Si tu veux que le téléchargement se fasse sur la VM :
- utiliser un compte dédié / jetable
- fournir des cookies temporaires
- supprimer les cookies après test

⚠️ Ne pas partager des cookies “principaux” via une messagerie : ça équivaut à partager une session authentifiée.

## Sorties attendues

- MP4 final avec audio doublé FR (et éventuellement conservation de l’audio original en piste 2 si on le veut).

## Prochaines améliorations (idées)

- gestion propre des pistes audio multiples
- sous-titres FR (SRT/VTT) en plus du dub
- caching des étapes (download/transcript)
- options : voix, vitesse, normalisation audio, etc.
