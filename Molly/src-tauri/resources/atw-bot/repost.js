// =====================================================================
// All Things Worn — Persistent Repost Bot (Playwright edition)
// =====================================================================
//
// A long-running Node.js process that, on each cycle:
//   1. Launches a fresh Chromium browser (no leftover state)
//   2. Logs in with credentials from .env
//   3. Counts all unscheduled listings across every page
//   4. Generates time slots spread across REPOST_DAYS days, within the
//      configured waking-hour window
//   5. Submits the repost form for each listing via direct HTTP POST
//      (inherits the browser's session cookies + CSRF token)
//   6. Closes the browser
//   7. Sleeps RUN_INTERVAL_HOURS with a live terminal countdown
//   8. Repeats. Ctrl+C to stop cleanly.
//
// USAGE:
//   cp .env.example .env           # fill in ATW_EMAIL / ATW_PASSWORD
//   npm install                    # installs Playwright + downloads Chromium
//   npm start                      # or: node repost.js
//
// =====================================================================

import 'dotenv/config';
import { chromium as chromiumExtra } from 'playwright-extra';
import StealthPlugin from 'puppeteer-extra-plugin-stealth';

// Apply stealth evasions (spoofs navigator.webdriver, plugins, codecs, etc.)
chromiumExtra.use(StealthPlugin());
const chromium = chromiumExtra;

// ---------- Config ----------
const cfg = {
  email:           required('ATW_EMAIL'),
  password:        required('ATW_PASSWORD'),
  baseUrl:         (process.env.BASE_URL || 'https://www.allthingsworn.com').replace(/\/$/, ''),
  loginPath:       process.env.LOGIN_PATH || '/login',
  emailSel:        process.env.LOGIN_EMAIL_SELECTOR    || 'input[name="email"]',
  passSel:         process.env.LOGIN_PASSWORD_SELECTOR || 'input[name="password"]',
  submitSel:       process.env.LOGIN_SUBMIT_SELECTOR   || 'button[type="submit"]',
  repostDays:      int('REPOST_DAYS', 3),
  utcOffset:       int('UTC_OFFSET', 4),
  startHour:       int('SCHEDULE_START_HOUR', 8),
  endHour:         int('SCHEDULE_END_HOUR', 22),
  delayMs:         int('DELAY_MS', 4000),
  intervalHours:   float('RUN_INTERVAL_HOURS', 12),
  headless:        (process.env.HEADLESS ?? 'true').toLowerCase() !== 'false',
};

validateConfig();

