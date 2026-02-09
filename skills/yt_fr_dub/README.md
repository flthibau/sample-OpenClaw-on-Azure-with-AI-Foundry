# yt_fr_dub — YouTube → French Dub (OpenClaw skill)

Goal: take a **YouTube URL** and produce an **MP4** with a **French dubbed audio track**.

## Overview (pipeline)

1. **Download video** (yt-dlp) or **local MP4 input** (`--input`)
2. **Transcription** (STT via AI Foundry / OpenAI-compatible)
3. **French translation** (chat via AI Foundry / OpenAI-compatible)
4. **French TTS (Text-to-Speech)** via **Azure Speech** (SSML)
5. **Remux** into a final MP4 (ffmpeg)

> Important: the **YouTube download** step may be blocked by anti-bot measures (*"Sign in to confirm you're not a bot"*). In that case, you need to provide **cookies** to yt-dlp (see dedicated section).

## Prerequisites

- Node.js (project already packaged)
- `ffmpeg` / `ffprobe`
- `yt-dlp`

## Key Files

- `run.js`: main script (download → STT → translate → TTS → remux)
- `SKILL.md`: skill description for OpenClaw
- `README_SETUP.md`: setup notes (historical)
- `STATUS.md`: current status / next steps (keep up to date)

## Usage (dev / test)

### Basic Test

```bash
cd skills/yt_fr_dub
node run.js "https://youtu.be/<id>" --out out/french_dub.mp4 --voice fr-FR-DeniseNeural
```

### Use a local MP4 as input (skip yt-dlp)

```bash
node run.js "https://youtu.be/<id>" --input /path/to/input.mp4 --out out/french_dub.mp4
```

### Upload to Azure Blob (returns a SAS URL in stdout)

✅ By default, the script uploads the result to Blob and returns a SAS URL.
To disable: `--no-blobUpload`.

Prerequisites: the VM must be able to run `az login --identity` and have the **Storage Blob Data Contributor** role.

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

Note: on recent YouTube, `yt-dlp` may require a JS runtime + EJS components.
In our tests, it works with:

- `--no-js-runtimes --js-runtimes "node:/usr/bin/node"`
- `--remote-components ejs:github`

When YouTube blocks yt-dlp, recommended solutions:

### Option A (safest)
Download **locally** (on your machine) then provide the MP4 to the pipeline.

Example:
- `yt-dlp --cookies-from-browser chrome "<URL>"`

### Option B (dedicated cookies)
If you want the download to happen on the VM:
- use a dedicated / disposable account
- provide temporary cookies
- delete cookies after testing

⚠️ Do not share "primary" cookies via messaging: this is equivalent to sharing an authenticated session.

## Expected Output

- Final MP4 with French dubbed audio (and optionally keeping the original audio as track 2 if desired).

## Future Improvements (ideas)

- proper management of multiple audio tracks
- French subtitles (SRT/VTT) in addition to the dub
- caching of pipeline steps (download/transcript)
- options: voice, speed, audio normalization, etc.
