// Lumtub learning pack license server, a Cloudflare Worker.
//
// POST /kofi   Ko-fi's webhook: a paid shop order is remembered by its
//              transaction id and the buyer's email.
// POST /polar  Polar's webhook (order.paid), signed as Standard Webhooks:
//              the order is remembered by its id and the buyer's email.
// POST /claim  {source: "kofi" or "polar", order, email, consent} or {source:
//              "afdian", order, consent} (Ko-fi's order is the transaction
//              id on the buyer's receipt) returns {code, consented} for a
//              paid order, or {error}. [consent] is the version of the
//              statement the buyer ticked: that the pack is supplied now and
//              the 14-day right of withdrawal ends with that (EU directive
//              2011/83 art. 16(m), Codice del consumo art. 59). The first
//              consent of each order is kept with its time.
//
// POST /activate {code, device, label} records a device for a code (at
//              most MAX_DEVICES) and returns {receipt, devices}: a signed
//              receipt that the code is active on that device, which the
//              app keeps and asks again for every 30 days. {error:
//              "revoked"} for a code in revoked.txt, {error: "devices",
//              devices} when the code is on as many devices as allowed.
// POST /deactivate {code, device} removes a device from a code's list;
//              whoever holds the code can, so a buyer frees a slot alone.
//
// 爱发电 orders are checked with 爱发电's own API when claimed, so they
// need no webhook. Codes are the same Ed25519-signed codes the signing
// page makes; the app checks them offline.
//
// Secrets (wrangler secret put): LICENSE_KEY (the PKCS#8 private key in
// base64), KOFI_TOKEN (Ko-fi › Webhooks › verification token),
// AFDIAN_USER_ID and AFDIAN_TOKEN (爱发电 › 开发者). Optional vars:
// KOFI_ITEM (the shop item's code, to count only that item) and
// AFDIAN_PLANS (comma-separated plan ids that count). Polar: the secret
// POLAR_WEBHOOK_SECRET (Polar › Settings › Webhooks), and optionally the
// var POLAR_PRODUCTS (comma-separated product ids that count).

import revokedList from './revoked.txt';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return reply(null, 204);
    try {
      if (request.method === 'POST' && url.pathname === '/kofi') return await kofi(request, env);
      if (request.method === 'POST' && url.pathname === '/polar') return await polar(request, env);
      if (request.method === 'POST' && url.pathname === '/claim') return await claim(request, env);
      if (request.method === 'POST' && url.pathname === '/activate') return await activate(request, env);
      if (request.method === 'POST' && url.pathname === '/deactivate') return await deactivate(request, env);
      if (request.method === 'GET' && url.pathname === '/') return reply({ ok: true });
      if (request.method === 'GET' && url.pathname === '/polar/thanks') return await polarThanks(url, env);
      return reply({ error: 'not found' }, 404);
    } catch (e) {
      console.log('error', e && e.stack || e);
      return reply({ error: 'server error' }, 500);
    }
  },
};

function reply(body, status = 200) {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type' },
  });
}

const sha256 = async (text) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
const hex = (buffer) => [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, '0')).join('');
const clean = (text) => String(text ?? '').trim();

// The statement the app shows beside the box the buyer ticks; a new
// wording gets a new version, and old ones stay accepted.
const CONSENTS = ['digital-content-v1'];

async function kofi(request, env) {
  const form = await request.formData();
  const data = JSON.parse(form.get('data') || '{}');
  if (!env.KOFI_TOKEN || data.verification_token !== env.KOFI_TOKEN) return reply({ error: 'bad token' }, 403);
  const items = Array.isArray(data.shop_items) ? data.shop_items : [];
  const counts = data.type === 'Shop Order' && (!env.KOFI_ITEM || items.some((i) => i.direct_link_code === env.KOFI_ITEM));
  if (!counts) return reply({ ok: true, ignored: true });
  const order = clean(data.kofi_transaction_id).toLowerCase();
  if (!order) return reply({ error: 'no transaction id' }, 400);
  // Codes carry no personal name: the order's tail is enough to trace one.
  await env.LICENSES.put(`kofi:${order}`, JSON.stringify({
    name: `Ko-fi #${order.replace(/[^0-9a-z]/g, '').slice(-6)}`,
    email: await sha256(clean(data.email).toLowerCase()),
    date: clean(data.timestamp).slice(0, 10) || new Date().toISOString().slice(0, 10),
  }));
  return reply({ ok: true });
}

const b64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)));

