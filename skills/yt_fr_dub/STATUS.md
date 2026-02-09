# STATUS — yt_fr_dub

## Summary

OpenClaw Skill: **YouTube URL → French dubbed MP4**.

## Current Status

- Overall pipeline OK: download/MP4 input → transcribe → translate → TTS → remux
- TTS: **Azure Speech via APIM** (`/speech/cognitiveservices/v1`, SSML)
- CLI additions:
  - `--input <mp4>` to use a local file (skip yt-dlp)
  - `--blobUpload` (+ options) to upload the final MP4 to Azure Blob and return a **SAS URL**
- VM tools: `ffmpeg` / `ffprobe`, `yt-dlp`, `curl`, `az`
- Safeguard: videos **< 20 min** recommended for testing

## Main Blocker (resolved / workaround)

- YouTube anti-bot/JS challenge (`n challenge solving failed`) → worked around with EJS (`--remote-components ejs:github`) + JS runtime
- YouTube cookies required depending on the video

## Test Video

- https://youtu.be/-os0lxDX0bU?si=rixXxr5PZFDa9-Hf

## Last E2E Test

- OK: dubbed MP4 generation + Azure Blob upload + SAS URL returned in stdout

## Next steps

1) Add EJS flags + cookie support (configurable) to the YouTube download in `run.js` so the E2E works "just with a URL"
2) Decide the default distribution strategy:
   - return a SAS URL (Blob) vs keep local file
3) Improve sync: currently using `-shortest` (no time-stretch / align)
4) Option: keep original audio as track 2
