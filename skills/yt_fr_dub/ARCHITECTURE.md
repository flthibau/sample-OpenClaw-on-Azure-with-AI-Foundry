# yt_fr_dub - Architecture & Documentation

## Overview

**OpenClaw Skill** to automatically convert a YouTube video to a French dubbed version.

| Component | Value |
|---------|--------|
| **Nom** | yt_fr_dub |
| **Version** | 0.1.0 |
| **Language** | Node.js (ES Modules) |
| **Location** | `/home/azureuser/.openclaw/workspace/skills/yt_fr_dub/` |

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         YT_FR_DUB PIPELINE                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   INPUT                                                                      │
│   ─────                                                                      │
│   YouTube URL  ─────┐                                                        │
│        or           ├──▶  [run.js]                                           │
│   Local MP4    ─────┘                                                        │
│                                                                              │
│   STEP 1: DOWNLOAD (yt-dlp)                                                  │
│   ──────────────────────────                                                 │
│   ┌─────────────┐     ┌─────────────┐                                        │
│   │  yt-dlp     │────▶│  video.mp4  │  (best video, no audio)                │
│   │  + cookies  │     │  audio.m4a  │  (best audio)                          │
│   │  + EJS      │     └─────────────┘                                        │
│   └─────────────┘                                                            │
│         │                                                                    │
│         ▼                                                                    │
│   STEP 2: TRANSCRIBE (AI Foundry - gpt-4o-transcribe)                        │
│   ───────────────────────────────────────────────────                        │
│   ┌─────────────┐     ┌─────────────────────────────────────────┐            │
│   │  audio.m4a  │────▶│  APIM /openai/deployments/              │            │
│   │             │     │       gpt-4o-transcribe/audio/          │            │
│   │             │     │       transcriptions                    │            │
│   └─────────────┘     └──────────────┬──────────────────────────┘            │
│                                      │                                       │
│                                      ▼                                       │
│                              ┌─────────────────┐                             │
│                              │  transcript.txt │                             │
│                              │  (English)      │                             │
│                              └────────┬────────┘                             │
│                                       │                                      │
│   STEP 3: TRANSLATE (AI Foundry - gpt-5.2)                                   │
│   ────────────────────────────────────────                                   │
│                                       │                                      │
│                                       ▼                                      │
│   ┌────────────────────────────────────────────────────────────┐             │
│   │  APIM /openai/deployments/gpt-5.2/chat/completions         │             │
│   │  System: "Professional translator for French voiceover"   │             │
│   │  User: <English transcript>                                │             │
│   └──────────────────────────┬─────────────────────────────────┘             │
│                              │                                               │
│                              ▼                                               │
│                      ┌─────────────────┐                                     │
│                      │  fr.txt         │                                     │
│                      │  (French text)  │                                     │
│                      └────────┬────────┘                                     │
│                               │                                              │
│   STEP 4: TTS (Azure Speech via APIM)                                        │
│   ───────────────────────────────────                                        │
│                               │                                              │
│                               ▼                                              │
│   ┌────────────────────────────────────────────────────────────┐             │
│   │  APIM /speech/cognitiveservices/v1                         │             │
│   │  Voice: fr-FR-DeniseNeural                                 │             │
│   │  Format: SSML                                              │             │
│   │  Output: audio-16khz-128kbitrate-mono-mp3                  │             │
│   └──────────────────────────┬─────────────────────────────────┘             │
│                              │                                               │
│                              ▼                                               │
│                      ┌─────────────────┐                                     │
│                      │  fr.mp3         │                                     │
│                      │  (French audio) │                                     │
│                      └────────┬────────┘                                     │
│                               │                                              │
│   STEP 5: AUDIO PROCESSING (ffmpeg)                                          │
│   ─────────────────────────────────                                          │
│                               │                                              │
│                               ▼                                              │
│   ┌─────────────────────────────────────────────────────────────┐            │
│   │  ① MP3 → WAV decode                                         │            │
│   │  ② Loudness normalization (-16 dB LUFS)                     │            │
│   │  ③ WAV → AAC encode (192kbps)                               │            │
│   └──────────────────────────┬──────────────────────────────────┘            │
│                              │                                               │
│                              ▼                                               │
│                      ┌─────────────────┐                                     │
│                      │  fr.m4a         │                                     │
│                      │  (AAC audio)    │                                     │
│                      └────────┬────────┘                                     │
│                               │                                              │
│   STEP 6: REMUX (ffmpeg)                                                     │
│   ──────────────────────                                                     │
│                               │                                              │
│   ┌─────────────┐             │                                              │
│   │  video.mp4  │─────────────┼──▶ ┌─────────────────────────────────────┐   │
│   │  (original) │             │    │  ffmpeg -map 0:v:0 -map 1:a:0       │   │
│   └─────────────┘             │    │  -c:v copy -c:a aac -shortest       │   │
│                               │    └──────────────────┬──────────────────┘   │
│                      ┌────────┘                       │                      │
│                      │                                │                      │
│                      ▼                                ▼                      │
│               ┌─────────────┐                ┌─────────────────────┐         │
│               │  fr.m4a     │                │  french_dub.mp4     │         │
│               │  (French)   │                │  (Final output)     │         │
│               └─────────────┘                └──────────┬──────────┘         │
│                                                         │                    │
│   STEP 7: UPLOAD (Azure Blob) - Optional                │                    │
│   ──────────────────────────────────────                │                    │
│                                                         ▼                    │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │  az storage blob upload                                             │    │
│   │  --account-name stopenclawmedia                                     │    │
│   │  --container-name media                                             │    │
│   │  --auth-mode login (MSI)                                            │    │
│   └──────────────────────────────┬──────────────────────────────────────┘    │
│                                  │                                           │
│                                  ▼                                           │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │  az storage blob generate-sas --as-user                             │    │
│   │  → SAS URL (valid 7 days)                                           │    │
│   └──────────────────────────────┬──────────────────────────────────────┘    │
│                                  │                                           │
│   OUTPUT                         │                                           │
│   ──────                         ▼                                           │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │  https://stopenclawmedia.blob.core.windows.net/media/french_dub.mp4 │    │
│   │  ?se=...&sp=r&sv=...&sig=...                                        │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Azure Infrastructure