// ---------- Helpers ----------
function required(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var ${name}. Copy .env.example to .env and fill it in.`);
    process.exit(1);
  }
  return v;
}
function int(name, dflt) {
  const v = process.env[name];
  return v === undefined || v === '' ? dflt : parseInt(v, 10);
}
function float(name, dflt) {
  const v = process.env[name];
  return v === undefined || v === '' ? dflt : parseFloat(v);
}

function validateConfig() {
  if (!Number.isInteger(cfg.repostDays) || cfg.repostDays < 1) {
    fail(`REPOST_DAYS must be a positive integer (got ${cfg.repostDays})`);
  }
  if (cfg.startHour >= cfg.endHour || cfg.startHour < 0 || cfg.endHour > 24) {
    fail(`Invalid hour window: START=${cfg.startHour} END=${cfg.endHour}`);
  }
  if (!Number.isFinite(cfg.intervalHours) || cfg.intervalHours <= 0) {
    fail(`RUN_INTERVAL_HOURS must be > 0 (got ${cfg.intervalHours})`);
  }
}
function fail(msg) { console.error(`Config error: ${msg}`); process.exit(1); }

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const pad   = (n) => String(n).padStart(2, '0');
const ts    = () => new Date().toLocaleTimeString();
const log   = (msg) => console.log(`[${ts()}] ${msg}`);

// ---------- Slot generation (ported from console script) ----------
function generateTimeSlots(totalListings) {
  const slots = [];
  const slotsPerDay = Math.ceil(totalListings / cfg.repostDays);

  for (let dayOffset = 0; dayOffset < cfg.repostDays; dayOffset++) {
    const slotsThisDay = Math.min(
      slotsPerDay,
      Math.max(0, totalListings - dayOffset * slotsPerDay)
    );
    if (slotsThisDay === 0) break;

    const targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + 1 + dayOffset);
    const yr = targetDate.getFullYear();
    const mo = targetDate.getMonth(); // zero-based
    const dy = targetDate.getDate();
    const dateStr = `${yr}-${pad(mo + 1)}-${pad(dy)}`;

    const used = new Set();
    let count = 0;
    while (count < slotsThisDay) {
      const localH = cfg.startHour + Math.floor(Math.random() * (cfg.endHour - cfg.startHour));
      const utcH   = localH + cfg.utcOffset;
      if (utcH < 0 || utcH > 23) continue; // crosses UTC midnight — retry
      const m = Math.floor(Math.random() * 60);
      const key = `${utcH}:${m}`;
      if (used.has(key)) continue;
      used.add(key);
      slots.push(new Date(Date.UTC(yr, mo, dy, utcH, m, 0)).toISOString());
      count++;
    }
    log(`  Day ${dayOffset + 1} (${dateStr}): ${slotsThisDay} slot(s) within ${cfg.startHour}:00–${cfg.endHour}:00 local`);
  }
  return slots;
}

// ---------- Accept cookie banner if present ----------
async function acceptCookies(page) {
  const sel = 'button:has-text("Accept"), a:has-text("Accept")';
  try {
    const btn = page.locator(sel).first();
    if (await btn.isVisible({ timeout: 2000 })) {
      await btn.click();
      await page.waitForTimeout(500);
    }
  } catch { /* no banner */ }
}

// ---------- Login ----------
// ATW uses a two-step login: enter email → Continue → enter password → Sign in.
// The visible email input has id="email-input" and no `name` attribute.
async function login(page) {
  log('Logging in (step 1: email)...');
  const loginResp = await page.goto(cfg.baseUrl + cfg.loginPath, { waitUntil: 'domcontentloaded', timeout: 45000 });
  if (loginResp && !loginResp.ok()) {
    throw new Error(`Login page returned HTTP ${loginResp.status()} — site may be blocking this browser.`);
  }
  await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
  await acceptCookies(page);

  // Step 1: fill email and submit by pressing Enter (more reliable than button hunt).
  await page.waitForSelector('#email-input', { state: 'visible', timeout: 20000 });
  await page.fill('#email-input', cfg.email);
  await page.focus('#email-input');
  await page.keyboard.press('Enter');

  // Step 2: wait for password field, fill it, submit via Enter too.
  log('Logging in (step 2: password)...');
  await page.waitForSelector('input[type="password"]', { state: 'visible', timeout: 20000 });
  await page.fill('input[type="password"]', cfg.password);
  await page.focus('input[type="password"]');
  await Promise.all([
    page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {}),
    page.keyboard.press('Enter'),
  ]);
  await page.waitForTimeout(2000); // settle after login

  // Verify we're actually logged in. Look for real post-login content, not just URL.
  const verifyResp = await page.goto(cfg.baseUrl + '/account/listings', {
    waitUntil: 'domcontentloaded', timeout: 45000,
  });
  if (!verifyResp || !verifyResp.ok()) {
    const status = verifyResp?.status?.() ?? '?';
    await saveDebugShot(page, 'login-verify-fail');
    throw new Error(`Login verification got HTTP ${status} — site is likely blocking this browser as a bot. See login-verify-fail.png.`);
  }
  const url = page.url();
  if (url.includes('/login') || url.includes('/auth')) {
    await saveDebugShot(page, 'login-redirect');
    throw new Error(`Login failed — landed on ${url}. Check credentials.`);
  }
  // Sanity check: the listings page should contain the word "Listings" or a logout link.
  const bodyText = await page.locator('body').innerText().catch(() => '');
  if (!/listing|logout|sign out|account/i.test(bodyText)) {
    await saveDebugShot(page, 'login-unexpected-content');
    throw new Error('Logged-in page content looks unexpected. See login-unexpected-content.png.');
  }
  log('Login OK');
}

async function saveDebugShot(page, name) {
  try { await page.screenshot({ path: `${name}.png`, fullPage: true }); log(`  (saved ${name}.png)`); }
  catch { /* ignore */ }
}

// ---------- Count listings across all pages ----------
function listingsUrl(pageNum) {
  // Page 1 uses the bare URL — appending ?page=1 has been observed to trigger 403.
  return pageNum === 1
    ? `${cfg.baseUrl}/account/listings`
    : `${cfg.baseUrl}/account/listings?page=${pageNum}`;
}

async function countListings(page) {
  log('Counting listings across all pages...');
  let total = 0;
  let pageNum = 1;
  while (true) {
    const url = listingsUrl(pageNum);
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!resp || !resp.ok()) throw new Error(`HTTP ${resp?.status?.() ?? '?'} on page ${pageNum} (${url})`);
    const count = await page.locator('button[data-target*="repostScheduleModal"]').count();
    if (count === 0) break;
    total += count;
    if (count < 20) break; // last page (20/page pagination)
    pageNum++;
    await sleep(1500); // small breather between page fetches
  }
  log(`Found ${total} unscheduled listing(s) across ${pageNum} page(s)`);
  return { total, pages: pageNum };
}

// ---------- Process one page ----------
async function processPage(page, pageNum, slots, slotIdx) {
  await page.goto(listingsUrl(pageNum), {
    waitUntil: 'domcontentloaded', timeout: 45000,
  });

  const token = await page.getAttribute('meta[name="csrf-token"]', 'content').catch(() => null);
  if (!token) throw new Error('CSRF <meta name="csrf-token"> not found — session may have expired.');

  // Grab each listing's repost form action from its modal.
  const actions = await page.$$eval('button[data-target*="repostScheduleModal"]', (btns) => {
    const out = [];
    for (const btn of btns) {
      const targetId = (btn.getAttribute('data-target') || '').replace('#', '');
      if (!targetId) continue;
      const modal = document.getElementById(targetId);
      if (!modal) continue;
      const form = modal.querySelector('form[action*="/repost"]');
      if (form && form.action) out.push(form.action);
    }
    return out;
  });

  if (actions.length === 0) {
    log(`  Page ${pageNum}: nothing to repost`);
    return slotIdx;
  }

  log(`  Page ${pageNum}: submitting ${actions.length} listing(s)...`);

  for (let i = 0; i < actions.length; i++) {
    if (slotIdx >= slots.length) {
      log('Ran out of generated time slots — stopping this run.');
      return slotIdx;
    }
    const action = actions[i];
    const scheduledAt = slots[slotIdx];
    const slug = (action.split('/').slice(-2, -1)[0]) || action;

    // Derive local-time date/time fields that the server expects.
    const dt = new Date(scheduledAt);
    const localDt = new Date(dt.getTime() - cfg.utcOffset * 3600 * 1000);
    const scheduledDate = `${localDt.getUTCFullYear()}-${pad(localDt.getUTCMonth() + 1)}-${pad(localDt.getUTCDate())}`;
    const timeStr = `${pad(localDt.getUTCHours())}:${pad(localDt.getUTCMinutes())}`;

    // Submit via in-page fetch so the request inherits the full browser context
    // (cookies, Origin, Referer, User-Agent, TLS/JA3 fingerprint, stealth evasions).
    const result = await page.evaluate(
      async ({ action, token, scheduledAt, scheduledDate, timeStr }) => {
        try {
          const params = new URLSearchParams();
          params.append('_token', token);
          params.append('schedule_type', 'scheduled');
          params.append('scheduled_date', scheduledDate);
          params.append('scheduled_time_input', timeStr);
          params.append('scheduled_at', scheduledAt);
          const r = await fetch(action, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'X-CSRF-TOKEN': token,
            },
            body: params.toString(),
            redirect: 'follow',
          });
          return { status: r.status, url: r.url, ok: r.ok };
        } catch (e) {
          return { error: String(e && e.message || e) };
        }
      },
      { action, token, scheduledAt, scheduledDate, timeStr }
    );

    if (result.error) {
      log(`  [ERR] (${slotIdx + 1}/${slots.length}) ${slug}: ${result.error}`);
    } else {
      if (result.url && result.url.includes('/login')) {
        throw new Error('Redirected to /login mid-run — session expired.');
      }
      const marker = result.ok || (result.status >= 200 && result.status < 400) ? 'OK ' : 'ERR';
      const pct = Math.round(((slotIdx + 1) / slots.length) * 100);
      log(`  [${marker}] (${slotIdx + 1}/${slots.length}, ${pct}%) ${slug} -> ${scheduledDate} ${timeStr} [HTTP ${result.status}]`);
    }

    slotIdx++;
    if (i < actions.length - 1) await sleep(cfg.delayMs);
  }
  return slotIdx;
}

// ---------- One full run ----------
async function launchBrowser() {
  // Priority order:
  //   1. BROWSER_EXECUTABLE_PATH env var (point at any Chromium-based browser)
  //   2. channel 'chrome' (real Chrome, if installed)
  //   3. Playwright's bundled Chromium (last resort)
  const customPath = process.env.BROWSER_EXECUTABLE_PATH;
  if (customPath) {
    log(`  (using browser at ${customPath})`);
    return chromium.launch({ executablePath: customPath, headless: cfg.headless });
  }
  try {
    return await chromium.launch({ channel: 'chrome', headless: cfg.headless });
  } catch (err) {
    log(`  (real Chrome not found, falling back to bundled Chromium)`);
    return await chromium.launch({ headless: cfg.headless });
  }
}

async function runOnce() {
  const browser = await launchBrowser();
  const context = await browser.newContext({
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1440, height: 900 },
    locale: 'en-US',
  });
  // Basic webdriver flag hiding — defeats the easiest automation checks.
  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  });
  const page = await context.newPage();

  try {
    await login(page);
    const { total, pages } = await countListings(page);
    if (total === 0) {
      log('Nothing to repost — all listings already scheduled.');
      return;
    }
    const slots = generateTimeSlots(total);
    log(`Generated ${slots.length} time slot(s)`);

    let slotIdx = 0;
    for (let p = 1; p <= pages; p++) {
      slotIdx = await processPage(page, p, slots, slotIdx);
      if (slotIdx >= slots.length) break;
    }
    log(`Run complete — submitted ${slotIdx} of ${slots.length} slot(s).`);
  } finally {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
  }
}

// ---------- Countdown sleep between runs ----------
let stopRequested = false;
async function countdownSleep(hours) {
  const endAt = Date.now() + hours * 3600 * 1000;
  while (!stopRequested && Date.now() < endAt) {
    const remain = endAt - Date.now();
    const h = Math.floor(remain / 3600000);
    const m = Math.floor((remain % 3600000) / 60000);
    const s = Math.floor((remain % 60000) / 1000);
    process.stdout.write(`\r  Next run in ${pad(h)}h ${pad(m)}m ${pad(s)}s   (Ctrl+C to stop) `);
    await sleep(1000);
  }
  process.stdout.write('\n');
}

// ---------- Main ----------
process.on('SIGINT', () => {
  stopRequested = true;
  console.log('\nStopping after current run (or press Ctrl+C again to force quit).');
  process.on('SIGINT', () => process.exit(0));
});

(async function main() {
  console.log('='.repeat(65));
  console.log(' ATW Repost Bot');
  console.log('='.repeat(65));
  log(`Interval: ${cfg.intervalHours}h between runs`);
  log(`Repost window: ${cfg.startHour}:00–${cfg.endHour}:00 local, spread across ${cfg.repostDays} day(s)`);
  log(`Throttle: ${cfg.delayMs} ms between submissions`);
  log(`Headless: ${cfg.headless}`);
  log('Press Ctrl+C to stop.');

  let runNum = 1;
  while (!stopRequested) {
    console.log(`\n--- Run #${runNum} @ ${new Date().toLocaleString()} ---`);
    const startedAt = Date.now();
    try {
      await runOnce();
    } catch (err) {
      log(`Run #${runNum} failed: ${err.message}`);
      if (process.env.DEBUG) console.error(err.stack);
    }
    const elapsed = ((Date.now() - startedAt) / 1000).toFixed(1);
    log(`Run #${runNum} ended (${elapsed}s elapsed).`);
    runNum++;

    if (stopRequested) break;
    await countdownSleep(cfg.intervalHours);
  }
  console.log('Bye.');
})();
