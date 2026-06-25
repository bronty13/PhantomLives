// PII detection engine — pure, environment-agnostic ES module.
//
// Single source of truth shared by three consumers:
//   - the browser (build.py inlines this into the detection Web Worker,
//     stripping the `export` keywords),
//   - the Node CLI (cli.mjs imports makeEngine),
//   - the test suite (tests/*.mjs import makeEngine).
//
// makeEngine(data) closes over the reference data and returns { detect }.
//   data = { firstNames: Set, lastNames: Set, places: {city: [STATE,...]} }

export function makeEngine(data) {
  const FIRST_NAMES = (data && data.firstNames instanceof Set) ? data.firstNames : new Set();
  const LAST_NAMES  = (data && data.lastNames  instanceof Set) ? data.lastNames  : new Set();
  const PLACES      = (data && data.places && typeof data.places === "object") ? data.places : {};

  // ---------- Static regex / data ----------
  const STATES_FULL = {
    "alabama":"AL","alaska":"AK","arizona":"AZ","arkansas":"AR","california":"CA",
    "colorado":"CO","connecticut":"CT","delaware":"DE","florida":"FL","georgia":"GA",
    "hawaii":"HI","idaho":"ID","illinois":"IL","indiana":"IN","iowa":"IA",
    "kansas":"KS","kentucky":"KY","louisiana":"LA","maine":"ME","maryland":"MD",
    "massachusetts":"MA","michigan":"MI","minnesota":"MN","mississippi":"MS","missouri":"MO",
    "montana":"MT","nebraska":"NE","nevada":"NV","new hampshire":"NH","new jersey":"NJ",
    "new mexico":"NM","new york":"NY","north carolina":"NC","north dakota":"ND","ohio":"OH",
    "oklahoma":"OK","oregon":"OR","pennsylvania":"PA","rhode island":"RI","south carolina":"SC",
    "south dakota":"SD","tennessee":"TN","texas":"TX","utah":"UT","vermont":"VT",
    "virginia":"VA","washington":"WA","west virginia":"WV","wisconsin":"WI","wyoming":"WY",
    "district of columbia":"DC"
  };
  const STATE_ABBR = new Set(Object.values(STATES_FULL));
  const STATE_FULL_RE = new RegExp("\\b(" + Object.keys(STATES_FULL).join("|").replace(/ /g,"\\s+") + ")\\b", "gi");
  const STATE_ABBR_RE = new RegExp("\\b(" + [...STATE_ABBR].join("|") + ")\\b", "g"); // case-sensitive

  const STREET_SUFFIXES = [
    "street","st","avenue","ave","road","rd","boulevard","blvd","lane","ln",
    "drive","dr","court","ct","place","pl","way","parkway","pkwy","circle","cir",
    "trail","trl","highway","hwy","terrace","ter","loop","square","sq","plaza","plz"
  ];
  const STREET_RE = new RegExp(
    "\\b\\d{1,6}\\s+(?:[NSEW]\\.?\\s+)?[A-Za-z0-9'\\-\\.]+(?:\\s+[A-Za-z0-9'\\-\\.]+){0,4}\\s+(?:" +
    STREET_SUFFIXES.join("|") + ")\\b\\.?",
    "gi"
  );
  const SECONDARY_RE = /\b(?:suite|ste|apt|apartment|unit|#|floor|fl|bldg|building|rm|room)\.?\s*[\w\d-]+\b/gi;
  const SSN_RE = /\b\d{3}-\d{2}-\d{4}\b/g;
  const PHONE_RE = /(?:\+?1[\s.\-]?)?\(?\b\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}\b/g;
  const ZIP_RE = /\b\d{5}(?:-\d{4})?\b/g;
  const EMAIL_RE = /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,24}\b/g;
  const NUMERIC_CANDIDATE_RE = /\b\d(?:[\s\-]?\d){4,18}\b/g;
  const VIN_RE = /\b[A-HJ-NPR-Z0-9]{17}\b/gi;

  const IPV4_RE = /\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/g;
  const IPV6_RE = /\b(?:[A-Fa-f0-9]{1,4}:){3,7}[A-Fa-f0-9]{1,4}\b/g; // >=4 groups: avoids HH:MM:SS
  const NINE_DIGIT_RE = /\b\d{9}\b/g;
  const DATE_RE = /\b(?:\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4}-\d{1,2}-\d{1,2}|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t)?(?:ember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+\d{4})\b/gi;
  const PASSPORT_RE = /passport\s*(?:no\.?|number|#|:)?\s*([A-Z0-9]{6,9})\b/gi;
  const DL_RE = /(?:driver'?s?\s+licen[cs]e|\bdl\b|license)\s*(?:no\.?|number|#|:)?\s*([A-Z0-9]{5,15})\b/gi;
  const ROUTING_KW = /\b(?:routing|aba|rtn|transit)\b/i;
  const DOB_KW = /\b(?:d\.?o\.?b\.?|date\s+of\s+birth|birth\s*date|born)\b/i;

  const NAME_STOPWORDS = new Set(`
the a an and or but if then so as is are was were be been being am do does did have has had
can could will would shall should may might must of for to in on at by with from into onto
upon about over under between among through during before after since until while because
although though however therefore however whether either neither both each every any some
no not yes very just only also even still here there now today tomorrow yesterday
i you he she it we they me him her us them my your his hers its our their mine yours ours theirs
this that these those who whom whose which what where when why how
loan title rate fee account amount balance payment due paid pay owe debt principal interest
term period escrow taxes insurance premium charge charges deposit refund credit
home auto vehicle car truck mortgage lease finance note bond
will may must can shall should would could
yes no okay ok sure thanks hello hi
date time day month year week
new old next last first second third
high low more less most least best worst
right left above below center side end front back top bottom
true false unknown other none null void
`.trim().toLowerCase().split(/\s+/));

  // ---------- Name detection ----------
  function isTitleCase(tok) { return /^[A-Z][a-z'’\-]*(?:[A-Z][a-z'’\-]*)*$/.test(tok) && /[a-z]/.test(tok); }
  function isAllCaps(tok)  { return /^[A-Z][A-Z'’\-]*$/.test(tok) && tok.length >= 2; }
  function nameTokenOk(tok){ if (NAME_STOPWORDS.has(tok.toLowerCase())) return false; return isTitleCase(tok) || isAllCaps(tok); }

  function findNames(text) {
    const out = [];
    if (!FIRST_NAMES.size || !LAST_NAMES.size) return out;
    const re = /\b([A-Za-z][A-Za-z'’\-]+)(?:\s+([A-Za-z])\.?)?\s+([A-Za-z][A-Za-z'’\-]+)\b/g;
    let m;
    while ((m = re.exec(text)) !== null) {
      const fnTok = m[1], lnTok = m[3];
      if (!nameTokenOk(fnTok) || !nameTokenOk(lnTok)) continue;
      if (!FIRST_NAMES.has(fnTok.toLowerCase())) continue;
      if (!LAST_NAMES.has(lnTok.toLowerCase())) continue;
      out.push({ start: m.index, end: m.index + m[0].length, type: "Name", value: m[0], priority: 20 });
    }
    const titledRe = /\b(Mr|Mrs|Ms|Miss|Dr|Prof|Rev|Sir|Madam)\.?\s+([A-Za-z][A-Za-z'’\-]+)\b/g;
    while ((m = titledRe.exec(text)) !== null) {
      const ln = m[2];
      if (!nameTokenOk(ln)) continue;
      if (!LAST_NAMES.has(ln.toLowerCase())) continue;
      out.push({ start: m.index, end: m.index + m[0].length, type: "Name", value: m[0], priority: 20 });
    }
    return out;
  }

  // ---------- City detection (hash lookup, not a megaregex) ----------
  function findCities(text) {
    const out = [];
    if (!PLACES || !Object.keys(PLACES).length) return out;
    const re = /\b([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+){0,2})\b/g;
    let m;
    while ((m = re.exec(text)) !== null) {
      const phrase = m[1];
      if (PLACES[phrase.toLowerCase()]) {
        out.push({ start: m.index, end: m.index + phrase.length, type: "City", value: phrase, priority: 30 });
        continue;
      }
      const toks = phrase.split(/\s+/);
      for (let n = toks.length - 1; n >= 1; n--) {
        const sub = toks.slice(0, n).join(" ");
        if (PLACES[sub.toLowerCase()]) {
          out.push({ start: m.index, end: m.index + sub.length, type: "City", value: sub, priority: 30 });
          break;
        }
      }
    }
    return out;
  }

  // ---------- Account / Credit Card ----------
  function luhnValid(d) {
    let sum = 0, alt = false;
    for (let i = d.length - 1; i >= 0; i--) {
      let x = d.charCodeAt(i) - 48;
      if (x < 0 || x > 9) return false;
      if (alt) { x *= 2; if (x > 9) x -= 9; }
      sum += x; alt = !alt;
    }
    return sum % 10 === 0;
  }
  function ccBrand(d) {
    const n = d.length;
    if (/^4/.test(d) && (n === 13 || n === 16 || n === 19)) return "Visa";
    if (n === 16) { if (/^5[1-5]/.test(d)) return "Mastercard"; const p4 = parseInt(d.slice(0,4),10); if (p4 >= 2221 && p4 <= 2720) return "Mastercard"; }
    if (/^3[47]/.test(d) && n === 15) return "Amex";
    if ((n === 16 || n === 19) && (/^6011/.test(d) || /^65/.test(d) || /^64[4-9]/.test(d))) return "Discover";
    if (n >= 14 && n <= 19 && (/^36/.test(d) || /^38/.test(d) || /^39/.test(d) || /^30[0-5]/.test(d))) return "Diners";
    if (n >= 16 && n <= 19 && /^35(2[89]|[3-8]\d)/.test(d)) return "JCB";
    return null;
  }
  function findCreditCardsAndAccounts(text) {
    const out = []; let m;
    NUMERIC_CANDIDATE_RE.lastIndex = 0;
    while ((m = NUMERIC_CANDIDATE_RE.exec(text)) !== null) {
      const raw = m[0], digits = raw.replace(/[\s\-]/g, "");
      const start = m.index, end = m.index + raw.length;
      if (/^\d{3}-\d{2}-\d{4}$/.test(raw)) continue;        // SSN shape -> SSN_RE owns it
      if (digits.length >= 13 && digits.length <= 19 && luhnValid(digits) && ccBrand(digits)) {
        out.push({ start, end, type: "CreditCard", value: raw, priority: 95 });
        continue;
      }
      if (digits.length >= 5 && digits.length <= 19) {
        out.push({ start, end, type: "Account", value: raw, priority: 55 });
      }
    }
    return out;
  }

  // ---------- ABA routing checksum ----------
  function abaValid(d) {
    if (d.length !== 9) return false;
    const n = [];
    for (let i = 0; i < 9; i++) n.push(d.charCodeAt(i) - 48);
    const sum = 3*(n[0]+n[3]+n[6]) + 7*(n[1]+n[4]+n[7]) + (n[2]+n[5]+n[8]);
    return sum % 10 === 0;
  }
  function nearKeyword(text, start, end, re, before, after) {
    const lo = Math.max(0, start - before);
    const hi = Math.min(text.length, end + after);
    return re.test(text.slice(lo, hi));
  }

  // ---------- New keyword-gated detectors ----------
  function findRouting(text) {
    const out = []; let m;
    NINE_DIGIT_RE.lastIndex = 0;
    while ((m = NINE_DIGIT_RE.exec(text)) !== null) {
      const d = m[0];
      if (!abaValid(d)) continue;
      if (!nearKeyword(text, m.index, m.index + 9, ROUTING_KW, 20, 20)) continue;
      out.push({ start: m.index, end: m.index + 9, type: "Routing", value: d, priority: 88 });
    }
    return out;
  }
  function findDOB(text) {
    const out = []; let m;
    DATE_RE.lastIndex = 0;
    while ((m = DATE_RE.exec(text)) !== null) {
      const s = m.index, e = m.index + m[0].length;
      if (!DOB_KW.test(text.slice(Math.max(0, s - 25), s))) continue;
      out.push({ start: s, end: e, type: "DOB", value: m[0], priority: 78 });
    }
    return out;
  }
  function findIPs(text) {
    const out = []; let m;
    IPV4_RE.lastIndex = 0;
    while ((m = IPV4_RE.exec(text)) !== null) out.push({ start: m.index, end: m.index + m[0].length, type: "IPAddress", value: m[0], priority: 108 });
    IPV6_RE.lastIndex = 0;
    while ((m = IPV6_RE.exec(text)) !== null) out.push({ start: m.index, end: m.index + m[0].length, type: "IPAddress", value: m[0], priority: 108 });
    return out;
  }
  function findAnchored(text, re, type, prio, requireDigit) {
    const out = []; let m;
    re.lastIndex = 0;
    while ((m = re.exec(text)) !== null) {
      const tok = m[1];
      if (!tok) continue;
      if (requireDigit && !/\d/.test(tok)) continue;       // cuts "License Agreement"
      const end = m.index + m[0].length;
      const start = end - tok.length;
      out.push({ start, end, type, value: tok, priority: prio });
    }
    return out;
  }

  // ---------- detect() + overlap resolver ----------
  function detect(text) {
    text = text || "";
    const matches = [];
    function push(re, type, prio) { let m; re.lastIndex = 0; while ((m = re.exec(text)) !== null) matches.push({ start: m.index, end: m.index + m[0].length, type, value: m[0], priority: prio }); }

    for (const x of findIPs(text)) matches.push(x);          // 108
    push(EMAIL_RE, "Email", 105);
    push(SSN_RE,   "SSN",   100);
    push(VIN_RE,   "VIN",   90);
    for (const r of findRouting(text)) matches.push(r);      // 88, gated
    push(PHONE_RE, "Phone", 80);
    for (const d of findDOB(text)) matches.push(d);          // 78, gated
    for (const p of findAnchored(text, PASSPORT_RE, "Passport", 76, true)) matches.push(p);
    for (const l of findAnchored(text, DL_RE, "DriversLicense", 74, true)) matches.push(l);
    for (const c of findCreditCardsAndAccounts(text)) matches.push(c);  // CC 95 / Account 55
    push(STREET_RE, "Address1", 70);
    push(SECONDARY_RE, "Address2", 60);
    push(ZIP_RE, "Zip", 58);   // above Account(55): a bare 5-digit ZIP must not read as [ACCOUNT]
    push(STATE_FULL_RE, "State", 40);
    push(STATE_ABBR_RE, "State", 35);
    for (const ci of findCities(text)) matches.push(ci);     // 30
    for (const nm of findNames(text)) matches.push(nm);      // 20

    matches.sort((a,b) => a.start - b.start || b.priority - a.priority || (b.end-b.start)-(a.end-a.start));
    // Resolve overlaps in one linear pass. Because `matches` is sorted by start
    // and `kept` stays non-overlapping, a new match can only overlap the LAST
    // kept interval (every earlier one ends before that last one begins, hence
    // before this match begins) — so we never scan more than one element. O(n).
    const kept = [];
    for (const mm of matches) {
      const last = kept[kept.length - 1];
      if (!last || mm.start >= last.end) { kept.push(mm); continue; }
      const mScore = mm.priority * 1000 + (mm.end - mm.start);
      const kScore = last.priority * 1000 + (last.end - last.start);
      if (mScore > kScore) { kept.pop(); kept.push(mm); }
    }
    return kept;
  }

  return { detect, luhnValid, ccBrand, abaValid };
}