### APIM Gateway

| Component | Endpoint |
|-----------|----------|
| **APIM** | `https://apim-openclaw-0974.azure-api.net` |
| **API Key** | `f912e4b174d645aabe927e80f9992ff6` |

### AI Foundry (via /openai/)

| Model | Deployment | Use | API Version |
|-------|------------|-----|-------------|
| GPT-4o Transcribe | `gpt-4o-transcribe` | Speech-to-Text | 2024-11-01-preview |
| GPT-5.2 | `gpt-5.2` | Translation EN→FR | 2024-10-21 |

### Azure Speech (via /speech/)

| Parameter | Value |
|-----------|-------|
| Endpoint | `/speech/cognitiveservices/v1` |
| Voice | `fr-FR-DeniseNeural` |
| Format | `audio-16khz-128kbitrate-mono-mp3` |
| Auth | MSI via APIM (aad# format) |

### Azure Blob Storage

| Parameter | Value |
|-----------|-------|
| Account | `stopenclawmedia` |
| Container | `media` |
| Region | `swedencentral` |
| Auth | VM MSI with role `Storage Blob Data Contributor` |

---

## Files Structure

```
yt_fr_dub/
├── run.js              # Main pipeline script (14KB)
├── package.json        # Dependencies (openai, yargs)
├── SKILL.md            # OpenClaw skill manifest
├── README.md           # Usage documentation
├── README_SETUP.md     # Initial setup notes
├── STATUS.md           # Current status & next steps
├── ARCHITECTURE.md     # This file
├── node_modules/       # npm dependencies
└── out/                # Output videos
    ├── french_dub.mp4
    ├── test_french_dub.mp4
    └── test_french_dub_blob.mp4
```

---

## Dependencies

### System (apt)

```bash
sudo apt-get install -y ffmpeg python3-pip
python3 -m pip install -U yt-dlp
```

### Node.js

```json
{
  "dependencies": {
    "openai": "^4.76.1",
    "yargs": "^17.7.2"
  }
}
```

### Required Binaries

| Binary | Purpose |
|--------|---------|
| `yt-dlp` | YouTube download (with EJS + cookies) |
| `ffmpeg` | Audio/video processing |
| `ffprobe` | Media info extraction |
| `curl` | API calls to APIM |
| `az` | Azure CLI for Blob upload |

---

## CLI Options

```bash
node run.js <youtubeUrl> [options]

Options:
  --input <path>        Use local MP4 (skip yt-dlp)
  --cookies <path>      yt-dlp cookies file
  --out <path>          Output MP4 path (default: out/french_dub.mp4)
  --workdir <path>      Working directory
  --maxMinutes <n>      Max video duration (default: 20)
  --voice <name>        TTS voice (default: fr-FR-DeniseNeural)
  --targetLoudnessDb    Audio normalization (default: -16)
  --blobUpload          Upload to Azure Blob (default: true)
  --blobAccount         Storage account (default: stopenclawmedia)
  --blobContainer       Container (default: media)
  --blobName            Blob filename
  --blobSasDays         SAS validity (default: 7)
  --no-blobUpload       Skip upload, keep local file
```

---

## Usage Examples

### Basic (YouTube URL → Blob SAS)

```bash
node run.js "https://youtu.be/VIDEO_ID"
# Output: SAS URL printed to stdout
```

### Local MP4 Input

```bash
node run.js "https://youtu.be/VIDEO_ID" --input /path/to/video.mp4
```

### Custom Voice

```bash
node run.js "https://youtu.be/VIDEO_ID" --voice fr-FR-HenriNeural
```

### Keep Local (No Upload)

```bash
node run.js "https://youtu.be/VIDEO_ID" --no-blobUpload --out ./my_dub.mp4
```

---

## Pipeline Steps Detail

### Step 1: Download (yt-dlp)

- Downloads best video (mp4, no audio) + best audio (m4a)
- Supports cookies for authenticated content
- Uses EJS remote components for JS challenges

### Step 2: Transcribe

- Sends audio to `gpt-4o-transcribe` via APIM
- Uses multipart/form-data (curl)
- Returns plain text transcript

### Step 3: Translate

- Sends transcript to `gpt-5.2` chat completion
- System prompt: professional translator
- Temperature: 0.2 (deterministic)

### Step 4: TTS

- Generates SSML with French text
- Sends to Azure Speech via APIM `/speech/`
- Output: MP3 (16kHz, 128kbps)

### Step 5: Audio Processing

- MP3 → WAV decode
- Loudness normalization (EBU R128, -16 LUFS)
- WAV → AAC encode (192kbps)

### Step 6: Remux

- Combines original video + new French audio
- Uses `-shortest` to match duration
- Video codec: copy (no re-encode)

### Step 7: Upload (optional)

- Uses `az storage blob upload` with MSI auth
- Generates user-delegation SAS URL
- Default validity: 7 days

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APIM_OPENAI_ENDPOINT` | `https://apim-openclaw-0974.azure-api.net` | APIM base URL |
| `APIM_OPENAI_API_KEY` | `f912e4b174d645aabe927e80f9992ff6` | APIM subscription key |
| `APIM_OPENAI_API_VERSION` | `2024-10-21` | OpenAI API version |
| `APIM_OPENAI_DEPLOYMENT_TRANSCRIBE` | `gpt-4o-transcribe` | STT deployment |
| `APIM_OPENAI_DEPLOYMENT_TRANSLATE` | `gpt-5.2` | Translation deployment |
| `SPEECH_TTS_ENDPOINT` | `${APIM}/speech/cognitiveservices/v1` | TTS endpoint |
| `SPEECH_TTS_VOICE` | `fr-FR-DeniseNeural` | TTS voice |
| `SPEECH_TTS_LANG` | `fr-FR` | TTS language |
| `BLOB_ACCOUNT` | `stopenclawmedia` | Storage account |
| `BLOB_CONTAINER` | `media` | Blob container |
| `BLOB_SAS_DAYS` | `7` | SAS validity |

---

## Limitations

1. **Single voice** - No speaker diarization/matching
2. **Duration limit** - Max 20 minutes recommended
3. **No sync** - Uses `-shortest`, no time-stretching
4. **YouTube blocks** - May need cookies for some videos

---

## Future Improvements

- [ ] Multi-speaker diarization with voice matching
- [ ] Subtitle generation (SRT/VTT)
- [ ] Time-stretch audio to match original duration
- [ ] Keep original audio as track 2
- [ ] Caching intermediate steps
- [ ] Support other languages (not just French)

---

*Generated by Copilot Azure - February 6, 2026*
