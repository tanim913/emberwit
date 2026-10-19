// Emberwit website: the lantern scene, the demo phone and the page's small
// interactive proofs. No network requests beyond this site's own files.
import * as THREE from './vendor/three.module.min.js';

const root = document.documentElement;
const body = document.body;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const small = matchMedia('(max-width: 960px)');
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;

/* ------------------------------------------------------------------ */
/* Language of the page                                                */
/* ------------------------------------------------------------------ */
const BN = {
  'skip': 'মূল অংশে যান',
  'nav.how': 'কীভাবে চলে', 'nav.lang': 'ভাষা', 'nav.privacy': 'গোপনীয়তা', 'nav.get': 'ডাউনলোড',
  'hero.title': 'ইন্টারনেট না থাকলেও যে AI কাজ করে।',
  'hero.sub': 'Emberwit-এর AI চলে <b>আপনার ফোনের ভেতরেই</b>। একবার একটি মডেল ডাউনলোড করুন, তারপর ইন্টারনেট ছাড়াই বাংলা বা English-এ কথা বলুন। কোনো অ্যাকাউন্ট নেই, কিছুই কোথাও পাঠানো হয় না।',
  'hero.cta': 'Android-এর জন্য ডাউনলোড', 'hero.how': 'কীভাবে কাজ করে দেখুন',
  'hero.f1': 'ফ্রি ও ওপেন সোর্স', 'hero.f2': 'Android 8.0+', 'hero.f3': 'বিজ্ঞাপন নেই, ট্র্যাকিং নেই',
  'phone.model': 'Qwen3 1.7B · এই ফোনেই চলছে', 'phone.online': 'অনলাইন', 'phone.offline': 'অফলাইন · তবুও চলছে',
  'phone.label': 'বার্তা', 'phone.ph': 'Emberwit-কে লিখুন',
  'phone.note': 'এটি একটি ডেমো: এই পেজের উত্তরগুলো আগে থেকে লেখা। অ্যাপ নিজেই উত্তর লেখে, আপনার ফোনে।',
  'switch.title': 'ইন্টারনেট বন্ধ করুন', 'switch.sub': 'শহরের আলো নিভে যাবে। Emberwit তবুও উত্তর দেবে।',
  'how.title': 'একবার ডাউনলোড। তারপর অফলাইনেও আপনার।',
  'how.lede': 'বেশিরভাগ AI অ্যাপ আপনার লেখা প্রতিটি শব্দ দূরের কোনো সার্ভারে পাঠায়। Emberwit পুরো AI মডেলটাই আপনার ফোনে রাখে। ইন্টারনেট লাগে শুধু একবার, ডাউনলোডের সময়।',
  'how.s1': 'ফোনটা পরীক্ষা করে নেয়', 'how.s1p': 'মেমরি, প্রসেসর আর একটা ছোট স্পিড টেস্ট, যাতে শুধু সেই মডেলগুলোই সাজেস্ট করে যেগুলো আপনার ফোনে ভালো চলবে।',
  'how.s2': 'একটি মডেল ডাউনলোড করুন', 'how.s2p': '০.৫ থেকে ২.৫ GB, চাইলে Wi-Fi-তে। ব্যবহারের আগে প্রতিটি ফাইল একটি সাইন করা তালিকার সাথে মিলিয়ে দেখা হয়।',
  'how.s3': 'ইন্টারনেট ছাড়াই চ্যাট', 'how.s3p': 'এয়ারপ্লেন মোড, লোডশেডিং, ডেটা প্যাক শেষ—তবুও উত্তর দেয়, কারণ ফোন থেকে কিছুই বাইরে যেতে হয় না।',
  'g.ram': 'মেমরি', 'g.cpu': 'কোর', 'g.fit': 'মডেলের সাইজ', 'g.title': 'এক নজরে আপনার ডিভাইস',
  'g.note': 'আপনার ব্রাউজার যা জানায় তা থেকে একটা মোটামুটি ধারণা। কিছু সাজেস্ট করার আগে অ্যাপ ফোনটা ঠিকভাবে মেপে নেয়।',
  'models.title': 'বেছে নেওয়ার জন্য আটটি মডেল',
  'models.lede': '২ GB ফোনের জন্য ছোট মডেল, আর ভালো বাংলা লেখার জন্য বড় মডেল। রিংটা টেনে ঘোরান, বা তীর চিহ্ন ব্যবহার করুন।',
  'lang.title': 'যেভাবে কথা বলেন, সেভাবেই লিখুন। উত্তরও আসবে সেভাবেই।',
  'lang.lede': 'প্রতিটি বার্তার ভাষা দেখে নেওয়া হয়। English-এ লিখলে English, বাংলায় লিখলে বাংলা, ইংরেজি অক্ষরে বাংলা লিখলেও।',
  'lang.trylabel': 'উত্তরের ভাষা দেখতে কিছু লিখুন', 'lang.ph': 'কিছু লিখুন: “ami bhalo achi”, “hello”, “কেমন আছো”',
  'lang.wait': 'উত্তরের ভাষা: অপেক্ষা করছি', 'lang.real': 'এই বক্সটি অ্যাপের একই নিয়মে চলে, আপনার ব্রাউজারেই।',
  'do.title': 'মুখে বলুন। কিছু কাজও করে দেয়।',
  'do.lede': 'টাইপ না করে মাইকে চাপ দিয়ে বলুন; আপনার ফোন ডিভাইসেই কথাকে লেখায় রূপ দেয়। অ্যালার্ম বা টর্চ চাইলে Emberwit সরাসরি করে দেয়, বাংলা বা English-এ, ইন্টারনেট ছাড়াই।',
  'do.try': 'চেষ্টা করুন',
  'do.voice': '<b>ভয়েস টাইপিং ফোনেই থাকে।</b> এটা আপনার ফোনের নিজস্ব অফলাইন স্পিচ রিকগনাইজার ব্যবহার করে, তাই আপনার কণ্ঠ কখনো আপলোড হয় না। English সব ফোনে চলে; বাংলা চলবে যদি আপনার ফোন অফলাইনে বাংলা দেয়।',
  'do.pick': 'কী হয় দেখতে একটি কমান্ড বেছে নিন।', 'do.widget': 'Emberwit-কে বলুন', 'do.widgetsub': 'হোম-স্ক্রিন উইজেট: এক চাপে কথা বলুন',
  'priv.title': 'আপনার ফোনে যা হয়, তা আপনার ফোনেই থাকে।',
  'priv.lede': 'এটা কোনো নীতিমালার প্রতিশ্রুতি নয়। অ্যাপটাই এভাবে বানানো: আপনার চ্যাট পাঠানোর মতো কোনো সার্ভারই নেই।',
  'priv.cap': 'আপনার ফোন থেকে কী বাইরে যায়',
  'priv.r1': 'আপনার বার্তা ও উত্তর', 'priv.never': 'কখনো না', 'priv.r2': 'আপনার কণ্ঠ',
  'priv.r3': 'ব্যবহারের পরিসংখ্যান, ক্র্যাশ রিপোর্ট, বিজ্ঞাপন আইডি', 'priv.none': 'কিছুই সংগ্রহ হয় না',
  'priv.r4': 'নাম, ইমেইল, ফোন নম্বর', 'priv.noacc': 'কোনো অ্যাকাউন্টই নেই',
  'priv.r5': 'ইন্টারনেট ব্যবহার', 'priv.r5v': 'শুধু মডেলের তালিকা আনতে আর আপনার বেছে নেওয়া মডেল ডাউনলোড করতে',
  'priv.k1': 'চ্যাট এনক্রিপ্টেড', 'priv.k1p': 'ইতিহাস একটি এনক্রিপ্টেড ডেটাবেসে থাকে, আর চাবি থাকে ফোনের সুরক্ষিত স্টোরেজে।',
  'priv.k2': 'ইচ্ছা হলে অ্যাপ লক', 'priv.k2p': 'ফোনের PIN বা আঙুলের ছাপ দিয়ে খুলুন। লক থাকলে সাম্প্রতিক অ্যাপের তালিকায় স্ক্রিন দেখা যায় না।',
  'priv.k3': 'ব্যাকআপ আপনার নিয়ন্ত্রণে', 'priv.k3p': 'নিজের পাসওয়ার্ড দিয়ে চ্যাট এনক্রিপ্টেড ফাইলে এক্সপোর্ট করুন, আর অন্য ফোনে ইমপোর্ট করুন।',
  'priv.k4': 'এমনকি এই ওয়েবসাইটও', 'priv.k4p': 'কোনো কুকি নেই, অ্যানালিটিক্স নেই, অন্য কোনো সাইটে রিকোয়েস্ট যায় না। ফন্ট আর কোড এই সাইট থেকেই আসে।',
  'care.title': 'ফোনের প্রতি যত্নশীল, সীমাবদ্ধতা নিয়ে সৎ।',
  'care.c1': 'ফোন গরম হলে', 'care.c1p': 'Emberwit ধীরে চলে বা থেমে যায়, ফোনকে পুড়িয়ে ফেলে না।',
  'care.c2': 'ব্যাটারি কমে গেলে', 'care.c2p': 'আস্তে চলে, আর কেন সেটাও জানায়।',
  'care.c3': 'মেমরি কমে গেলে', 'care.c3p': 'মডেলটা সরিয়ে রাখা হয়, দরকার হলে আবার লোড হয়।',
  'lim.title': 'যা পারে না',
  'lim.1': 'ওয়েবে সার্চ করতে বা আজকের খবর জানতে পারে না। মডেল যা শিখেছে, সেটুকুই জানে।',
  'lim.2': 'ছোট মডেল ভুল করে। গুরুত্বপূর্ণ কিছু হলে যাচাই করে নিন।',
  'lim.3': 'সবচেয়ে বড় মডেলের জন্য প্রায় ৬ GB মেমরি লাগে; সবচেয়ে ছোটটা ২ GB-তেই চলে।',
  'lim.4': 'বাংলা ভয়েস টাইপিং আপনার ফোনের ওপর নির্ভর করে; অনেক ফোন অফলাইনে শুধু English দেয়।',
  'lim.5': 'আপাতত শুধু Android, GitHub থেকে। এখনো Play Store-এ নেই।',
  'get.title': 'পকেটে একটা আলো জ্বালিয়ে রাখুন।',
  'get.lede': 'ফ্রি, ওপেন সোর্স, আর পুরোপুরি আপনার। অ্যাপ ডাউনলোড করুন, একটা মডেল বেছে নিন, তাহলেই পরের বার ইন্টারনেট চলে গেলেও আপনি তৈরি।',
  'get.src': 'সোর্স কোড দেখুন',
  'get.i1': 'APK ডাউনলোড করুন', 'get.i1p': 'ফোনে রিলিজ পেজটি খুলে <i>arm64-v8a.apk</i> দিয়ে শেষ হওয়া ফাইলে চাপ দিন।',
  'get.i2': 'ইনস্টলের অনুমতি দিন', 'get.i2p': 'Android একবার জানতে চাইবে ব্রাউজার থেকে ইনস্টলের অনুমতি দেবেন কি না। অনুমতি দিন, তারপর Install চাপুন।',
  'get.i3': 'একটি মডেল বেছে নিন', 'get.i3p': 'Emberwit ফোনটা পরীক্ষা করে একটি মডেল সাজেস্ট করবে। সেটা ডাউনলোড করুন, পারলে Wi-Fi-তে।',
  'get.i4': 'অফলাইনে যান', 'get.i4p': 'ব্যস। ইন্টারনেট বন্ধ করুন, চ্যাট চালিয়ে যান।',
  'get.needs': 'লাগবে Android 8.0 বা নতুন, ৬৪-বিট ফোন, আর অন্তত ২ GB মেমরি। প্রতিটি রিলিজে SHA-256 চেকসাম দেওয়া থাকে, যাতে ফাইলটা যাচাই করতে পারেন।',
  'foot.by': '<b>Azizullah Tanim</b>-এর তৈরি', 'foot.privacy': 'গোপনীয়তা নীতি',
  'foot.small': 'MIT লাইসেন্সে ওপেন সোর্স। মডেল ফাইলগুলোর নিজস্ব লাইসেন্স আছে (Apache 2.0, MIT, Gemma Terms, Llama 3.2 Community License), যা ডাউনলোডের আগে অ্যাপে দেখানো হয়।',
};
// Strings built in code, both languages.
const S = {
  en: {
    online: 'Online', offline: 'Offline · still works',
    hello: 'Hi! I run right here on this phone. Ask me something, or turn off the internet first and try again.',
    netOff: 'Internet off. Still here.', netOn: 'Internet back on. Nothing changes for me.',
    waiting: 'Reply language: waiting', replyEn: 'Reply language: English', replyBn: 'Reply language: Bengali (বাংলা)',
    fitNone: 'Your browser doesn’t say how much memory it has. As a guide: 2 GB phones run Qwen3 0.6B, 3–4 GB phones run the 1–3B models, 6 GB phones run the 4B ones.',
    fit: (ram, m) => `With about ${ram} GB of memory, a good first pick would be <span class="pick">${m}</span>.`,
    fitPc: (ram, m) => `This looks like a computer with ${ram}+ GB. A phone with that much memory could run <span class="pick">${m}</span>.`,
    gb: 'GB', size: 'Download', ram: 'Memory', bn: 'Bengali', fitTag: 'Fits your device',
    q: { good: 'Good', basic: 'Basic', limited: 'Limited' },
    lic: { 'Apache-2.0': 'Apache 2.0', MIT: 'MIT', gemma: 'Gemma Terms', 'llama3.2': 'Llama 3.2' }, license: 'License',
    of: (i, n, name) => `${name} · ${i} of ${n}`,
  },
  bn: {
    online: 'অনলাইন', offline: 'অফলাইন · তবুও চলছে',
    hello: 'হ্যালো! আমি এই ফোনেই চলি। কিছু জিজ্ঞেস করুন, অথবা আগে ইন্টারনেট বন্ধ করে আবার চেষ্টা করুন।',
    netOff: 'ইন্টারনেট বন্ধ। আমি এখনো আছি।', netOn: 'ইন্টারনেট ফিরে এসেছে। আমার জন্য কিছুই বদলায় না।',
    waiting: 'উত্তরের ভাষা: অপেক্ষা করছি', replyEn: 'উত্তরের ভাষা: English', replyBn: 'উত্তরের ভাষা: বাংলা',
    fitNone: 'আপনার ব্রাউজার মেমরির পরিমাণ জানায় না। মোটামুটি হিসাব: ২ GB ফোনে Qwen3 0.6B, ৩–৪ GB ফোনে ১–৩B মডেল, ৬ GB ফোনে 4B মডেল চলে।',
    fit: (ram, m) => `প্রায় ${bnDigits(ram)} GB মেমরিতে প্রথমে <span class="pick">${m}</span> বেছে নেওয়া ভালো।`,
    fitPc: (ram, m) => `এটা মনে হচ্ছে ${bnDigits(ram)}+ GB-র একটি কম্পিউটার। এত মেমরির একটি ফোনে <span class="pick">${m}</span> চলবে।`,
    gb: 'GB', size: 'ডাউনলোড', ram: 'মেমরি', bn: 'বাংলা', fitTag: 'আপনার ডিভাইসে চলবে',
    q: { good: 'ভালো', basic: 'মোটামুটি', limited: 'সীমিত' },
    lic: { 'Apache-2.0': 'Apache 2.0', MIT: 'MIT', gemma: 'Gemma Terms', 'llama3.2': 'Llama 3.2' }, license: 'লাইসেন্স',
    of: (i, n, name) => `${name} · ${bnDigits(i)}/${bnDigits(n)}`,
  },
};
const EN = {};
let lang = 'en';
const t = (k) => S[lang][k];

