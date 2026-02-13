#!/usr/bin/env node
/**
 * twitter-reader — Read Twitter/X timelines and tweets without API keys.
 *
 * Uses two free, no-auth endpoints:
 *   1. Twitter Syndication API  — timeline HTML → parsed tweets
 *   2. FxTwitter API            — single-tweet JSON + user profiles
 *
 * Usage:
 *   node run.js --user <handle>              # latest tweets from @handle
 *   node run.js --user <handle> --count 5    # last 5 tweets
 *   node run.js --tweet <tweet_id_or_url>    # single tweet detail
 *   node run.js --search <query>             # search via web_search fallback
 *   node run.js --profile <handle>           # user profile info
 */

import { parseArgs } from "node:util";

/* ───────────────────────── CLI args ───────────────────────── */

const { values: args } = parseArgs({
  options: {
    user:    { type: "string", short: "u" },
    tweet:   { type: "string", short: "t" },
    search:  { type: "string", short: "s" },
    profile: { type: "string", short: "p" },
    count:   { type: "string", short: "n", default: "10" },
    format:  { type: "string", short: "f", default: "text" }, // text | json
  },
  strict: false,
});

const MAX_TWEETS = Math.min(parseInt(args.count, 10) || 10, 50);
const UA = "Mozilla/5.0 (compatible; OpenClawBot/1.0)";

/* ───────────────────────── helpers ───────────────────────── */

