#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import yargs from 'yargs/yargs';
import { hideBin } from 'yargs/helpers';
import { DefaultAzureCredential } from '@azure/identity';
import { BlobServiceClient, generateBlobSASQueryParameters, BlobSASPermissions, StorageSharedKeyCredential } from '@azure/storage-blob';

// Azure SDK is used for blob storage upload via Managed Identity (DefaultAzureCredential).
// For APIM calls we use direct HTTP fetch to match the exact APIM routes.

function mustGetEnv(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

function sh(cmd, args, { cwd } = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    p.stdout.on('data', (d) => (stdout += d.toString()));
    p.stderr.on('data', (d) => (stderr += d.toString()));
    p.on('error', reject);
    p.on('close', (code) => {
      if (code === 0) return resolve({ stdout, stderr });
      reject(new Error(`${cmd} exited ${code}\n${stderr || stdout}`));
    });
  });
}

async function fileExists(p) {
  try {
    await fs.promises.access(p, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function safeBasename(s) {
  return s.replace(/[^a-z0-9._-]+/gi, '_').slice(0, 80);
}

const argv = yargs(hideBin(process.argv))
  .scriptName('yt_fr_dub')
  .usage('$0 <youtubeUrl> [options]')
  .positional('youtubeUrl', { describe: 'YouTube URL', type: 'string', demandOption: true })
  .option('input', { describe: 'Use a local MP4 as input (skip yt-dlp download). If set, youtubeUrl is only used for metadata/title when available.', type: 'string' })
  .option('cookies', { describe: 'Path to yt-dlp cookies.txt (default: ~/.openclaw/secrets/youtube_cookies.txt)', type: 'string', default: path.join(os.homedir(), '.openclaw', 'secrets', 'youtube_cookies.txt') })
  .option('ytdlpNode', { describe: 'Path to node runtime for yt-dlp JS challenges', type: 'string', default: '/usr/bin/node' })
  .option('ytdlpEjs', { describe: 'Enable EJS remote components for yt-dlp (recommended)', type: 'boolean', default: true })
  .option('out', { describe: 'Output MP4 path', type: 'string', default: 'out/french_dub.mp4' })
  .option('workdir', { describe: 'Working directory (temp if omitted)', type: 'string' })
  .option('maxMinutes', { describe: 'Max duration in minutes', type: 'number', default: 20 })
  .option('voice', { describe: 'TTS voice name. For Azure Speech, use e.g. fr-FR-DeniseNeural', type: 'string', default: 'fr-FR-DeniseNeural' })
  .option('targetLoudnessDb', { describe: 'Normalize synthesized audio loudness (dB)', type: 'number', default: -16 })
  .option('blobUpload', { describe: 'Upload resulting MP4 to Azure Blob and print a SAS URL (uses Managed Identity via Azure SDK)', type: 'boolean', default: true })
  .option('blobAccount', { describe: 'Azure Storage account name', type: 'string', default: process.env.BLOB_ACCOUNT || 'stopenclawmedia' })
  .option('blobContainer', { describe: 'Azure Storage container name', type: 'string', default: process.env.BLOB_CONTAINER || 'media' })
  .option('blobName', { describe: 'Blob name (default: output filename)', type: 'string' })
  .option('blobSasDays', { describe: 'SAS validity in days', type: 'number', default: Number(process.env.BLOB_SAS_DAYS || 7) })
  .help()
  .parse();

const youtubeUrl = argv._[0];

const apimEndpoint = process.env.APIM_OPENAI_ENDPOINT || 'https://apim-openclaw-0974.azure-api.net';
// Prefer env; fallback is kept for local dev but should not be committed with real secrets
const apimApiKey = process.env.APIM_OPENAI_API_KEY || 'f912e4b174d645aabe927e80f9992ff6';
const apiVersion = process.env.APIM_OPENAI_API_VERSION || '2024-10-21';
// Azure Speech TTS (via APIM) settings
const speechTtsEndpoint = process.env.SPEECH_TTS_ENDPOINT || `${apimEndpoint.replace(/\/$/, '')}/speech/cognitiveservices/v1`;
const speechTtsOutputFormat = process.env.SPEECH_TTS_OUTPUT_FORMAT || 'audio-16khz-128kbitrate-mono-mp3';
const speechTtsVoice = process.env.SPEECH_TTS_VOICE || 'fr-FR-DeniseNeural';
const speechTtsLang = process.env.SPEECH_TTS_LANG || 'fr-FR';

// APIM routes: /openai/deployments/<deployment>/...
const deploymentTranscribe = process.env.APIM_OPENAI_DEPLOYMENT_TRANSCRIBE || 'gpt-4o-transcribe';
const deploymentTranslate = process.env.APIM_OPENAI_DEPLOYMENT_TRANSLATE || 'gpt-5.2';
const deploymentTts = process.env.APIM_OPENAI_DEPLOYMENT_TTS || 'gpt-4o-audio-preview';

const apimBase = apimEndpoint.replace(/\/$/, '');

async function apimPost(pathname, body) {
  const url = `${apimBase}${pathname}?api-version=${encodeURIComponent(apiVersion)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'api-key': apimApiKey,
      'content-type': 'application/json'
    },
    body: JSON.stringify(body)
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`APIM ${res.status} for ${pathname}: ${text.slice(0, 500)}`);
  }
  return text ? JSON.parse(text) : {};
}

async function apimChatTranslateToFrench(transcript) {
  const prompt = [
    'Translate the following transcript to French for spoken narration.',
    'Requirements:',
    '- Natural, conversational French.',
    '- Keep meaning faithful; do not add content.',
    '- Keep numbers, names, and technical terms accurate.',
    '- Output ONLY the French text (no quotes, no preface).',
    '',
    transcript
  ].join('\n');

  const data = await apimPost(`/openai/deployments/${deploymentTranslate}/chat/completions`, {
    messages: [
      { role: 'system', content: 'You are a professional translator for French voiceover scripts.' },
      { role: 'user', content: prompt }
    ],
    temperature: 0.2,
    // Azure/APIM for gpt-5.2 expects max_completion_tokens
    max_completion_tokens: 8192
  });

  const fr = data?.choices?.[0]?.message?.content?.trim?.() || data?.choices?.[0]?.text?.trim?.() || '';
  return fr;
}

async function apimTranscribeAudioMp4(audioPath) {
  // Azure OpenAI transcriptions endpoint expects multipart/form-data. We'll use curl for simplicity/reliability.
  // Note: file is audio/mp4 (m4a). response_format=text.
  const url = `${apimBase}/openai/deployments/${deploymentTranscribe}/audio/transcriptions?api-version=${encodeURIComponent(apiVersion)}`;
  const { stdout } = await sh('curl', [
    '-sS',
    '-X', 'POST',
    '-H', `api-key: ${apimApiKey}`,
    '-F', `file=@${audioPath};type=audio/mp4`,
    '-F', 'response_format=text',
    '-F', `model=${deploymentTranscribe}`,
    url
  ]);
  return String(stdout || '').trim();
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

async function speechTtsToMp3(text, mp3OutPath, { voiceName = speechTtsVoice, lang = speechTtsLang } = {}) {
  const ssml = `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${lang}"><voice name="${voiceName}">${escapeXml(text)}</voice></speak>`;

  await sh('curl', [
    '-sS',
    '-X', 'POST',
    speechTtsEndpoint,
    '-H', `Ocp-Apim-Subscription-Key: ${apimApiKey}`,
    '-H', 'Content-Type: application/ssml+xml',
    '-H', `X-Microsoft-OutputFormat: ${speechTtsOutputFormat}`,
    '--data', ssml,
    '--output', mp3OutPath
  ]);
}

// Azure credential – uses Managed Identity on Azure VM, or az CLI locally as fallback.
const azureCredential = new DefaultAzureCredential();

async function main() {
  // Basic dependency checks
  // Note: yt-dlp uses --version (not -version).
  for (const [bin, args] of [
    ['yt-dlp', ['--version']],
    ['ffmpeg', ['-version']],
    ['ffprobe', ['-version']],
    ['curl', ['--version']]
  ]) {
    try {
      await sh(bin, args);
    } catch (e) {
      throw new Error(`Missing dependency '${bin}' or not executable. Install and ensure it's on PATH.\n${e.message}`);
    }
  }

  const jobId = crypto.randomBytes(6).toString('hex');
  const workdir = argv.workdir
    ? path.resolve(argv.workdir)
    : await fs.promises.mkdtemp(path.join(os.tmpdir(), `yt-fr-dub-${jobId}-`));

  await fs.promises.mkdir(workdir, { recursive: true });
  await fs.promises.mkdir(path.dirname(path.resolve(argv.out)), { recursive: true });

  const infoJson = path.join(workdir, 'info.json');

  let durationSec = null;
  let title = 'youtube_video';

  // Build yt-dlp args (cookies + JS challenge support)
  const ytdlpCommon = ['--no-warnings', '--no-playlist'];
  if (argv.cookies && (await fileExists(path.resolve(argv.cookies)))) {
    ytdlpCommon.push('--cookies', path.resolve(argv.cookies));
  }
  // JS challenge solving (YouTube)
  if (argv.ytdlpNode) {
    ytdlpCommon.push('--no-js-runtimes', '--js-runtimes', `node:${argv.ytdlpNode}`);
  }
  if (argv.ytdlpEjs) {
    ytdlpCommon.push('--remote-components', 'ejs:github');
  }

  // 1) Get metadata incl duration
  if (!argv.input) {
    await sh('yt-dlp', ['--dump-single-json', ...ytdlpCommon, youtubeUrl], { cwd: workdir })
      .then(async ({ stdout }) => {
        await fs.promises.writeFile(infoJson, stdout);
      });

    const info = JSON.parse(await fs.promises.readFile(infoJson, 'utf8'));
    durationSec = info.duration ?? null;
    title = info.title ?? title;
    if (!durationSec) throw new Error('Could not determine video duration.');
  } else {
    // Local input: derive duration via ffprobe
    const inputPath = path.resolve(argv.input);
    if (!(await fileExists(inputPath))) throw new Error(`Input file not found: ${inputPath}`);

    const { stdout } = await sh('ffprobe', [
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=nw=1:nk=1',
      inputPath
    ], { cwd: workdir });

    durationSec = Number.parseFloat(String(stdout).trim());
    if (!Number.isFinite(durationSec) || durationSec <= 0) throw new Error('Could not determine input video duration (ffprobe).');

    // Keep a stable name for artifacts
    title = path.basename(inputPath, path.extname(inputPath));
  }

  if (durationSec > argv.maxMinutes * 60) {
    throw new Error(`Video too long: ${Math.round(durationSec / 60)} min (max ${argv.maxMinutes} min)`);
  }

  const base = safeBasename(title);
  const videoPath = path.join(workdir, `${base}.video.mp4`);
  const audioPath = path.join(workdir, `${base}.audio.m4a`);

  // 2) Acquire video+audio
  if (argv.input) {
    const inputPath = path.resolve(argv.input);
    if (!(await fileExists(videoPath))) {
      await fs.promises.copyFile(inputPath, videoPath);
    }
    if (!(await fileExists(audioPath))) {
      await sh('ffmpeg', ['-y', '-i', videoPath, '-vn', '-c:a', 'aac', '-b:a', '192k', audioPath], { cwd: workdir });
    }
  } else {
    // Download best video-only mp4 + best audio
    if (!(await fileExists(videoPath))) {
      await sh('yt-dlp', [
        '-f', 'bv*[ext=mp4]/bv*',
        '-o', videoPath,
        ...ytdlpCommon,
        youtubeUrl
      ], { cwd: workdir });
    }

    if (!(await fileExists(audioPath))) {
      await sh('yt-dlp', [
        '-f', 'ba[ext=m4a]/ba',
        '-o', audioPath,
        ...ytdlpCommon,
        youtubeUrl
      ], { cwd: workdir });
    }
  }

  // 3) Transcribe
  const transcriptPath = path.join(workdir, `${base}.transcript.txt`);
  let transcript;
  if (await fileExists(transcriptPath)) {
    transcript = await fs.promises.readFile(transcriptPath, 'utf8');
  } else {
    transcript = await apimTranscribeAudioMp4(audioPath);
    if (!transcript.trim()) throw new Error('Empty transcript returned.');
    await fs.promises.writeFile(transcriptPath, transcript);
  }

  // 4) Translate to French
  const frTextPath = path.join(workdir, `${base}.fr.txt`);
  let frText;
  if (await fileExists(frTextPath)) {
    frText = await fs.promises.readFile(frTextPath, 'utf8');
  } else {
    frText = await apimChatTranslateToFrench(transcript);
    if (!frText) throw new Error('Empty French translation returned.');
    await fs.promises.writeFile(frTextPath, frText);
  }

  // 5) TTS synthesize (Azure Speech via APIM)
  const ttsMp3Path = path.join(workdir, `${base}.fr.mp3`);
  if (!(await fileExists(ttsMp3Path))) {
    await speechTtsToMp3(frText, ttsMp3Path, {
      // If user passes --voice, prefer it as a Speech voice name; otherwise default.
      voiceName: argv.voice || speechTtsVoice,
      lang: speechTtsLang
    });
    if (!(await fileExists(ttsMp3Path))) throw new Error('TTS did not produce an MP3 file.');
  }

  // Decode to WAV then normalize loudness
  const ttsWavPath = path.join(workdir, `${base}.fr.wav`);
  await sh('ffmpeg', ['-y', '-i', ttsMp3Path, ttsWavPath], { cwd: workdir });

  const ttsNormPath = path.join(workdir, `${base}.fr.norm.wav`);
  await sh('ffmpeg', [
    '-y',
    '-i', ttsWavPath,
    '-af', `loudnorm=I=${argv.targetLoudnessDb}:TP=-1.5:LRA=11`,
    ttsNormPath
  ], { cwd: workdir });

  // Encode to AAC for MP4 container
  const ttsAacPath = path.join(workdir, `${base}.fr.m4a`);
  await sh('ffmpeg', [
    '-y',
    '-i', ttsNormPath,
    '-c:a', 'aac',
    '-b:a', '192k',
    ttsAacPath
  ], { cwd: workdir });

  // 6) Remux: replace audio
  const outPath = path.resolve(argv.out);
  await sh('ffmpeg', [
    '-y',
    '-i', videoPath,
    '-i', ttsAacPath,
    '-map', '0:v:0',
    '-map', '1:a:0',
    '-c:v', 'copy',
    '-c:a', 'aac',
    '-shortest',
    outPath
  ], { cwd: workdir });

  // Optionally upload to Azure Blob and print SAS URL (uses Managed Identity via SDK)
  if (argv.blobUpload) {
    const blobName = argv.blobName || path.basename(outPath);
    const accountUrl = `https://${argv.blobAccount}.blob.core.windows.net`;

    // Create BlobServiceClient with Managed Identity credential
    const blobService = new BlobServiceClient(accountUrl, azureCredential);
    const containerClient = blobService.getContainerClient(argv.blobContainer);
    const blockBlobClient = containerClient.getBlockBlobClient(blobName);

    // Upload the MP4 file
    console.error(`Uploading ${outPath} -> ${accountUrl}/${argv.blobContainer}/${blobName} ...`);
    await blockBlobClient.uploadFile(outPath, {
      blobHTTPHeaders: { blobContentType: 'video/mp4' },
      overwrite: true
    });
    console.error('Upload complete.');

    // Generate User-Delegation SAS (read-only) via Managed Identity
    const startsOn = new Date();
    const expiresOn = new Date(Date.now() + argv.blobSasDays * 24 * 60 * 60 * 1000);
    const delegationKey = await blobService.getUserDelegationKey(startsOn, expiresOn);

    const sasToken = generateBlobSASQueryParameters({
      containerName: argv.blobContainer,
      blobName,
      permissions: BlobSASPermissions.parse('r'),
      startsOn,
      expiresOn
    }, delegationKey, argv.blobAccount).toString();

    const sasUrl = `${blockBlobClient.url}?${sasToken}`;
    // Emit as a MEDIA token so OpenClaw attaches the URL (no Telegram upload).
    process.stdout.write(`MEDIA: ${sasUrl}\n`);
    return;
  }

  // Print output path (handy for OpenClaw)
  process.stdout.write(outPath + '\n');
}

main().catch((err) => {
  console.error(err?.stack || err?.message || String(err));
  process.exit(1);
});