function bnDigits(v) { return String(v).replace(/[0-9]/g, (d) => '০১২৩৪৫৬৭৮৯'[d]); }

function setLang(next) {
  lang = next;
  root.lang = next; root.dataset.lang = next;
  for (const el of $$('[data-i18n]')) {
    const k = el.dataset.i18n;
    if (!(k in EN)) EN[k] = el.innerHTML;
    el.innerHTML = next === 'bn' && BN[k] ? BN[k] : EN[k];
  }
  for (const el of $$('[data-i18n-ph]')) {
    const k = el.dataset.i18nPh;
    if (!(k in EN)) EN[k] = el.placeholder;
    el.placeholder = next === 'bn' && BN[k] ? BN[k] : EN[k];
  }
  for (const b of $$('[data-setlang]')) b.setAttribute('aria-pressed', String(b.dataset.setlang === next));
  try { localStorage.setItem('emberwit.lang', next); } catch { /* storage blocked: the choice just isn't kept */ }
  $('#netchip').textContent = body.classList.contains('offline') ? t('offline') : t('online');
  renderFit(); renderRing(); updateLangTry();
}
for (const b of $$('[data-setlang]')) b.addEventListener('click', () => setLang(b.dataset.setlang));

/* ------------------------------------------------------------------ */
/* Reply language: the app's own rules (reply_language.dart)           */
/* ------------------------------------------------------------------ */
const ROMANIZED_BN = new Set(('ami amra amar amader amake tumi tomar tomake tomra tomader apni apnar ' +
  'apnake apnara apnader er se tar tara tader ora oder ke kar ki keno kno kemon kmn kivabe kibhabe kemne kothay kothai kobe kokhon koto kon ' +
  'kichu kisu keu naki acho achen achi ache achhe ase asen asi achho chilo chhilo silo nai nei na hobe hoy hoye hoyeche hoise hoyse holo ' +
  'hoilo kori koro koren korbo korte korchi korsi korecho korlam kore korun bolo bolen bolte bolchi bolun jani janina jante janen janao ' +
  'janan jabo jao jaben khabo khai khete valo bhalo bhalobasi bhalobashi valobasi onek khub kintu tahole tahle jodi ekta ekti ektu shob sob ' +
  'shobai sobai dhonnobad dhonyobad accha acha thik bhai vai apu lagbe lage chai chao chan diye dite dao niye theke ekhon akhon ajke aj kalke ' +
  'ei oi eta ota sheta seta eita oita mane shathe sathe jonno jnno bhabe vabe porte pori likho likhte likhun bujhi bujhlam bujhte bujhao ' +
  'bujhiye shekhao shikhte golpo kobita proshno prosno uttor abar aro arekta pari parbo paro paren parben dekhao dekhte dekhi shune shuni ' +
  'hae haa kholo khulo jalao nivao nevao bondho bondo dio tay').split(' '));
