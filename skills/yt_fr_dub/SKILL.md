---
name: yt_fr_dub
description: YouTube URL → French dubbed MP4 → Blob link (SAS)
user-invocable: true
---

# yt_fr_dub (YouTube → French dub MP4)

Takes a YouTube URL, downloads the video, transcribes the original audio, translates to French, synthesizes French speech, and remuxes the new audio into an MP4.

## What it does

Pipeline:
1. **Download** best video (no audio) + best audio using `yt-dlp` (cookies + JS challenge support enabled by default).
2. **Enforce max duration**: refuses videos longer than **20 minutes** (configurable).
3. **Transcribe** audio via **AI Foundry /openai** (`gpt-4o-transcribe`).
4. **Translate** transcript to French via **AI Foundry /openai** (`gpt-5.2`).
5. **Synthesize** French audio via **Azure Speech /speech** (SSML, e.g. `fr-FR-DeniseNeural`).
6. **Remux** into MP4.
7. **Upload** to Azure Blob and return a **SAS URL** (default behavior).

## Tools used

- `yt-dlp`
- `ffmpeg`
- Node.js 22+

## Setup

### 1) Install OS dependencies

On Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg python3-pip
python3 -m pip install -U yt-dlp
```

Verify:

```bash
ffmpeg -version
yt-dlp --version
```

### 2) Environment variables

The script is currently configured with defaults matching this VM’s APIM setup.
If you need overrides:

AI Foundry (/openai):
- `APIM_OPENAI_ENDPOINT`
- `APIM_OPENAI_API_KEY`
- `APIM_OPENAI_API_VERSION`
- `APIM_OPENAI_DEPLOYMENT_TRANSCRIBE` (default: `gpt-4o-transcribe`)
- `APIM_OPENAI_DEPLOYMENT_TRANSLATE` (default: `gpt-5.2`)

Azure Speech TTS (/speech):
- `SPEECH_TTS_ENDPOINT` (default: `${APIM_OPENAI_ENDPOINT}/speech/cognitiveservices/v1`)
- `SPEECH_TTS_OUTPUT_FORMAT` (default: `audio-16khz-128kbitrate-mono-mp3`)
- `SPEECH_TTS_VOICE` (default: `fr-FR-DeniseNeural`)
- `SPEECH_TTS_LANG` (default: `fr-FR`)

YouTube download:
- Default cookies path: `~/.openclaw/secrets/youtube_cookies.txt` (can be overridden with `--cookies`)

### 3) OpenClaw exec allowlist

This skill runs external commands. Add these to your OpenClaw exec allowlist (exact mechanism depends on your OpenClaw config):

- `yt-dlp`
- `ffmpeg`
- `ffprobe`

If your allowlist supports patterns, allow:

- `yt-dlp *`
- `ffmpeg *`
- `ffprobe *`

### 4) Run (CLI)

```bash
node skills/yt_fr_dub/run.js "https://www.youtube.com/watch?v=..."
```

By default it uploads to Blob and prints a SAS URL.
To disable upload:

```bash
node skills/yt_fr_dub/run.js "https://www.youtube.com/watch?v=..." --no-blobUpload
```

## Notes / limitations

- This produces a **single French narration track** (no diarization/voice matching). For multi-speaker dubbing, you’d add speaker separation and per-speaker voice selection.
- The transcript is translated and synthesized as one chunk with SSML-like pacing hints (lightweight). Very long videos are rejected.
