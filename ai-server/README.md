# AI helper

`worker.js` is a Cloudflare Worker that gives **AI 讲这句** (a subtitle line
explained for a learner) to learning pack buyers who have no AI key of
their own. People with their own key under 翻译与 AI never use it.

It is **off** until its owner turns it on, because every explanation is
paid for with the owner's AI key:

1. Add the repository secret `LUMTUB_AI_KEY`: a key for an
   OpenAI-compatible Chat Completions service. DeepSeek
   (`https://api.deepseek.com`, model `deepseek-chat`) is the default;
   another service is chosen with the repository variables
   `LUMTUB_AI_BASE` and `LUMTUB_AI_MODEL`.
2. Run the **AI helper** workflow (Actions › AI helper › Run workflow).
   It uses the license server's Cloudflare secrets, deploys the worker
   and writes its address to the `learning` release as `ai-server.txt`.
   The app asks the helper only while that file is there.
3. To turn it off, run the workflow with **off** ticked: the address is
   removed and the app goes back to asking for the person's own key.

Limits (in `wrangler.toml`): `PER_DAY` lines a day for each code, `TRIAL`
lines in all for a device in the free trial, and `DAILY_MAX` lines a day
for everyone together, so a bill can never run away. A line asked before
comes from the cache and counts for nothing.

Only the line, up to three lines before and two after, and the video's
title are sent to the AI service. Request logs are off.