const ENGLISH = new Set(('the a an is are am was were be been what how why who when where which ' +
  'you your i me my we our they he she it its to of and or in on at for with this that these those can could do does did please tell explain ' +
  'write give make about have has will would should there from not no yes hi hello hey thanks thank want need like know help some any all more ' +
  'if but so than then just also very good into by as show').split(' '));

function detectLanguage(text) {
  let bn = 0, latin = 0;
  for (const ch of text) {
    const c = ch.codePointAt(0);
    if (c >= 0x0980 && c <= 0x09ff) bn++;
    else if ((c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a)) latin++;
  }
  if (!bn && !latin) return null;
  if (bn * 2 >= latin) return 'bn';
  const words = text.toLowerCase().match(/[a-z]+/g) || [];
  const b = words.filter((w) => ROMANIZED_BN.has(w)).length;
  const e = words.filter((w) => ENGLISH.has(w)).length;
  return b > e ? 'bn' : 'en';
}

const langTry = $('#langtry');
const langOut = $('#langout');
function updateLangTry() {
  const l = detectLanguage(langTry.value);
  langOut.textContent = l == null ? t('waiting') : l === 'bn' ? t('replyBn') : t('replyEn');
  langOut.classList.toggle('hit', l != null);
}
langTry.addEventListener('input', updateLangTry);

/* ------------------------------------------------------------------ */
/* Phone commands: the app's own reply sentences (device_actions.dart) */
/* ------------------------------------------------------------------ */
function toAscii(s) { return s.replace(/[০-৯]/g, (d) => String(d.charCodeAt(0) - 0x09e6)); }
function bnPart(h) {
  return h >= 4 && h < 6 ? 'ভোর' : h >= 6 && h < 12 ? 'সকাল' : h >= 12 && h < 15 ? 'দুপুর' : h >= 15 && h < 18 ? 'বিকেল' : h >= 18 && h < 20 ? 'সন্ধ্যা' : 'রাত';
}
function timeText(h, m, l) {
  const h12 = h % 12 === 0 ? 12 : h % 12, mm = String(m).padStart(2, '0');
  return l === 'bn' ? `${bnPart(h)} ${bnDigits(`${h12}:${mm}`)}` : `${h12}:${mm} ${h < 12 ? 'AM' : 'PM'}`;
}
// Simplified version of DeviceCommand.parse, enough for the demo.
function parseCommand(raw) {
  const s = toAscii(raw.toLowerCase()).replace(/[?!.।]/g, ' ').trim();
  if (s.length > 80) return null;
  if (/(flash ?light|torch|টর্চ)/.test(s)) {
    const off = /(off|বন্ধ|নিভাও|nivao|nevao|bondho)/.test(s);
    return { kind: 'torch', on: !off };
  }
  const tm = s.match(/(\d+)\s*(min|minute|minutes|মিনিট|hour|hours|ঘণ্টা)/);
  if (/(timer|টাইমার)/.test(s) && tm) {
    const n = +tm[1], hours = /hour|ঘণ্টা/.test(tm[2]);
    return { kind: 'timer', minutes: hours ? n * 60 : n };
  }
  if (/(alarm|অ্যালার্ম|এলার্ম)/.test(s)) {
    const m = s.match(/(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|টা|টায়)?/);
    if (!m) return { kind: 'alarm', hour: null };
    let h = +m[1]; const min = +(m[2] || 0);
    const pm = m[3] === 'pm' || /(বিকাল|বিকেল|সন্ধ্যা|রাত|evening|night)/.test(s) && h < 12;
    if (m[3] === 'am' && h === 12) h = 0;
    else if (pm && h < 12) h += 12;
    return { kind: 'alarm', hour: h % 24, minute: min };
  }
  const open = s.match(/^(?:please\s+)?(?:open|launch|start)\s+(.+)$/) || s.match(/^(.+?)\s+(?:খোলো|খুলুন|kholo|khulo)$/);
  if (open) return { kind: 'open', name: open[1].trim() };
  return null;
}
const APPS = { youtube: 'YouTube', 'ইউটিউব': 'YouTube', facebook: 'Facebook', 'ফেসবুক': 'Facebook', whatsapp: 'WhatsApp', camera: 'Camera', 'ক্যামেরা': 'Camera', maps: 'Maps', messenger: 'Messenger', bkash: 'bKash', 'বিকাশ': 'bKash' };
function commandReply(c, l) {
  const bn = l === 'bn';
  switch (c.kind) {
    case 'alarm':
      if (c.hour == null) return bn ? 'অ্যালার্ম দিতে ঘড়ি অ্যাপ খুলে দিয়েছি।' : 'I opened the clock app so you can set the alarm.';
      return bn ? `${timeText(c.hour, c.minute, 'bn')}-এ অ্যালার্ম দেওয়া হয়েছে।` : `Alarm set for ${timeText(c.hour, c.minute, 'en')}.`;
    case 'timer': {
      const h = Math.floor(c.minutes / 60), m = c.minutes % 60;
      if (bn) return `টাইমার চালু হয়েছে: ${[h && `${bnDigits(h)} ঘণ্টা`, m && `${bnDigits(m)} মিনিট`].filter(Boolean).join(' ')}।`;
      return `Timer set for ${[h && `${h} hour${h === 1 ? '' : 's'}`, m && `${m} minute${m === 1 ? '' : 's'}`].filter(Boolean).join(' ')}.`;
    }
    case 'torch': return c.on ? (bn ? 'টর্চ জ্বালানো হয়েছে।' : 'Flashlight on.') : (bn ? 'টর্চ নেভানো হয়েছে।' : 'Flashlight off.');
    case 'open': {
      const name = APPS[c.name] || c.name.replace(/\b\w/g, (x) => x.toUpperCase());
      return bn ? `${name} খোলা হচ্ছে।` : `Opening ${name}.`;
    }
  }
  return null;
}

/* ------------------------------------------------------------------ */
/* Demo phone                                                          */
/* ------------------------------------------------------------------ */
const chat = $('#chat');
const composer = $('#composer');
const ask = $('#ask');
const TRIES = {
  explain: 'Explain photosynthesis simply',
  golpo: 'আমাকে একটা ছোট গল্প বলো',
  kemon: 'kemon acho?',
  alarm: 'Set an alarm for 6:30 am',
  torch: 'টর্চ জ্বালাও',
};
const CANNED = {
  'explain photosynthesis simply': 'Plants catch sunlight with the green pigment in their leaves, called chlorophyll. They use that energy to turn water and carbon dioxide from the air into sugar, which is their food. Oxygen is left over, and they let it out: that is the air we breathe.',
  'আমাকে একটা ছোট গল্প বলো': 'এক রাতে গ্রামে হঠাৎ বিদ্যুৎ চলে গেল। চারদিক অন্ধকার, শুধু রিনার ঘরে একটা হারিকেন জ্বলছিল। পাশের বাড়ির ছেলেমেয়েরা সেই আলোয় এসে পড়া শেষ করল। সেদিন রিনা বুঝল, ছোট একটা আলোও অনেককে পথ দেখাতে পারে।',
  'kemon acho': 'ভালো আছি, ধন্যবাদ! তুমি কেমন আছো? আজ কী নিয়ে কথা বলতে চাও?',
};
let busy = false;

