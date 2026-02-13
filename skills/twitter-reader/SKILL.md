---
name: twitter-reader
description: Read Twitter/X timelines, individual tweets, and user profiles. Use when the user asks about tweets, Twitter feeds, X posts, or wants to check what someone posted on Twitter/X. Triggers on phrases like "tweets", "twitter", "timeline", "@username", "X post", "lire twitter", "profil twitter".
user-invocable: true
---

# Twitter / X Reader

Read tweets, timelines, and user profiles from Twitter/X without API keys.

## What it does

This skill lets you read Twitter/X content using two free, no-auth public endpoints:
- **Twitter Syndication API** — for user timelines (latest tweets)
- **FxTwitter API** — for individual tweet details and user profiles

## Commands

### Read a user's recent tweets
```bash
node skills/twitter-reader/run.js --user <handle> [--count N]
```
Example: `node skills/twitter-reader/run.js --user OpenAI --count 5`

### Read a specific tweet
```bash
node skills/twitter-reader/run.js --tweet <tweet_id_or_url>
```
Example: `node skills/twitter-reader/run.js --tweet https://x.com/OpenAI/status/1889753204340265039`
Or: `node skills/twitter-reader/run.js --tweet 1889753204340265039`

### Get a user profile
```bash
node skills/twitter-reader/run.js --profile <handle>
```
Example: `node skills/twitter-reader/run.js --profile elonmusk`

### Search tweets
For search, use the `web_search` tool with `site:x.com <query>`.

## Output formats

- Default: human-readable text with emojis
- JSON: add `--format json` for structured output

## Instructions

When the user asks to read tweets, check a Twitter/X timeline, or look up a Twitter user:

1. For **timelines**: run `node skills/twitter-reader/run.js --user <handle> --count <N>`
2. For **specific tweets** (URL or ID): run `node skills/twitter-reader/run.js --tweet <id_or_url>`
3. For **user profiles**: run `node skills/twitter-reader/run.js --profile <handle>`
4. For **tweet search**: use `web_search` with query `site:x.com <search terms>`

Always present the results in a clean, readable format. Include engagement metrics (likes, retweets) and dates.

## Limitations

- Timeline returns ~20 most recent tweets (Twitter syndication limit)
- No access to replies, DMs, or private accounts
- Rate limits may apply if called very frequently
- Search is delegated to web_search (Bing grounding)

## No API key required

This skill uses public endpoints that don't require authentication.
