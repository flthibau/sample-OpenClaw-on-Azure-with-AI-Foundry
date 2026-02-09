# Setup notes (OpenClaw)

## Dependencies

This skill depends on:

- `ffmpeg` (also provides `ffprobe`)
- `yt-dlp`

Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg python3-pip
python3 -m pip install -U yt-dlp
```

## Node dependencies

From workspace root:

```bash
cd skills/yt_fr_dub
npm install
```

## Environment variables

```bash
export AZURE_OPENAI_ENDPOINT="https://<your-aoai-resource>.openai.azure.com/"
export AZURE_OPENAI_API_KEY="..."
export AZURE_OPENAI_API_VERSION="2024-10-01-preview"

# optional (defaults shown)
export AZURE_OPENAI_DEPLOYMENT_TRANSCRIBE="gpt-4o-transcribe"
export AZURE_OPENAI_DEPLOYMENT_TRANSLATE="gpt-5.2"
export AZURE_OPENAI_DEPLOYMENT_TTS="gpt-4o-audio-preview"
```

## OpenClaw exec allowlist

If your OpenClaw runtime restricts process execution, allow:

- `yt-dlp`
- `ffmpeg`
- `ffprobe`

If it is a pattern allowlist, permit:

- `yt-dlp *`
- `ffmpeg *`
- `ffprobe *`

## Run

```bash
node skills/yt_fr_dub/run.js "https://www.youtube.com/watch?v=..." --out out/french.mp4
```

## Output

The script prints the absolute output path to stdout on success.