async function fetchJSON(url, opts = {}) {
  const res = await fetch(url, {
    headers: { "User-Agent": UA, ...opts.headers },
    signal: AbortSignal.timeout(15_000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${url}`);
  return res.json();
}

async function fetchText(url) {
  const res = await fetch(url, {
    headers: { "User-Agent": UA },
    signal: AbortSignal.timeout(15_000),
  });
  if (res.status === 429) throw new Error(`Rate limited (429) — try again in a minute. URL: ${url}`);
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${url}`);
  return res.text();
}

function cleanHandle(h) {
  return h.replace(/^@/, "").replace(/^https?:\/\/(x|twitter)\.com\//, "").split("/")[0].trim();
}

function extractTweetId(input) {
  // Accept full URL or raw ID
  const m = input.match(/status\/(\d+)/);
  if (m) return m[1];
  if (/^\d+$/.test(input.trim())) return input.trim();
  throw new Error(`Cannot parse tweet ID from: ${input}`);
}

function decodeUnicode(str) {
  try { return str.replace(/\\u[\dA-Fa-f]{4}/g, m => String.fromCharCode(parseInt(m.slice(2), 16))); }
  catch { return str; }
}

/* ───────── Twitter Syndication (timeline, no auth) ──────── */

async function getTimeline(handle, count) {
  const url = `https://syndication.twitter.com/srv/timeline-profile/screen-name/${cleanHandle(handle)}`;
  const html = await fetchText(url);

  // Extract tweets from embedded data in the HTML
  const textMatches = [...html.matchAll(/"text":"((?:[^"\\]|\\.){5,})"/g)];
  const dateMatches = [...html.matchAll(/"created_at":"([^"]+)"/g)];
  const idMatches   = [...html.matchAll(/"id_str":"(\d+)"/g)];
  const likeMatches = [...html.matchAll(/"favorite_count":(\d+)/g)];
  const rtMatches   = [...html.matchAll(/"retweet_count":(\d+)/g)];

  const tweets = [];
  for (let i = 0; i < Math.min(textMatches.length, count); i++) {
    const text = decodeUnicode(textMatches[i][1]);
    // Skip very short entries that are just URLs or metadata
    if (text.length < 5) continue;

    tweets.push({
      id:        idMatches[i]?.[1] ?? null,
      date:      dateMatches[i]?.[1] ?? null,
      text:      text,
      likes:     parseInt(likeMatches[i]?.[1] ?? "0", 10),
      retweets:  parseInt(rtMatches[i]?.[1] ?? "0", 10),
      url:       idMatches[i]?.[1] ? `https://x.com/${cleanHandle(handle)}/status/${idMatches[i][1]}` : null,
    });
  }

  return { handle: cleanHandle(handle), count: tweets.length, tweets };
}

/* ───────── FxTwitter API (single tweet, user profile) ───── */

async function getTweet(tweetInput) {
  const id = extractTweetId(tweetInput);
  // Extract username from URL if present, otherwise use /x/ as wildcard
  const userMatch = tweetInput.match(/(?:x|twitter)\.com\/([^/]+)\/status/);
  const user = userMatch ? userMatch[1] : "x";
  const url = `https://api.fxtwitter.com/${user}/status/${id}`;
  const data = await fetchJSON(url);

  if (data.code !== 200) throw new Error(data.message || "Tweet not found");

  const t = data.tweet;
  return {
    id:       t.id,
    author:   `@${t.author?.screen_name ?? "unknown"}`,
    name:     t.author?.name ?? "",
    date:     t.created_at,
    text:     t.text,
    likes:    t.likes ?? 0,
    retweets: t.retweets ?? 0,
    replies:  t.replies ?? 0,
    quotes:   t.quotes ?? 0,
    views:    t.views ?? 0,
    media:    (t.media?.all ?? []).map(m => ({ type: m.type, url: m.url })),
    url:      t.url,
  };
}

async function getProfile(handle) {
  const h = cleanHandle(handle);
  const data = await fetchJSON(`https://api.fxtwitter.com/${h}`);
  if (data.code !== 200) throw new Error(data.message || "User not found");

  const u = data.user;
  return {
    handle:      `@${u.screen_name}`,
    name:        u.name,
    description: u.description,
    followers:   u.followers,
    following:   u.following,
    tweets:      u.tweets,
    likes:       u.likes,
    joined:      u.joined,
    verified:    u.verification?.verified ?? false,
    avatar:      u.avatar_url,
    url:         `https://x.com/${u.screen_name}`,
    website:     u.website?.url ?? null,
  };
}

/* ───────────────────────── output ──────────────────────── */

function formatTimeline(data) {
  if (args.format === "json") return JSON.stringify(data, null, 2);

  let out = `📱 @${data.handle} — ${data.count} recent tweets\n${"─".repeat(50)}\n`;
  for (const t of data.tweets) {
    const date = t.date ? new Date(t.date).toLocaleDateString("fr-FR", { day: "numeric", month: "short", year: "numeric" }) : "";
    out += `\n${date}  ❤️ ${t.likes}  🔄 ${t.retweets}\n`;
    out += `${t.text}\n`;
    if (t.url) out += `🔗 ${t.url}\n`;
    out += `${"─".repeat(50)}\n`;
  }
  return out;
}

function formatTweet(t) {
  if (args.format === "json") return JSON.stringify(t, null, 2);

  let out = `📱 ${t.author} (${t.name})\n`;
  out += `📅 ${t.date}\n\n`;
  out += `${t.text}\n\n`;
  out += `❤️ ${t.likes}  🔄 ${t.retweets}  💬 ${t.replies}  👁️ ${t.views}\n`;
  if (t.media?.length) out += `📎 ${t.media.length} media: ${t.media.map(m => m.url).join(", ")}\n`;
  out += `🔗 ${t.url}\n`;
  return out;
}

function formatProfile(p) {
  if (args.format === "json") return JSON.stringify(p, null, 2);

  return `👤 ${p.name} (${p.handle}) ${p.verified ? "✅" : ""}
📝 ${p.description}
👥 ${p.followers.toLocaleString()} followers | ${p.following.toLocaleString()} following
📊 ${p.tweets.toLocaleString()} tweets | ❤️ ${p.likes.toLocaleString()} likes
📅 Joined ${p.joined}
${p.website ? `🌐 ${p.website}` : ""}
🔗 ${p.url}`;
}

/* ───────────────────────── main ───────────────────────── */

async function main() {
  try {
    if (args.user) {
      const data = await getTimeline(args.user, MAX_TWEETS);
      console.log(formatTimeline(data));
    } else if (args.tweet) {
      const data = await getTweet(args.tweet);
      console.log(formatTweet(data));
    } else if (args.profile) {
      const data = await getProfile(args.profile);
      console.log(formatProfile(data));
    } else if (args.search) {
      // For search, we output a hint that web_search should be used
      console.log(`🔍 Twitter search is best done via web_search tool.`);
      console.log(`Suggested query: "site:x.com ${args.search}"`);
      console.log(`Or: "${args.search} twitter"`);
    } else {
      console.error("Usage: node run.js --user <handle> | --tweet <id_or_url> | --profile <handle> | --search <query>");
      process.exit(1);
    }
  } catch (err) {
    console.error(`❌ Error: ${err.message}`);
    process.exit(1);
  }
}

main();
