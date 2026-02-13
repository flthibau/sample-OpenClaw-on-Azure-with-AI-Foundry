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
  .option('voice', { describe: 'TTS voice name override. If omitted, auto-detects male/female from transcript. e.g. fr-FR-DeniseNeural (female) or fr-FR-HenriNeural (male)', type: 'string' })
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
const speechTtsVoiceFemale = process.env.SPEECH_TTS_VOICE_FEMALE || 'fr-FR-DeniseNeural';
const speechTtsVoiceMale = process.env.SPEECH_TTS_VOICE_MALE || 'fr-FR-HenriNeural';
const speechTtsVoice = process.env.SPEECH_TTS_VOICE || 'fr-FR-DeniseNeural'; // default fallback
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

// Detect speaker gender from transcript content using LLM
async function detectSpeakerGender(transcriptSample) {
  const prompt = [
    'Analyze the following transcript excerpt and determine the gender of the main speaker.',
    'Look for clues such as: self-references ("I\'m a guy", "as a woman"), name mentions,',
    'gendered language, context, and speaking style.',
    'Respond with EXACTLY one word: "male" or "female".',
    'If uncertain, respond "male".',
    '',
    transcriptSample.slice(0, 3000)
  ].join('\n');

  const data = await apimPost(`/openai/deployments/${deploymentTranslate}/chat/completions`, {
    messages: [
      { role: 'system', content: 'You are a gender detection assistant. You analyze transcripts and output exactly one word: male or female.' },
      { role: 'user', content: prompt }
    ],
    temperature: 0,
    max_completion_tokens: 10
  });

  const answer = (data?.choices?.[0]?.message?.content?.trim?.() || 'male').toLowerCase();
  return answer.includes('female') ? 'female' : 'male';
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

// --- TTS chunking helpers ---
// Azure Speech REST API has a ~10 000 char / 64 KB SSML body limit per request.
// For long texts we split at sentence boundaries and concatenate the resulting MP3s.
const TTS_CHUNK_MAX_CHARS = 8000; // Conservative limit (leaves room for SSML wrapper + XML escaping)

function splitTextIntoChunks(text, maxChars = TTS_CHUNK_MAX_CHARS) {
  if (text.length <= maxChars) return [text];

  const chunks = [];
  let remaining = text;

  while (remaining.length > 0) {
    if (remaining.length <= maxChars) {
      chunks.push(remaining);
      break;
    }

    // Search backwards from maxChars for a sentence-ending boundary
    const searchRegion = remaining.slice(0, maxChars);
    let splitAt = -1;

    for (const sep of ['. ', '! ', '? ', '.\n', '!\n', '?\n', '\n']) {
      const idx = searchRegion.lastIndexOf(sep);
      if (idx > maxChars * 0.3) { // keep at least 30 % usage per chunk
        splitAt = idx + sep.length;
        break;
      }
    }

    // Fallback: split at last space
    if (splitAt === -1) {
      const lastSpace = searchRegion.lastIndexOf(' ');
      splitAt = lastSpace > maxChars * 0.3 ? lastSpace + 1 : maxChars;
    }

    chunks.push(remaining.slice(0, splitAt).trim());
    remaining = remaining.slice(splitAt).trim();
  }

  return chunks.filter(c => c.length > 0);
}

// Synthesize a single chunk via Azure Speech REST API (curl)
async function speechTtsSingleChunk(text, mp3OutPath, { voiceName = speechTtsVoice, lang = speechTtsLang } = {}) {
  const ssml = `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${lang}"><voice name="${voiceName}">${escapeXml(text)}</voice></speak>`;

  await sh('curl', [
    '-sS',
    '--max-time', '300',
    '-X', 'POST',
    speechTtsEndpoint,
    '-H', `Ocp-Apim-Subscription-Key: ${apimApiKey}`,
    '-H', 'Content-Type: application/ssml+xml',
    '-H', `X-Microsoft-OutputFormat: ${speechTtsOutputFormat}`,
    '--data', ssml,
    '--output', mp3OutPath
  ]);
}

// High-level TTS: auto-splits long text into chunks, synthesizes each, and
// concatenates the resulting MP3 files seamlessly with ffmpeg.
async function speechTtsToMp3(text, mp3OutPath, { voiceName = speechTtsVoice, lang = speechTtsLang, workdir } = {}) {
  const chunks = splitTextIntoChunks(text);

  if (chunks.length === 1) {
    await speechTtsSingleChunk(chunks[0], mp3OutPath, { voiceName, lang });
    return;
  }

  console.error(`TTS: text is ${text.length} chars — splitting into ${chunks.length} chunks (limit ${TTS_CHUNK_MAX_CHARS} chars/chunk).`);

  const chunkMp3s = [];
  for (let i = 0; i < chunks.length; i++) {
    const chunkPath = mp3OutPath.replace(/\.mp3$/, `.chunk${String(i).padStart(3, '0')}.mp3`);
    console.error(`  TTS chunk ${i + 1}/${chunks.length} (${chunks[i].length} chars) …`);
    await speechTtsSingleChunk(chunks[i], chunkPath, { voiceName, lang });

    if (!(await fileExists(chunkPath))) {
      throw new Error(`TTS chunk ${i + 1}/${chunks.length} did not produce an MP3 file.`);
    }
    // Verify the file is not a JSON/XML error response disguised as MP3
    const stat = await fs.promises.stat(chunkPath);
    if (stat.size < 1024) {
      const probe = await fs.promises.readFile(chunkPath, 'utf8').catch(() => '');
      if (probe.includes('<') || probe.includes('{')) {
        throw new Error(`TTS chunk ${i + 1} returned an error instead of audio: ${probe.slice(0, 300)}`);
      }
    }
    chunkMp3s.push(chunkPath);
  }

  // Concatenate chunks with ffmpeg concat demuxer (lossless for same-format MP3s)
  const concatListPath = mp3OutPath.replace(/\.mp3$/, '.concat.txt');
  await fs.promises.writeFile(concatListPath, chunkMp3s.map(p => `file '${p}'`).join('\n'));

  const cwd = workdir || path.dirname(mp3OutPath);
  await sh('ffmpeg', [
    '-y',
    '-f', 'concat',
    '-safe', '0',
    '-i', concatListPath,
    '-c', 'copy',
    mp3OutPath
  ], { cwd });

  console.error(`TTS: concatenated ${chunks.length} chunks → ${path.basename(mp3OutPath)}`);
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

  // =====================================================================
  // SEGMENT-BASED PIPELINE
  // Instead of translating/synthesizing the entire text at once (which
  // produces audio that doesn't match the video pacing), we:
  //   3a) Detect silence boundaries in the original audio
  //   3b) Split audio into segments at those boundaries
  //   3c) Transcribe each segment individually
  //   4)  Translate all segments (batch, preserving structure)
  //   5)  TTS each translated segment
  //   5b) Speed-adjust each TTS segment to fit its time slot
  //   5c) Assemble all segments into a single audio track
  // =====================================================================

  const segmentsDir = path.join(workdir, 'segments');
  await fs.promises.mkdir(segmentsDir, { recursive: true });

  // 3a) Detect silence boundaries
  const silencesPath = path.join(workdir, `${base}.silences.json`);
  let segmentBoundaries; // array of { start, end } in seconds

  if (await fileExists(silencesPath)) {
    segmentBoundaries = JSON.parse(await fs.promises.readFile(silencesPath, 'utf8'));
    console.error(`Loaded ${segmentBoundaries.length} cached segments.`);
  } else {
    console.error('Detecting silence boundaries in original audio…');
    const { stderr: silenceOut } = await sh('ffmpeg', [
      '-i', audioPath,
      '-af', 'silencedetect=n=-25dB:d=0.3',
      '-f', 'null', '-'
    ], { cwd: workdir });

    // Parse silence_end lines: "silence_end: 36.5857 | silence_duration: 0.395941"
    const silenceEnds = [];
    for (const line of silenceOut.split('\n')) {
      const m = line.match(/silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)/);
      if (m) {
        const end = parseFloat(m[1]);
        const dur = parseFloat(m[2]);
        silenceEnds.push({ silenceStart: end - dur, silenceEnd: end });
      }
    }

    // Build segments of ~30-60s by picking silence gaps as cut points
    const TARGET_SEG_SEC = 40;
    const MIN_SEG_SEC = 15;
    segmentBoundaries = [];
    let segStart = 0;

    for (const s of silenceEnds) {
      const elapsed = s.silenceStart - segStart;
      if (elapsed >= TARGET_SEG_SEC) {
        // Cut at the middle of this silence gap
        const cutPoint = (s.silenceStart + s.silenceEnd) / 2;
        segmentBoundaries.push({ start: segStart, end: cutPoint });
        segStart = cutPoint;
      }
    }
    // Last segment
    if (segStart < durationSec - 1) {
      segmentBoundaries.push({ start: segStart, end: durationSec });
    }

    // Merge any very short trailing segment into the previous one
    if (segmentBoundaries.length > 1) {
      const last = segmentBoundaries[segmentBoundaries.length - 1];
      if ((last.end - last.start) < MIN_SEG_SEC) {
        segmentBoundaries[segmentBoundaries.length - 2].end = last.end;
        segmentBoundaries.pop();
      }
    }

    await fs.promises.writeFile(silencesPath, JSON.stringify(segmentBoundaries, null, 2));
    console.error(`Created ${segmentBoundaries.length} segments (target ~${TARGET_SEG_SEC}s each).`);
  }

  // 3b) Split audio into segment files
  for (let i = 0; i < segmentBoundaries.length; i++) {
    const seg = segmentBoundaries[i];
    const segAudioPath = path.join(segmentsDir, `seg_${String(i).padStart(3, '0')}.m4a`);
    seg._audioPath = segAudioPath;
    if (!(await fileExists(segAudioPath))) {
      await sh('ffmpeg', [
        '-y', '-i', audioPath,
        '-ss', String(seg.start),
        '-to', String(seg.end),
        '-c:a', 'aac', '-b:a', '192k',
        segAudioPath
      ], { cwd: workdir });
    }
  }
  console.error(`Split audio into ${segmentBoundaries.length} segment files.`);

  // 3c) Transcribe each segment
  const segTranscriptsPath = path.join(workdir, `${base}.seg_transcripts.json`);
  let segTranscripts; // array of strings

  if (await fileExists(segTranscriptsPath)) {
    segTranscripts = JSON.parse(await fs.promises.readFile(segTranscriptsPath, 'utf8'));
    console.error(`Loaded ${segTranscripts.length} cached segment transcripts.`);
  } else {
    console.error(`Transcribing ${segmentBoundaries.length} segments…`);
    segTranscripts = [];
    for (let i = 0; i < segmentBoundaries.length; i++) {
      const seg = segmentBoundaries[i];
      console.error(`  Transcribing segment ${i + 1}/${segmentBoundaries.length} (${(seg.end - seg.start).toFixed(1)}s)…`);
      const txt = await apimTranscribeAudioMp4(seg._audioPath);
      segTranscripts.push(txt);
    }
    await fs.promises.writeFile(segTranscriptsPath, JSON.stringify(segTranscripts, null, 2));
    console.error('All segments transcribed.');
  }

  // 4) Translate all segments (structured, preserving segment boundaries)
  const segTranslationsPath = path.join(workdir, `${base}.seg_translations.json`);
  let segTranslations; // array of strings

  if (await fileExists(segTranslationsPath)) {
    segTranslations = JSON.parse(await fs.promises.readFile(segTranslationsPath, 'utf8'));
    console.error(`Loaded ${segTranslations.length} cached segment translations.`);
  } else {
    console.error(`Translating ${segTranscripts.length} segments to French…`);

    // Build a structured prompt that preserves segment boundaries
    const numberedSegments = segTranscripts.map((t, i) => `[SEGMENT ${i + 1}]\n${t}`).join('\n\n');
    const prompt = [
      `Translate the following ${segTranscripts.length} numbered transcript segments to French for spoken narration.`,
      'Requirements:',
      '- Natural, conversational French.',
      '- Keep meaning faithful; do not add or remove content.',
      '- Keep numbers, names, and technical terms accurate.',
      '- Preserve the EXACT segment structure: output each segment prefixed with [SEGMENT N].',
      '- Output ONLY the translated segments (no quotes, no preface, no explanation).',
      '',
      numberedSegments
    ].join('\n');

    const data = await apimPost(`/openai/deployments/${deploymentTranslate}/chat/completions`, {
      messages: [
        { role: 'system', content: 'You are a professional translator for French voiceover scripts. You preserve the exact segment structure given to you.' },
        { role: 'user', content: prompt }
      ],
      temperature: 0.2,
      max_completion_tokens: 16384
    });

    const rawFr = data?.choices?.[0]?.message?.content?.trim?.() || '';

    // Parse [SEGMENT N] blocks
    segTranslations = [];
    const segRegex = /\[SEGMENT\s+(\d+)\]\s*/gi;
    const parts = rawFr.split(segRegex);
    // parts: ['', '1', 'text1', '2', 'text2', ...]
    for (let j = 1; j < parts.length; j += 2) {
      segTranslations.push((parts[j + 1] || '').trim());
    }

    // Fallback: if parsing failed, try splitting by double newlines
    if (segTranslations.length < segTranscripts.length * 0.5) {
      console.error(`Warning: segment parsing recovered ${segTranslations.length}/${segTranscripts.length} segments. Falling back to paragraph split.`);
      segTranslations = rawFr.split(/\n\n+/).map(s => s.replace(/^\[SEGMENT\s*\d+\]\s*/i, '').trim()).filter(s => s.length > 0);
    }

    // If we still have fewer translations than segments, pad empty ones
    while (segTranslations.length < segTranscripts.length) {
      segTranslations.push('');
    }
    // Trim to match count
    segTranslations = segTranslations.slice(0, segTranscripts.length);

    await fs.promises.writeFile(segTranslationsPath, JSON.stringify(segTranslations, null, 2));
    console.error(`Translated ${segTranslations.length} segments.`);
  }

  // 4b) Auto-detect speaker gender and select appropriate TTS voice
  let selectedVoice = argv.voice || null; // user override takes priority
  if (!selectedVoice) {
    const genderCachePath = path.join(workdir, `${base}.speaker_gender.txt`);
    let gender;
    if (await fileExists(genderCachePath)) {
      gender = (await fs.promises.readFile(genderCachePath, 'utf8')).trim();
      console.error(`Loaded cached speaker gender: ${gender}`);
    } else {
      // Use first few non-empty transcripts for detection
      const sample = segTranscripts.filter(t => t.length > 20).slice(0, 5).join(' ');
      console.error('Detecting speaker gender…');
      gender = await detectSpeakerGender(sample);
      await fs.promises.writeFile(genderCachePath, gender);
      console.error(`Detected speaker gender: ${gender}`);
    }
    selectedVoice = gender === 'female' ? speechTtsVoiceFemale : speechTtsVoiceMale;
    console.error(`Auto-selected TTS voice: ${selectedVoice}`);
  } else {
    console.error(`Using user-specified TTS voice: ${selectedVoice}`);
  }

  // 5) TTS each translated segment + speed-adjust to fit time slot
  console.error(`Synthesizing and time-fitting ${segmentBoundaries.length} TTS segments…`);
  const fittedSegPaths = [];

  for (let i = 0; i < segmentBoundaries.length; i++) {
    const seg = segmentBoundaries[i];
    const segDuration = seg.end - seg.start;
    const frText = segTranslations[i];
    const prefix = `seg_${String(i).padStart(3, '0')}`;

    const segTtsMp3 = path.join(segmentsDir, `${prefix}.fr.mp3`);
    const segTtsWav = path.join(segmentsDir, `${prefix}.fr.wav`);
    const segFitted = path.join(segmentsDir, `${prefix}.fr.fitted.wav`);

    fittedSegPaths.push(segFitted);

    // Skip if already fitted
    if (await fileExists(segFitted)) continue;

    if (!frText || frText.length < 2) {
      // Empty segment → generate silence for its duration
      console.error(`  Segment ${i + 1}: empty text → ${segDuration.toFixed(1)}s silence`);
      await sh('ffmpeg', [
        '-y', '-f', 'lavfi', '-i', `anullsrc=r=16000:cl=mono`,
        '-t', String(segDuration),
        '-c:a', 'pcm_s16le',
        segFitted
      ], { cwd: workdir });
      continue;
    }

    // TTS (with chunking for safety)
    if (!(await fileExists(segTtsMp3))) {
      await speechTtsToMp3(frText, segTtsMp3, {
        voiceName: selectedVoice,
        lang: speechTtsLang,
        workdir: segmentsDir
      });
    }

    // Decode to WAV
    if (!(await fileExists(segTtsWav))) {
      await sh('ffmpeg', ['-y', '-i', segTtsMp3, segTtsWav], { cwd: workdir });
    }

    // Measure TTS duration
    const { stdout: durOut } = await sh('ffprobe', [
      '-v', 'error', '-show_entries', 'format=duration',
      '-of', 'default=nw=1:nk=1', segTtsWav
    ]);
    const ttsDur = parseFloat(String(durOut).trim());

    if (!Number.isFinite(ttsDur) || ttsDur <= 0) {
      console.error(`  Segment ${i + 1}: invalid TTS duration → silence`);
      await sh('ffmpeg', [
        '-y', '-f', 'lavfi', '-i', 'anullsrc=r=16000:cl=mono',
        '-t', String(segDuration), '-c:a', 'pcm_s16le', segFitted
      ], { cwd: workdir });
      continue;
    }

    // Speed-adjust to fit in the original time slot
    const ratio = ttsDur / segDuration;
    if (ratio > 1.05 || ratio < 0.7) {
      // Need speed adjustment — clamp to [0.5, 2.0] range with chaining
      const clamped = Math.max(0.5, Math.min(2.0, ratio));
      const tempoFilters = [];
      let rem = ratio;
      while (rem > 2.0) { tempoFilters.push('atempo=2.0'); rem /= 2.0; }
      while (rem < 0.5) { tempoFilters.push('atempo=0.5'); rem /= 0.5; }
      tempoFilters.push(`atempo=${rem.toFixed(4)}`);
      const chain = tempoFilters.join(',');

      console.error(`  Segment ${i + 1}: ${ttsDur.toFixed(1)}s → ${segDuration.toFixed(1)}s (atempo ${ratio.toFixed(3)}, ${chain})`);

      // Speed-adjust then pad/trim to exact duration
      const segTmp = path.join(segmentsDir, `${prefix}.fr.tempo.wav`);
      await sh('ffmpeg', [
        '-y', '-i', segTtsWav,
        '-af', chain,
        '-c:a', 'pcm_s16le',
        segTmp
      ], { cwd: workdir });

      // Pad with silence if shorter, or trim if still slightly longer
      await sh('ffmpeg', [
        '-y', '-i', segTmp,
        '-af', `apad=whole_dur=${segDuration.toFixed(3)}`,
        '-t', String(segDuration.toFixed(3)),
        '-c:a', 'pcm_s16le',
        segFitted
      ], { cwd: workdir });
    } else {
      // Close enough — just pad/trim to exact duration
      console.error(`  Segment ${i + 1}: ${ttsDur.toFixed(1)}s ≈ ${segDuration.toFixed(1)}s (no speed change)`);
      await sh('ffmpeg', [
        '-y', '-i', segTtsWav,
        '-af', `apad=whole_dur=${segDuration.toFixed(3)}`,
        '-t', String(segDuration.toFixed(3)),
        '-c:a', 'pcm_s16le',
        segFitted
      ], { cwd: workdir });
    }
  }

  // 5c) Concatenate all fitted segments → final TTS audio
  const concatListPath = path.join(workdir, `${base}.seg_concat.txt`);
  await fs.promises.writeFile(
    concatListPath,
    fittedSegPaths.map(p => `file '${p}'`).join('\n')
  );

  const ttsAssembledWav = path.join(workdir, `${base}.fr.assembled.wav`);
  await sh('ffmpeg', [
    '-y', '-f', 'concat', '-safe', '0',
    '-i', concatListPath,
    '-c:a', 'pcm_s16le',
    ttsAssembledWav
  ], { cwd: workdir });

  // Normalize loudness on assembled audio
  const ttsNormPath = path.join(workdir, `${base}.fr.norm.wav`);
  await sh('ffmpeg', [
    '-y', '-i', ttsAssembledWav,
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