// Standard Webhooks: HMAC-SHA256 over "id.timestamp.body", base64, in
// webhook-signature as "v1,<signature>" (several may be listed). Polar
// signs with the secret's own bytes; a whsec_ secret in base64 is tried
// as well.
async function signedByPolar(request, body, secret) {
  const id = request.headers.get('webhook-id') || '';
  const timestamp = request.headers.get('webhook-timestamp') || '';
  const given = (request.headers.get('webhook-signature') || '').split(' ').map((s) => s.split(',')[1]).filter(Boolean);
  if (!id || !given.length || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const keys = [new TextEncoder().encode(secret)];
  try {
    keys.push(Uint8Array.from(atob(secret.replace(/^whsec_/, '')), (c) => c.charCodeAt(0)));
  } catch (_) {
    // Not base64: the bytes as they are only.
  }
  const message = new TextEncoder().encode(`${id}.${timestamp}.${body}`);
  for (const raw of keys) {
    const key = await crypto.subtle.importKey('raw', raw, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const expected = b64(await crypto.subtle.sign('HMAC', key, message));
    if (given.some((g) => g.length === expected.length && timingSafe(g, expected))) return true;
  }
  return false;
}

function timingSafe(a, b) {
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function polar(request, env) {
  const body = await request.text();
  if (!env.POLAR_WEBHOOK_SECRET || body.length > 200000 || !(await signedByPolar(request, body, env.POLAR_WEBHOOK_SECRET))) return reply({ error: 'bad signature' }, 403);
  const event = JSON.parse(body);
  if (event.type !== 'order.paid') return reply({ ok: true, ignored: true });
  const data = event.data || {};
  const products = clean(env.POLAR_PRODUCTS).split(',').map(clean).filter(Boolean);
  const product = clean(data.product_id || data.product?.id);
  if (products.length && !products.includes(product)) return reply({ ok: true, ignored: true });
  const order = clean(data.id).toLowerCase();
  const email = clean(data.customer?.email || data.user?.email).toLowerCase();
  if (!order || !email) return reply({ error: 'no order' }, 400);
  // The page Polar sends the buyer to after paying shows the order id.
  const checkout = clean(data.checkout_id).toLowerCase();
  if (checkout) await env.LICENSES.put(`polar-checkout:${checkout}`, order, { expirationTtl: 60 * 60 * 24 * 30 });
  await env.LICENSES.put(`polar:${order}`, JSON.stringify({
    name: `Polar #${order.replace(/[^0-9a-z]/g, '').slice(-6)}`,
    email: await sha256(email),
    date: clean(data.created_at).slice(0, 10) || new Date().toISOString().slice(0, 10),
  }));
  return reply({ ok: true });
}

// Polar's success page (its success URL ends ?checkout_id={CHECKOUT_ID}):
// the order id to type into Lumtub. It may come a few seconds before the
// webhook, so the page looks again.
async function polarThanks(url, env) {
  const checkout = clean(url.searchParams.get('checkout_id')).toLowerCase();
  const order = /^[0-9a-z_-]{3,80}$/.test(checkout) ? await env.LICENSES.get(`polar-checkout:${checkout}`) : null;
  const safe = (order || '').replace(/[^0-9a-z-]/g, '');
  const html = `<!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
${safe ? '' : '<meta http-equiv="refresh" content="4">'}<title>Lumtub</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:560px;margin:48px auto;padding:0 16px;color:#222}code{font-size:15px;background:#f2f2f2;padding:4px 8px;border-radius:6px;user-select:all;word-break:break-all}</style></head><body>
<h1>Thank you · 谢谢支持</h1>
${safe ? `<p>Your order ID · 你的订单号：</p><p><code>${safe}</code></p>
<p>In Lumtub › Learning › <b>I bought it: unlock</b>, pick Polar and enter this order ID and the email you paid with.</p>
<p>在 Lumtub › 学习 › <b>我买了：解锁</b>，选 Polar，填这个订单号和付款用的邮箱。</p>` : '<p>Confirming your payment… · 正在确认付款…</p>'}
</body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

async function claim(request, env) {
  const ask = await request.json().catch(() => ({}));
  const source = clean(ask.source);
  const order = clean(ask.order).toLowerCase();
  const email = clean(ask.email).toLowerCase();
  if (!order || order.length > 80 || email.length > 200) return reply({ error: 'order' }, 400);
  const consent = clean(ask.consent);
  if (!CONSENTS.includes(consent)) return reply({ error: 'consent' }, 400);
  // A few tries a minute per address are plenty for a person.
  const ip = request.headers.get('cf-connecting-ip') || '';
  const slot = `tries:${ip}:${Math.floor(Date.now() / 60000)}`;
  const tries = Number(await env.LICENSES.get(slot)) || 0;
  if (tries >= 10) return reply({ error: 'busy' }, 429);
  await env.LICENSES.put(slot, String(tries + 1), { expirationTtl: 120 });

  let buyer;
  if (source === 'kofi' || source === 'polar') {
    // Both must match, so a known email alone gets nothing.
    const saved = JSON.parse((await env.LICENSES.get(`${source}:${order}`)) || 'null');
    if (!saved || !email || saved.email !== await sha256(email)) return reply({ error: 'not found' }, 404);
    buyer = saved;
  } else if (source === 'afdian') {
    buyer = await afdianOrder(order, env);
    if (!buyer) return reply({ error: 'not found' }, 404);
  } else {
    return reply({ error: 'source' }, 400);
  }
  // The proof of consent: which statement, when, before the code went out.
  const consentKey = `consent:${source}:${order}`;
  let consented = JSON.parse((await env.LICENSES.get(consentKey)) || 'null');
  if (!consented) {
    consented = { version: consent, at: new Date().toISOString() };
    await env.LICENSES.put(consentKey, JSON.stringify(consented));
  }
  if (isRevoked(buyer.name, '')) return reply({ error: 'revoked' }, 403);
  const key = `code:${source}:${order}`;
  let code = await env.LICENSES.get(key);
  if (!code) {
    code = await sign(env, { n: buyer.name, p: 'learn', d: buyer.date });
    await env.LICENSES.put(key, code);
  }
  return reply({ code, name: buyer.name, consented: consented.at });
}

// Devices --------------------------------------------------------------

const MAX_DEVICES = 5;

// The public half of LICENSE_KEY, as in the app (lib/learning/license.dart).
const PUBLIC_KEY = new Uint8Array([
  92, 203, 159, 16, 74, 151, 175, 115, 174, 26, 30, 150, 154, 75, 64, 178,
  245, 5, 87, 31, 181, 23, 50, 133, 133, 226, 91, 128, 111, 232, 16, 148,
]);

// revoked.txt: one code a line, by the name in it ("Polar #a1b2c3") or
// by its id (the first 32 hex digits of its SHA-256, which the app
// shows); a note can follow " # ", and a line starting with # is one.
const REVOKED = new Set(String(revokedList).split('\n').filter((l) => !l.trim().startsWith('#')).map((l) => l.split(' # ')[0].trim().toLowerCase()).filter(Boolean));
const isRevoked = (name, id) => REVOKED.has(clean(name).toLowerCase()) || (id !== '' && REVOKED.has(id));

const fromB64url = (text) => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - text.length % 4) % 4)), (c) => c.charCodeAt(0));

// The code's fields when [text] is a code signed with LICENSE_KEY.
async function checkCode(text) {
  const code = clean(text).replace(/\s/g, '');
  const parts = code.startsWith('LT1.') ? code.slice(4).split('.') : [];
  if (parts.length !== 2 || code.length > 2000) return null;
  try {
    const payload = fromB64url(parts[0]);
    const signature = fromB64url(parts[1]);
    const context = new TextEncoder().encode('lumtub-license-v1\n');
    const message = new Uint8Array(context.length + payload.length);
    message.set(context);
    message.set(payload, context.length);
    const key = await crypto.subtle.importKey('raw', PUBLIC_KEY, { name: 'Ed25519' }, false, ['verify']);
    if (!await crypto.subtle.verify({ name: 'Ed25519' }, key, signature, message)) return null;
    const fields = JSON.parse(new TextDecoder().decode(payload));
    if (fields?.p !== 'learn') return null;
    return { code, id: (await sha256(code)).slice(0, 32), name: clean(fields.n) };
  } catch {
    return null;
  }
}

async function tooMany(request, env) {
  const ip = request.headers.get('cf-connecting-ip') || '';
  const slot = `tries:${ip}:${Math.floor(Date.now() / 60000)}`;
  const tries = Number(await env.LICENSES.get(slot)) || 0;
  if (tries >= 20) return true;
  await env.LICENSES.put(slot, String(tries + 1), { expirationTtl: 120 });
  return false;
}

const shown = (devices) => devices.map(({ id, label, seen }) => ({ id, label, seen }));

async function activate(request, env) {
  if (await tooMany(request, env)) return reply({ error: 'busy' }, 429);
  const ask = await request.json().catch(() => ({}));
  const device = clean(ask.device).toLowerCase();
  const label = clean(ask.label).slice(0, 80);
  if (!/^[0-9a-f]{32}$/.test(device)) return reply({ error: 'device' }, 400);
  const code = await checkCode(ask.code);
  if (!code) return reply({ error: 'code' }, 400);
  if (isRevoked(code.name, code.id)) return reply({ error: 'revoked' }, 403);
  const key = `devices:${code.id}`;
  const today = new Date().toISOString().slice(0, 10);
  // A device not seen for 24 months is forgotten (the privacy notice
  // says so), which also frees its slot.
  const cutoff = new Date(Date.now() - 730 * 86400000).toISOString().slice(0, 10);
  const devices = JSON.parse((await env.LICENSES.get(key)) || '[]').filter((d) => (d.seen || d.added || today) >= cutoff);
  const known = devices.find((d) => d.id === device);
  if (known) {
    known.seen = today;
    if (label) known.label = label;
  } else if (devices.length >= MAX_DEVICES) {
    return reply({ error: 'devices', devices: shown(devices), max: MAX_DEVICES }, 409);
  } else {
    devices.push({ id: device, label, added: today, seen: today });
  }
  await env.LICENSES.put(key, JSON.stringify(devices));
  const receipt = await signWith(env, { c: code.id, v: device, t: today }, 'lumtub-activation-v1\n', 'LA1.');
  return reply({ receipt, devices: shown(devices), max: MAX_DEVICES });
}

async function deactivate(request, env) {
  if (await tooMany(request, env)) return reply({ error: 'busy' }, 429);
  const ask = await request.json().catch(() => ({}));
  const device = clean(ask.device).toLowerCase();
  const code = await checkCode(ask.code);
  if (!code) return reply({ error: 'code' }, 400);
  const key = `devices:${code.id}`;
  const devices = JSON.parse((await env.LICENSES.get(key)) || '[]').filter((d) => d.id !== device);
  await env.LICENSES.put(key, JSON.stringify(devices));
  return reply({ devices: shown(devices), max: MAX_DEVICES });
}

async function afdianOrder(order, env) {
  if (!env.AFDIAN_USER_ID || !env.AFDIAN_TOKEN) return null;
  const params = JSON.stringify({ out_trade_no: order });
  const ts = Math.floor(Date.now() / 1000);
  const signText = `${env.AFDIAN_TOKEN}params${params}ts${ts}user_id${env.AFDIAN_USER_ID}`;
  const response = await fetch('https://afdian.com/api/open/query-order', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ user_id: env.AFDIAN_USER_ID, params, ts, sign: md5(signText) }),
  });
  const answer = await response.json().catch(() => null);
  if (!answer || answer.ec !== 200) {
    console.log('afdian', JSON.stringify(answer));
    return null;
  }
  const plans = clean(env.AFDIAN_PLANS).split(',').map(clean).filter(Boolean);
  const found = (answer.data?.list || []).find((o) => String(o.out_trade_no).toLowerCase() === order && Number(o.status) === 2 && (!plans.length || plans.includes(o.plan_id)));
  if (!found) return null;
  const when = Number(found.create_time) ? new Date(Number(found.create_time) * 1000) : new Date();
  return { name: `爱发电 #${order.replace(/[^0-9a-z]/g, '').slice(-6)}`, date: when.toISOString().slice(0, 10) };
}

async function sign(env, fields) {
  return signWith(env, fields, 'lumtub-license-v1\n', 'LT1.');
}

async function signWith(env, fields, contextText, prefix) {
  const der = Uint8Array.from(atob(env.LICENSE_KEY.replace(/\s/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'Ed25519' }, false, ['sign']);
  const payload = new TextEncoder().encode(JSON.stringify(fields));
  const context = new TextEncoder().encode(contextText);
  const message = new Uint8Array(context.length + payload.length);
  message.set(context);
  message.set(payload, context.length);
  const signature = await crypto.subtle.sign({ name: 'Ed25519' }, key, message);
  const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${prefix}${b64url(payload)}.${b64url(signature)}`;
}

// MD5, which 爱发电's API signs with and Web Crypto lacks (RFC 1321).
function md5(text) {
  const bytes = new TextEncoder().encode(text);
  const words = new Uint32Array(((bytes.length + 8 >> 6) + 1) * 16);
  for (let i = 0; i < bytes.length; i++) words[i >> 2] |= bytes[i] << (i % 4 * 8);
  words[bytes.length >> 2] |= 0x80 << (bytes.length % 4 * 8);
  words[words.length - 2] = bytes.length * 8;
  const s = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
  const k = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) >>> 0);
  let [a0, b0, c0, d0] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476];
  for (let chunk = 0; chunk < words.length; chunk += 16) {
    let [a, b, c, d] = [a0, b0, c0, d0];
    for (let i = 0; i < 64; i++) {
      let f, g;
      if (i < 16) { f = (b & c) | (~b & d); g = i; }
      else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
      else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
      else { f = c ^ (b | ~d); g = (7 * i) % 16; }
      const t = d;
      d = c;
      c = b;
      const sum = (a + f + k[i] + words[chunk + g]) >>> 0;
      b = (b + ((sum << s[(i >> 4) * 4 + i % 4]) | (sum >>> (32 - s[(i >> 4) * 4 + i % 4])))) >>> 0;
      a = t;
    }
    a0 = (a0 + a) >>> 0; b0 = (b0 + b) >>> 0; c0 = (c0 + c) >>> 0; d0 = (d0 + d) >>> 0;
  }
  return [a0, b0, c0, d0].map((v) => [0, 8, 16, 24].map((sh) => ((v >>> sh) & 255).toString(16).padStart(2, '0')).join('')).join('');
}

export { md5, sign };