function addMsg(cls, text) {
  const el = document.createElement('div');
  el.className = `msg ${cls}`;
  if (text != null) el.textContent = text;
  chat.append(el);
  chat.scrollTop = chat.scrollHeight;
  return el;
}

async function stream(el, text) {
  const caret = document.createElement('span');
  caret.className = 'caret';
  el.append(caret);
  const parts = text.match(/\S+\s*/g) || [text];
  for (const p of parts) {
    caret.before(p);
    chat.scrollTop = chat.scrollHeight;
    if (!reduceMotion) await new Promise((r) => setTimeout(r, 34 + Math.random() * 60));
  }
  caret.remove();
}

async function send(text) {
  text = text.trim();
  if (!text || busy) return;
  busy = true;
  setBusy(true);
  addMsg('me', text);
  const l = detectLanguage(text) || lang;
  const command = parseCommand(text);
  await new Promise((r) => setTimeout(r, reduceMotion ? 0 : 420));
  if (command) {
    const el = addMsg('ai action', commandReply(command, l));
    if (command.kind === 'torch') setTorch(command.on);
    void el;
  } else {
    const key = text.toLowerCase().replace(/[?!.।]+$/g, '').trim();
    const reply = CANNED[key] ?? (l === 'bn'
      ? 'এটা একটা ওয়েবসাইটের ডেমো, তাই এখানে আমি আসলে ভাবতে পারি না। অ্যাপে আপনার ফোনের মডেল নিজেই এর উত্তর লিখবে, ইন্টারনেট ছাড়াই।'
      : 'This is a demo on a website, so I can’t really think here. In the app, the model on your phone writes the answer itself, with no internet.');
    await stream(addMsg('ai'), reply);
  }
  busy = false;
  setBusy(false);
}
function setBusy(b) {
  $('#send').disabled = b;
  for (const c of $$('#tries .chip')) c.disabled = b;
}
composer.addEventListener('submit', (e) => { e.preventDefault(); const v = ask.value; ask.value = ''; send(v); });
for (const c of $$('#tries .chip')) c.addEventListener('click', () => send(TRIES[c.dataset.try]));

const offlineBox = $('#offline');
offlineBox.addEventListener('change', () => {
  const off = offlineBox.checked;
  body.classList.toggle('offline', off);
  $('#netchip').textContent = off ? t('offline') : t('online');
  addMsg('note', off ? t('netOff') : t('netOn'));
  scene?.setOffline(off);
});

function tick() {
  const d = new Date();
  $('#clock').textContent = `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}
tick(); setInterval(tick, 30000);

/* Torch: a cold white beam that follows the pointer. */
let torchTimer = 0;
function setTorch(on) {
  body.classList.toggle('torch-on', on);
  clearTimeout(torchTimer);
  if (on) torchTimer = setTimeout(() => body.classList.remove('torch-on'), 9000);
}
addEventListener('pointermove', (e) => {
  root.style.setProperty('--tx', `${e.clientX}px`);
  root.style.setProperty('--ty', `${e.clientY}px`);
}, { passive: true });

/* ------------------------------------------------------------------ */
/* Models                                                              */
/* ------------------------------------------------------------------ */
const MODELS = [
  { name: 'Qwen3 0.6B', fam: 'Qwen3', gb: 0.48, ram: 2, bn: 'basic', lic: 'Apache-2.0' },
  { name: 'Qwen3 1.7B', fam: 'Qwen3', gb: 1.28, ram: 3, bn: 'basic', lic: 'Apache-2.0' },
  { name: 'Qwen3 4B', fam: 'Qwen3', gb: 2.5, ram: 6, bn: 'good', lic: 'Apache-2.0' },
  { name: 'Gemma 3 1B', fam: 'Gemma 3', gb: 0.81, ram: 3, bn: 'basic', lic: 'gemma' },
  { name: 'Gemma 3 4B', fam: 'Gemma 3', gb: 2.49, ram: 6, bn: 'good', lic: 'gemma' },
  { name: 'Llama 3.2 1B', fam: 'Llama 3.2', gb: 0.81, ram: 3, bn: 'limited', lic: 'llama3.2' },
  { name: 'Llama 3.2 3B', fam: 'Llama 3.2', gb: 2.02, ram: 4, bn: 'limited', lic: 'llama3.2' },
  { name: 'Phi 4 mini', fam: 'Phi 4', gb: 2.49, ram: 6, bn: 'limited', lic: 'MIT' },
];
const RANK = { good: 2, basic: 1, limited: 0 };
const deviceRam = navigator.deviceMemory || null;
const cores = navigator.hardwareConcurrency || null;
const isPhone = /Android|iPhone|iPad|Mobile/i.test(navigator.userAgent);
function bestFor(ram) {
  const fits = MODELS.filter((m) => m.ram <= ram);
  fits.sort((a, b) => RANK[b.bn] - RANK[a.bn] || b.gb - a.gb);
  return fits[0] || MODELS[0];
}
const pick = deviceRam ? bestFor(deviceRam) : null;

function renderFit() {
  const el = $('#fittext');
  if (!deviceRam) { el.innerHTML = t('fitNone'); return; }
  el.innerHTML = (isPhone ? t('fit') : t('fitPc'))(deviceRam, pick.name);
}

/* Gauges: needles on damped springs. */
const gauges = $$('.gauge').map((g) => {
  const svg = $('svg', g);
  const kind = g.dataset.gauge;
  const max = kind === 'fit' ? 3 : 12;
  let ticks = '';
  for (let i = 0; i <= 12; i++) {
    const a = Math.PI * (1 - i / 12), r1 = i % 3 ? 44 : 40, r2 = 50;
    ticks += `<line x1="${60 + Math.cos(a) * r1}" y1="${66 - Math.sin(a) * r1}" x2="${60 + Math.cos(a) * r2}" y2="${66 - Math.sin(a) * r2}" stroke="${i % 3 ? '#3a4a70' : '#93a6c9'}" stroke-width="${i % 3 ? 1.2 : 2}" stroke-linecap="round"/>`;
  }
  svg.innerHTML = `<path d="M10 66 A50 50 0 0 1 110 66" fill="none" stroke="#1a2542" stroke-width="10" stroke-linecap="round"/>${ticks}
    <g class="needle"><line x1="60" y1="66" x2="60" y2="24" stroke="#ffb04a" stroke-width="3" stroke-linecap="round"/><circle cx="60" cy="66" r="6" fill="#ffd89a"/></g>`;
  const value = kind === 'ram' ? deviceRam : kind === 'cpu' ? cores : (pick || MODELS[1]).gb;
  const label = kind === 'ram' ? (deviceRam ? `${deviceRam} GB` : '?') : kind === 'cpu' ? (cores ?? '?') : `${(pick || MODELS[1]).gb} GB`;
  return { needle: $('.needle', svg), val: $('.val', g), target: value == null ? 0.04 : clamp(value / max), label, a: 0, v: 0, on: false };
});
function runGauges() {
  for (const g of gauges) { g.on = true; g.val.textContent = lang === 'bn' ? bnDigits(g.label) : g.label; }
  if (reduceMotion) { for (const g of gauges) { g.a = g.target; draw(g); } return; }
  let last = performance.now();
  const step = (now) => {
    const dt = Math.min(0.033, (now - last) / 1000); last = now;
    let moving = false;
    for (const g of gauges) {
      const k = 55, c = 7.5; // a little overshoot, then settle, like a real needle
      g.v += (k * (g.target - g.a) - c * g.v) * dt;
      g.a += g.v * dt;
      if (Math.abs(g.v) > 0.0005 || Math.abs(g.target - g.a) > 0.0005) moving = true;
      draw(g);
    }
    if (moving) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}
function draw(g) { g.needle.setAttribute('transform', `rotate(${-90 + g.a * 180} 60 66)`); }

/* Model ring */
const ring = $('#ring');
const ringwrap = $('#ringwrap');
let rot = 0, rotV = 0, dragging = false;
const step = 360 / MODELS.length;
function renderRing() {
  const s = S[lang];
  ring.innerHTML = MODELS.map((m) => `
    <article class="model">
      ${pick && m.name === pick.name ? `<span class="fit">${s.fitTag}</span>` : ''}
      <h3>${m.name}</h3>
      <dl>
        <dt>${s.size}</dt><dd>${lang === 'bn' ? bnDigits(m.gb) : m.gb} GB</dd>
        <dt>${s.ram}</dt><dd>${lang === 'bn' ? bnDigits(m.ram) : m.ram}+ GB</dd>
        <dt>${s.bn}</dt><dd>${s.q[m.bn]}</dd>
        <dt>${s.license}</dt><dd>${s.lic[m.lic]}</dd>
      </dl>
      <span class="shade"></span>
    </article>`).join('');
  layoutRing();
}
function radius() { return small.matches ? 300 : 380; }
function layoutRing() {
  const r = radius();
  $$('.model', ring).forEach((el, i) => {
    const a = i * step;
    el.style.transform = `rotateY(${a}deg) translateZ(${r}px)`;
    const rel = ((((a + rot) % 360) + 540) % 360) - 180; // -180..180, 0 = facing us
    el.style.setProperty('--shade', String(clamp(Math.abs(rel) / 110, 0, 0.85)));
    el.classList.toggle('front', Math.abs(rel) < step / 2);
  });
  ring.style.transform = `translateZ(${-r}px) rotateY(${rot}deg)`;
  const i = ((Math.round(-rot / step) % MODELS.length) + MODELS.length) % MODELS.length;
  $('#ringname').textContent = S[lang].of(i + 1, MODELS.length, MODELS[i].name);
}
function snapTo(target) {
  const from = rot, start = performance.now(), dur = reduceMotion ? 1 : 700;
  const ease = (x) => 1 - Math.pow(1 - x, 4);
  const go = (now) => {
    const k = clamp((now - start) / dur);
    rot = lerp(from, target, ease(k)); layoutRing();
    if (k < 1 && !dragging) requestAnimationFrame(go);
  };
  requestAnimationFrame(go);
}
const nearest = () => Math.round(rot / step) * step;
$('#prev').addEventListener('click', () => snapTo(nearest() + step));
$('#next').addEventListener('click', () => snapTo(nearest() - step));
ringwrap.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowLeft') { e.preventDefault(); snapTo(nearest() + step); }
  if (e.key === 'ArrowRight') { e.preventDefault(); snapTo(nearest() - step); }
});
let lastX = 0, lastT = 0;
ringwrap.addEventListener('pointerdown', (e) => {
  if (e.target.closest('button')) return;
  dragging = true; lastX = e.clientX; lastT = performance.now(); rotV = 0;
  ringwrap.classList.add('drag'); ringwrap.setPointerCapture(e.pointerId);
});
ringwrap.addEventListener('pointermove', (e) => {
  if (!dragging) return;
  const now = performance.now(), dx = e.clientX - lastX;
  rot += dx * 0.28; rotV = (dx * 0.28) / Math.max(1, now - lastT) * 16;
  lastX = e.clientX; lastT = now; layoutRing();
});
const endDrag = () => {
  if (!dragging) return;
  dragging = false; ringwrap.classList.remove('drag');
  snapTo(Math.round((rot + rotV * 8) / step) * step);
};
ringwrap.addEventListener('pointerup', endDrag);
ringwrap.addEventListener('pointercancel', endDrag);
small.addEventListener('change', layoutRing);
if (pick) rot = -MODELS.indexOf(pick) * step;

/* ------------------------------------------------------------------ */
/* Speak & do panel                                                    */
/* ------------------------------------------------------------------ */
const face = $('#face');
const say = $('#say');
const CMDS = {
  alarm: { en: 'Set an alarm for 7 am', bn: 'সকাল ৭টায় অ্যালার্ম দাও' },
  timer: { en: 'Timer for 10 minutes', bn: '১০ মিনিটের টাইমার দাও' },
  torch: { en: 'Turn on the flashlight', bn: 'টর্চ জ্বালাও' },
  open: { en: 'Open YouTube', bn: 'ইউটিউব খোলো' },
};
function drawFace(kind) {
  const tick = (n, r1, r2, w) => Array.from({ length: n }, (_, i) => {
    const a = (i / n) * Math.PI * 2;
    return `<line x1="${80 + Math.sin(a) * r1}" y1="${80 - Math.cos(a) * r1}" x2="${80 + Math.sin(a) * r2}" y2="${80 - Math.cos(a) * r2}" stroke="#93a6c9" stroke-width="${w}" stroke-linecap="round"/>`;
  }).join('');
  if (kind === 'alarm') {
    face.innerHTML = `<circle cx="80" cy="80" r="66" fill="#0b1020" stroke="#2a3550" stroke-width="3"/>${tick(12, 54, 60, 2.5)}
      <line class="hand" x1="80" y1="80" x2="80" y2="44" stroke="#fbe9cc" stroke-width="5" stroke-linecap="round" style="transform-origin:80px 80px;transform:rotate(210deg);transition:transform 1.2s var(--ease-out)"/>
      <line x1="80" y1="80" x2="80" y2="28" stroke="#ffb04a" stroke-width="3" stroke-linecap="round"/><circle cx="80" cy="80" r="6" fill="#ffb04a"/>`;
  } else if (kind === 'timer') {
    face.innerHTML = `<circle cx="80" cy="80" r="62" fill="none" stroke="#1a2542" stroke-width="12"/>
      <circle cx="80" cy="80" r="62" fill="none" stroke="#ffb04a" stroke-width="12" stroke-linecap="round" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100" transform="rotate(-90 80 80)" style="transition:stroke-dashoffset 1.6s var(--ease-out)" class="arc"/>
      <text x="80" y="92" text-anchor="middle" fill="#fbe9cc" font-size="34" font-weight="700" font-family="Anek Bangla">10:00</text>`;
  } else if (kind === 'torch') {
    face.innerHTML = `<defs><radialGradient id="beam" cx="50%" cy="0%" r="100%"><stop offset="0" stop-color="#eef3ff" stop-opacity=".9"/><stop offset="1" stop-color="#eef3ff" stop-opacity="0"/></radialGradient></defs>
      <path d="M62 64 L20 160 L140 160 L98 64 Z" fill="url(#beam)" opacity=".75"/>
      <rect x="62" y="8" width="36" height="60" rx="8" fill="#2a3550"/><rect x="66" y="58" width="28" height="8" rx="3" fill="#eef3ff"/>`;
  } else {
    face.innerHTML = Array.from({ length: 9 }, (_, i) => {
      const x = 22 + (i % 3) * 42, y = 22 + Math.floor(i / 3) * 42, hit = i === 4;
      return `<rect x="${x}" y="${y}" width="32" height="32" rx="9" fill="${hit ? '#ffb04a' : '#1a2542'}" ${hit ? 'style="transform-origin:80px 80px;animation:rise .6s var(--ease-out) both"' : ''}/>`;
    }).join('') + '<path d="M90 92 l-12 -7 v14 z" fill="#1b1206"/>';
  }
  requestAnimationFrame(() => requestAnimationFrame(() => {
    const hand = $('.hand', face); if (hand) hand.style.transform = 'rotate(210deg)';
    const arc = $('.arc', face); if (arc) arc.style.strokeDashoffset = '0';
  }));
}
for (const b of $$('.cmd')) {
  b.addEventListener('click', () => {
    for (const o of $$('.cmd')) o.setAttribute('aria-pressed', String(o === b));
    const kind = b.dataset.cmd, said = CMDS[kind][lang];
    const reply = commandReply(parseCommand(said), lang);
    drawFace(kind);
    say.innerHTML = '';
    say.append(reply);
    const sm = document.createElement('small'); sm.textContent = `“${said}”`; say.append(sm);
    if (kind === 'torch') setTorch(!body.classList.contains('torch-on'));
  });
}
drawFace('open');

/* ------------------------------------------------------------------ */
/* The lantern scene                                                    */
/* ------------------------------------------------------------------ */
let scene = null;

// Where the lantern stands on screen: in its layout slot in the hero, then
// in the right gutter (or out of frame when there is no gutter), so it never
// sits under text.
const spots = $$('.lampspot');
const howWrap = $('#how .wrap');
const easeInOut = (x) => x * x * (3 - 2 * x);
function lampTarget(W, H) {
  const r = spots.map((e) => e.getBoundingClientRect()).find((b) => b.width > 0) || { left: W * 0.6, top: H * 0.3, width: 200, height: 360 };
  const hero = { x: r.left + r.width / 2, y: r.top + r.height / 2, size: r.height * 0.9 };
  const gutter = W - howWrap.getBoundingClientRect().right;
  const post = gutter >= 120
    ? { x: W - gutter / 2, y: H * 0.84, size: Math.min(gutter * 1.2, 170) }
    : { x: W + 180, y: H * 0.95, size: 160 };
  const p = easeInOut(clamp((scrollY - H * 0.2) / (H * 0.8)));
  return { x: lerp(hero.x, post.x, p), y: lerp(hero.y, post.y, p), size: lerp(hero.size, post.size, p) };
}

function createScene(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setClearColor(0x0b1020, 1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const lowEnd = (navigator.hardwareConcurrency || 4) <= 4 || small.matches;
  renderer.setPixelRatio(Math.min(devicePixelRatio, lowEnd ? 1.25 : 1.75));

  const world = new THREE.Scene();
  world.fog = new THREE.Fog(0x0b1020, 5, 24);
  const sky = document.createElement('canvas');
  sky.width = 2; sky.height = 256;
  const sx = sky.getContext('2d');
  const sg = sx.createLinearGradient(0, 0, 0, 256);
  sg.addColorStop(0, '#111a36'); sg.addColorStop(0.55, '#0b1020'); sg.addColorStop(1, '#0b1020');
  sx.fillStyle = sg; sx.fillRect(0, 0, 2, 256);
  const skyTex = new THREE.CanvasTexture(sky);
  skyTex.colorSpace = THREE.SRGBColorSpace;
  world.background = skyTex;
  const camera = new THREE.PerspectiveCamera(34, 1, 0.05, 120);

  // Moonlight, very little of it: the lantern does the modelling.
  const hemi = new THREE.HemisphereLight(0x50649a, 0x07080c, 0.32);
  world.add(hemi);
  const moon = new THREE.DirectionalLight(0x7f97cf, 0.35);
  moon.position.set(-4, 6, -6);
  world.add(moon);

  // Table with a painted wood grain.
  const grain = document.createElement('canvas');
  grain.width = 512; grain.height = 512;
  const gx = grain.getContext('2d');
  gx.fillStyle = '#3a291c'; gx.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 140; i++) {
    gx.strokeStyle = `rgba(${20 + Math.random() * 30},${12 + Math.random() * 14},${6},${0.15 + Math.random() * 0.25})`;
    gx.lineWidth = 1 + Math.random() * 2.5;
    gx.beginPath();
    const y = Math.random() * 512;
    gx.moveTo(0, y);
    for (let x = 0; x <= 512; x += 32) gx.lineTo(x, y + Math.sin(x / 60 + i) * 6 + Math.random() * 2);
    gx.stroke();
  }
  const woodTex = new THREE.CanvasTexture(grain);
  woodTex.colorSpace = THREE.SRGBColorSpace;
  woodTex.wrapS = woodTex.wrapT = THREE.RepeatWrapping;
  woodTex.repeat.set(22, 11);
  woodTex.anisotropy = 4;
  const table = new THREE.Mesh(new THREE.BoxGeometry(70, 0.14, 34), new THREE.MeshStandardMaterial({ map: woodTex, roughness: 0.78, metalness: 0 }));
  table.position.set(0, -0.07, -8);
  table.receiveShadow = true;
  world.add(table);

  // A hurricane lantern, built from turned profiles like the real thing.
  const lantern = new THREE.Group();
  const tin = new THREE.MeshStandardMaterial({ color: 0x8c7046, metalness: 0.55, roughness: 0.42 });
  const darkTin = new THREE.MeshStandardMaterial({ color: 0x2b2a2a, metalness: 0.5, roughness: 0.55 });
  const lathe = (pts, mat, seg = 48) => {
    const m = new THREE.Mesh(new THREE.LatheGeometry(pts.map(([x, y]) => new THREE.Vector2(x, y)), seg), mat);
    m.castShadow = true; m.receiveShadow = true; return m;
  };
  lantern.add(lathe([[0, 0], [0.3, 0], [0.34, 0.03], [0.36, 0.1], [0.35, 0.17], [0.3, 0.21], [0.16, 0.24], [0.12, 0.25], [0, 0.25]], tin));
  lantern.add(lathe([[0, 0.24], [0.13, 0.24], [0.135, 0.3], [0.1, 0.31], [0, 0.31]], darkTin, 32));
  const glassMat = new THREE.MeshStandardMaterial({ color: 0xffe3b8, transparent: true, opacity: 0.16, roughness: 0.05, metalness: 0, side: THREE.DoubleSide, depthWrite: false, emissive: 0xff9a40, emissiveIntensity: 0.22 });
  const globe = lathe([[0.11, 0.31], [0.18, 0.36], [0.235, 0.45], [0.245, 0.53], [0.22, 0.63], [0.15, 0.71], [0.1, 0.76]], glassMat, 48);
  globe.castShadow = false;
  lantern.add(globe);
  lantern.add(lathe([[0, 0.92], [0.06, 0.92], [0.07, 0.86], [0.2, 0.8], [0.22, 0.77], [0.12, 0.75], [0, 0.75]], tin));
  lantern.add(lathe([[0, 0.98], [0.05, 0.98], [0.05, 0.92], [0, 0.92]], darkTin, 24));
  // Guard wires around the globe: they throw the striped shadows.
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2 + 0.3;
    const pts = [[0.2, 0.31], [0.27, 0.42], [0.285, 0.53], [0.26, 0.65], [0.2, 0.76]].map(([r, y]) => new THREE.Vector3(Math.cos(a) * r, y, Math.sin(a) * r));
    const wire = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 24, 0.008, 6), darkTin);
    wire.castShadow = true; lantern.add(wire);
  }
  // The two side tubes that feed air down to the burner.
  for (const s of [-1, 1]) {
    const pts = [[0.34, 0.16], [0.39, 0.4], [0.37, 0.66], [0.22, 0.8]].map(([r, y]) => new THREE.Vector3(s * r, y, 0));
    const tube = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 32, 0.022, 10), tin);
    tube.castShadow = true; lantern.add(tube);
  }
  const bail = new THREE.Mesh(new THREE.TorusGeometry(0.33, 0.009, 8, 40, Math.PI), darkTin);
  bail.position.y = 0.86; bail.rotation.y = Math.PI / 2; bail.castShadow = true;
  lantern.add(bail);

  // The flame: a soft teardrop shader that breathes.
  const flameMat = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    uniforms: { uTime: { value: 0 } },
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `varying vec2 vUv; uniform float uTime;
      void main(){
        vec2 p = vUv * 2.0 - 1.0;
        float y = p.y;
        p.x += sin(uTime * 7.0 + y * 4.0) * 0.07 * (y + 1.0) + sin(uTime * 13.0) * 0.02 * (y + 1.0);
        float w = mix(0.62, 0.05, smoothstep(-0.9, 1.0, y));
        float d = abs(p.x) / w;
        float body = exp(-d * d * 2.2) * smoothstep(1.0, 0.25, y) * smoothstep(-1.0, -0.6, y);
        float core = exp(-d * d * 7.0) * smoothstep(0.4, -0.5, y) * smoothstep(-1.0, -0.55, y);
        vec3 col = mix(vec3(1.0, 0.42, 0.08), vec3(1.0, 0.78, 0.38), smoothstep(-0.6, 0.5, -y));
        col += vec3(1.0, 0.95, 0.8) * core;
        vec3 blue = vec3(0.25, 0.4, 1.0) * smoothstep(-0.55, -0.85, y) * exp(-d * d * 3.0);
        gl_FragColor = vec4(col * body + blue, body);
      }`,
  });
  const flame = new THREE.Mesh(new THREE.PlaneGeometry(0.1, 0.21), flameMat);
  flame.position.y = 0.43;
  lantern.add(flame);

  const halo = document.createElement('canvas');
  halo.width = halo.height = 128;
  const hx = halo.getContext('2d');
  const hg = hx.createRadialGradient(64, 64, 0, 64, 64, 64);
  hg.addColorStop(0, 'rgba(255,190,110,0.55)'); hg.addColorStop(0.35, 'rgba(255,140,60,0.18)'); hg.addColorStop(1, 'rgba(255,120,40,0)');
  hx.fillStyle = hg; hx.fillRect(0, 0, 128, 128);
  const glowSprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(halo), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
  glowSprite.scale.setScalar(0.9);
  glowSprite.position.y = 0.45;
  lantern.add(glowSprite);

  const lamp = new THREE.PointLight(0xffa04c, 3.2, 0, 2);
  lamp.position.y = 0.45;
  lamp.castShadow = true;
  lamp.shadow.mapSize.set(lowEnd ? 512 : 1024, lowEnd ? 512 : 1024);
  lamp.shadow.bias = -0.003;
  lamp.shadow.radius = 4;
  lamp.shadow.camera.near = 0.05;
  lantern.add(lamp);
  world.add(lantern);

  // Moths and dust drifting in the light.
  const N = lowEnd ? 50 : 110;
  const motes = new Float32Array(N * 3), seeds = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const r = 0.35 + Math.random() * 1.4, a = Math.random() * Math.PI * 2;
    motes.set([Math.cos(a) * r, 0.1 + Math.random() * 1.6, Math.sin(a) * r], i * 3);
    seeds[i] = Math.random() * 100;
  }
  const moteGeo = new THREE.BufferGeometry();
  moteGeo.setAttribute('position', new THREE.BufferAttribute(motes.slice(), 3));
  const moteMat = new THREE.PointsMaterial({ color: 0xffc98a, size: 0.012, transparent: true, opacity: 0.75, blending: THREE.AdditiveBlending, depthWrite: false });
  const moteCloud = new THREE.Points(moteGeo, moteMat);
  world.add(moteCloud);

  // The city across the dark: windows that go out when the internet does.
  const city = new THREE.Group();
  const buildingMat = new THREE.MeshBasicMaterial({ color: 0x060914, fog: false, transparent: true });
  const winGeo = new THREE.PlaneGeometry(0.22, 0.3);
  const winMat = new THREE.MeshBasicMaterial({ toneMapped: false, fog: false });
  const windows = [];
  // A fixed skyline (seeded), kept to the lantern's right and below the nav band, so no lit window sits behind the copy.
  let seed = 7;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  let x = -23;
  while (x < 70) {
    const w = 3 + rand() * 5, h = 5 + rand() * 9, z = -52 - rand() * 14;
    const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, 3), buildingMat);
    b.position.set(x + w / 2, h / 2 - 9, z);
    city.add(b);
    for (let wx = 0.5; wx < w - 0.3; wx += 0.9) for (let wy = 0.8; wy < h - 0.5; wy += 1.2) {
      if (rand() < 0.55) windows.push([x + wx + 0.2, wy - 9, z + 1.51]);
    }
    x += w + rand() * 1.2;
  }
  const winMesh = new THREE.InstancedMesh(winGeo, winMat, windows.length);
  const m4 = new THREE.Matrix4(), col = new THREE.Color();
  const onColors = [];
  windows.forEach((p, i) => {
    m4.makeTranslation(p[0], p[1], p[2]);
    winMesh.setMatrixAt(i, m4);
    const c = Math.random() < 0.18 ? new THREE.Color(0xb7c8ee) : new THREE.Color(0xffc67a);
    c.multiplyScalar(0.55 + Math.random() * 0.45);
    onColors.push(c);
    winMesh.setColorAt(i, c);
  });
  city.add(winMesh);
  // A phone tower with its blinking warning lamp.
  const towerPts = [];
  for (let i = 0; i < 12; i++) {
    const y0 = i * 1.2 - 3.5, y1 = y0 + 1.2, w0 = 0.9 - i * 0.065, w1 = w0 - 0.065;
    towerPts.push(-w0, y0, 0, -w1, y1, 0, w0, y0, 0, w1, y1, 0, -w0, y0, 0, w1, y1, 0, w0, y0, 0, -w1, y1, 0);
  }
  const towerGeo = new THREE.BufferGeometry();
  towerGeo.setAttribute('position', new THREE.Float32BufferAttribute(towerPts, 3));
  const tower = new THREE.LineSegments(towerGeo, new THREE.LineBasicMaterial({ color: 0x24314f, fog: false }));
  tower.position.set(22, -5, -48); tower.scale.setScalar(1.6);
  city.add(tower);
  const beaconMat = new THREE.SpriteMaterial({ color: 0xff4a3a, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, fog: false, map: glowSprite.material.map });
  const beacon = new THREE.Sprite(beaconMat);
  beacon.scale.setScalar(1.4);
  beacon.position.set(22, 13.4, -48);
  city.add(beacon);
  world.add(city);

  // Offline: the city's windows go out in a ripple; the lantern stays lit.
  let cityOn = 1, cityTarget = 1, offAt = -100; // the city starts fully lit
  const order = windows.map((_, i) => i).sort(() => Math.random() - 0.5);
  const delays = new Float32Array(windows.length);
  order.forEach((idx, k) => { delays[idx] = (k / windows.length) * 1.4; });
  function setOffline(off) {
    cityTarget = off ? 0 : 1;
    offAt = clock.getElapsedTime() - (reduceMotion ? 10 : 0); // no ripple without motion: switch at once
    if (reduceMotion) requestAnimationFrame(frame);
  }

  // Framing: the lantern sits right of the copy, and drifts into the corner on scroll.
  const pointer = { x: 0, y: 0, sx: 0, sy: 0 };
  addEventListener('pointermove', (e) => { pointer.x = e.clientX / innerWidth - 0.5; pointer.y = e.clientY / innerHeight - 0.5; }, { passive: true });
  let W = 1, H = 1;
  function resize() {
    W = innerWidth; H = innerHeight;
    renderer.setSize(W, H, false);
    camera.aspect = W / H;
    camera.updateProjectionMatrix();
  }
  addEventListener('resize', resize);
  resize();

  const clock = new THREE.Clock();
  const target = new THREE.Vector3(0, 0.5, 0);
  const fovK = 2 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  const flamePos = new THREE.Vector3();
  let glow = 1, flick = 1, visible = true;
  document.addEventListener('visibilitychange', () => { visible = !document.hidden; if (visible) loop(); });

  function frame() {
    const tm = clock.getElapsedTime();
    const scrollP = clamp(scrollY / (H * 1.1));
    const mobile = W < 960;
    // Flicker: layered noise, eased so it never strobes.
    const n = Math.sin(tm * 7.3) * 0.5 + Math.sin(tm * 13.1 + 1.3) * 0.3 + Math.sin(tm * 2.1) * 0.4 + (Math.random() - 0.5) * 0.25;
    flick = lerp(flick, 1 + n * 0.08, reduceMotion ? 1 : 0.25);
    glow = reduceMotion ? 1 : flick;
    lamp.intensity = 3.2 * glow * (mobile ? 0.85 : 1);
    glassMat.emissiveIntensity = 0.22 * glow;
    glowSprite.material.opacity = 0.85 * glow;
    flameMat.uniforms.uTime.value = reduceMotion ? 0 : tm;
    flame.quaternion.copy(camera.quaternion);

    // Motes drift up through the light and wrap around.
    if (!reduceMotion) {
      const pos = moteGeo.attributes.position.array;
      for (let i = 0; i < N; i++) {
        const s = seeds[i];
        pos[i * 3] = motes[i * 3] + Math.sin(tm * 0.3 + s) * 0.12;
        pos[i * 3 + 1] = 0.1 + ((motes[i * 3 + 1] + tm * 0.04 + s) % 1.7);
        pos[i * 3 + 2] = motes[i * 3 + 2] + Math.cos(tm * 0.25 + s) * 0.12;
      }
      moteGeo.attributes.position.needsUpdate = true;
    }

    // City lights follow the switch.
    cityOn = lerp(cityOn, cityTarget, 0.06);
    const since = tm - offAt;
    for (let i = 0; i < windows.length; i++) {
      const on = cityTarget === 0 ? (since > delays[i] ? 0 : 1) : (since > delays[i] * 0.6 ? 1 : 0);
      col.copy(onColors[i]).multiplyScalar(on ? 1 : 0.035);
      winMesh.setColorAt(i, col);
    }
    winMesh.instanceColor.needsUpdate = true;
    // The city belongs to the hero; it sinks into the fog before any body text scrolls over it.
    const cityK = 1 - clamp((scrollP - 0.15) / 0.45);
    city.visible = cityK > 0.01;
    buildingMat.opacity = cityK;
    winMat.opacity = cityK; winMat.transparent = cityK < 1;
    tower.material.opacity = cityK; tower.material.transparent = true;
    beaconMat.opacity = (cityTarget ? (Math.sin(tm * 3) > 0.2 ? 0.95 : 0.1) : 0) * cityK;
    // The whole night drops a step when the grid goes; only the flame stays.
    hemi.intensity = 0.32 * (0.3 + 0.7 * cityOn);
    moon.intensity = 0.35 * (0.3 + 0.7 * cityOn);

    // Camera: a slow orbit with the pointer, pulled back as the page scrolls.
    pointer.sx = lerp(pointer.sx, reduceMotion ? 0 : pointer.x, 0.04);
    pointer.sy = lerp(pointer.sy, reduceMotion ? 0 : pointer.y, 0.04);
    const aim = lampTarget(W, H);
    const dist = clamp(H / (fovK * aim.size), 2.2, 40);
    const az = 0.42 + pointer.sx * 0.3 + scrollP * 0.15;
    const el = lerp(0.22, 0.4, scrollP) - pointer.sy * 0.06;
    camera.position.set(Math.sin(az) * Math.cos(el) * dist, 0.5 + Math.sin(el) * dist, Math.cos(az) * Math.cos(el) * dist);
    camera.lookAt(target);
    camera.setViewOffset(W, H, W / 2 - aim.x, H / 2 - aim.y, W, H);
    void mobile;

    renderer.render(world, camera);

    // Hand the lantern's position and brightness to the page's own lighting.
    flame.getWorldPosition(flamePos).project(camera);
    lightPage((flamePos.x * 0.5 + 0.5) * W, (-flamePos.y * 0.5 + 0.5) * H, glow);
  }
  // Slow GPU (old phone, software rendering): drop resolution and shadows once.
  let slowAvg = 16, frames = 0, degraded = false, lastT = performance.now();
  function loop() {
    if (!visible) return;
    const now = performance.now();
    slowAvg = lerp(slowAvg, now - lastT, 0.1); lastT = now;
    if (!degraded && ++frames > 45 && slowAvg > 45) {
      degraded = true;
      renderer.setPixelRatio(0.75);
      lamp.castShadow = false;
      resize();
    }
    frame();
    if (!reduceMotion) requestAnimationFrame(loop);
  }
  loop();
  if (reduceMotion) { addEventListener('scroll', () => requestAnimationFrame(frame), { passive: true }); addEventListener('resize', () => requestAnimationFrame(frame)); }
  return { setOffline };
}

/* Page lighting: shadows fall away from the flame. */
const litShadows = $$('.lit-shadow');
const phone = $('#phone');
const h1 = $('.hero h1');
const glyphSpans = $$('#glyphs span');
const glyphBox = $('#glyphs');
let frameNo = 0;
function lightPage(lx, ly, glow) {
  root.style.setProperty('--lx', `${lx.toFixed(1)}px`);
  root.style.setProperty('--ly', `${ly.toFixed(1)}px`);
  root.style.setProperty('--glow', glow.toFixed(3));
  if (small.matches && frameNo++ % 2) return; // half rate on phones
  const shadowAway = (el, k, set) => {
    const r = el.getBoundingClientRect();
    if (r.bottom < -100 || r.top > innerHeight + 100) return;
    const dx = r.left + r.width / 2 - lx, dy = r.top + r.height / 2 - ly;
    const d = Math.hypot(dx, dy) || 1;
    const f = k * clamp(700 / d, 0.4, 1.4);
    set(dx / d * f, dy / d * f, dx / d);
  };
  for (const el of litShadows) shadowAway(el, 26, (x, y) => { el.style.setProperty('--sx', `${x.toFixed(1)}px`); el.style.setProperty('--sy', `${(y + 18).toFixed(1)}px`); });
  shadowAway(phone, 46, (x, y, ux) => {
    phone.style.setProperty('--psx', `${x.toFixed(1)}px`); phone.style.setProperty('--psy', `${(y + 30).toFixed(1)}px`);
    phone.style.setProperty('--psx2', `${(x * 0.35).toFixed(1)}px`); phone.style.setProperty('--psy2', `${(y * 0.35 + 10).toFixed(1)}px`);
    phone.style.setProperty('--rimx', `${ux > 0 ? 2 : -2}px`);
    const pr = phone.getBoundingClientRect();
    const ang = Math.atan2(pr.left + pr.width / 2 - lx, -(pr.top + pr.height / 2 - ly)) * 180 / Math.PI;
    phone.style.setProperty('--la', `${ang.toFixed(1)}deg`);
    phone.style.setProperty('--shx', `${(ux * 46).toFixed(1)}px`);
  });
  shadowAway(h1, 10, (x, y) => { h1.style.setProperty('--tsx', `${x.toFixed(1)}px`); h1.style.setProperty('--tsy', `${(y + 4).toFixed(1)}px`); });
  // The big letters: a long soft shadow cast away from the flame, and a warm face where the light reaches.
  const gb = glyphBox.getBoundingClientRect();
  if (gb.bottom > 0 && gb.top < innerHeight) {
    for (const g of glyphSpans) {
      const r = g.getBoundingClientRect();
      const dx = r.left + r.width / 2 - lx, dy = r.top + r.height / 2 - ly;
      const d = Math.hypot(dx, dy) || 1, ux = dx / d, uy = dy / d;
      const warm = clamp(1.15 - d / (innerWidth * 1.3)) * glow;
      g.style.color = `rgb(${Math.round(26 + 70 * warm)}, ${Math.round(36 + 34 * warm)}, ${Math.round(67 - 30 * warm)})`;
      let sh = '';
      for (let i = 1; i <= 10; i++) sh += `${i > 1 ? ',' : ''}${(ux * i * 4).toFixed(1)}px ${(uy * i * 4).toFixed(1)}px ${(i * 1.2).toFixed(1)}px rgba(3,5,10,${(0.55 - i * 0.045).toFixed(2)})`;
      g.style.textShadow = sh;
    }
  }
}

try { scene = createScene($('#scene')); } catch { scene = null; }
// Without WebGL the lantern is still there: a fixed glow, lighting the page from the same spot.
if (!scene) {
  const place = () => lightPage(innerWidth * (small.matches ? 0.82 : 0.86), innerHeight * (small.matches ? 0.22 : 0.58), 1);
  addEventListener('resize', place); addEventListener('scroll', () => requestAnimationFrame(place), { passive: true });
  place();
}

/* ------------------------------------------------------------------ */
/* Scroll: smooth wheel, reveals, steps, bar                            */
/* ------------------------------------------------------------------ */
let lenis = null;
if (!reduceMotion && window.Lenis) {
  lenis = new window.Lenis({ lerp: 0.1, smoothWheel: true });
  const raf = (time) => { lenis.raf(time); requestAnimationFrame(raf); };
  requestAnimationFrame(raf);
}
for (const a of $$('a[href^="#"]')) {
  a.addEventListener('click', (e) => {
    const id = a.getAttribute('href');
    const el = id.length > 1 ? $(id) : null;
    if (!el && id !== '#top') return;
    e.preventDefault();
    if (lenis) lenis.scrollTo(id === '#top' ? 0 : el, { offset: -70, duration: 1.4 });
    else (el || body).scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth' });
    if (el) { el.setAttribute('tabindex', '-1'); el.focus({ preventScroll: true }); }
  });
}

const io = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    e.target.classList.add('in');
    if (e.target.id === 'instrument') runGauges();
    io.unobserve(e.target);
  }
}, { rootMargin: '0px 0px -12% 0px' });
for (const parent of new Set($$('.reveal').map((el) => el.parentElement))) {
  [...parent.children].filter((c) => c.classList.contains('reveal')).forEach((c, i) => { c.style.transitionDelay = `${Math.min(i, 6) * 80}ms`; });
}
$$('.reveal').forEach((el) => io.observe(el));

const steps = $('#steps');
const stepEls = $$('.step', steps);
const bar = $('#bar');
function onScroll() {
  bar.classList.toggle('solid', scrollY > 40);
  const r = steps.getBoundingClientRect();
  const p = clamp((innerHeight * 0.78 - r.top) / (r.height + innerHeight * 0.25));
  steps.style.setProperty('--p', p.toFixed(3));
  stepEls.forEach((s, i) => s.classList.toggle('on', p > i / 3 + 0.05));
}
addEventListener('scroll', onScroll, { passive: true });
onScroll();

/* Phone tilt toward the pointer, a little. */
const stage = $('.stage');
stage.addEventListener('pointermove', (e) => {
  if (reduceMotion || small.matches) return;
  const r = stage.getBoundingClientRect();
  phone.style.setProperty('--ry', `${(-10 + ((e.clientX - r.left) / r.width - 0.5) * 12).toFixed(2)}deg`);
  phone.style.setProperty('--rx', `${(4 - ((e.clientY - r.top) / r.height - 0.5) * 8).toFixed(2)}deg`);
});
stage.addEventListener('pointerleave', () => { phone.style.removeProperty('--ry'); phone.style.removeProperty('--rx'); });

/* Start */
let saved = null;
try { saved = localStorage.getItem('emberwit.lang'); } catch { /* no storage: use the browser's language */ }
setLang(saved || (/^bn\b/i.test(navigator.language) ? 'bn' : 'en'));
addMsg('ai', t('hello'));
