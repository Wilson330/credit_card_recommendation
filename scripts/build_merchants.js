// Builds lib/data/merchants.json from the unique merchant names that
// appear across cube_reward_rules.json / jiho_reward_rules.json.
//
// Classification is per-MERCHANT (what the store actually is), not
// per-scheme — some schemes mix categories (e.g. 樂饗購 has department
// stores, fast food, AND drugstores like 屈臣氏/康是美 in the same list).
//
// This is a first-pass AI classification, not verified against official
// sources. Anything pushed to _REVIEW_NOTES should be checked by a human
// before being treated as fact — see the printed review list after running.
//
// Usage: node scripts/build_merchants.js

const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'lib', 'data');
const ALLEN_DIR = path.join(DATA_DIR, 'allen');

function normalizeMerchantName(raw) {
  const CONSTRAINT_BRACKET_KEYWORDS = [
    '限', '不含', '僅', '需', '限定', '週', '街邊店', '儲值', '電子票券', '結帳',
  ];
  const match = raw.trim().match(/^(.*?)\s*[\(（](.+?)[\)）]\s*$/);
  if (match) {
    const bracketContent = match[2].trim();
    const looksLikeConstraint = CONSTRAINT_BRACKET_KEYWORDS.some((kw) =>
      bracketContent.includes(kw)
    );
    if (looksLikeConstraint) return match[1].trim();
  }
  return raw.trim();
}

// ---- gather the unique (name -> schemes[]) universe from real data ----

function collectMerchantUniverse() {
  const cubeRaw = JSON.parse(
    fs.readFileSync(path.join(ALLEN_DIR, 'cube_ALL_LEVELS_rewards.json'), 'utf8')
  );
  const jihoRaw = JSON.parse(
    fs.readFileSync(path.join(ALLEN_DIR, 'jiho_rewards.json'), 'utf8')
  );

  const CUBE_DEFERRED_SCHEMES = new Set(['慶生月', '童樂匯']);
  const JIHO_CONDITION_SCHEMES = new Set([
    '國內一般消費', '國外一般消費', '日本一般消費', '日本交通卡儲值',
  ]);

  const byName = new Map();

  for (const schemes of Object.values(cubeRaw)) {
    for (const [scheme, merchants] of Object.entries(schemes)) {
      if (CUBE_DEFERRED_SCHEMES.has(scheme)) continue;
      for (const rawName of Object.keys(merchants)) {
        const name = normalizeMerchantName(rawName);
        if (!byName.has(name)) byName.set(name, new Set());
        byName.get(name).add(scheme);
      }
    }
  }

  for (const schemes of Object.values(jihoRaw)) {
    for (const [scheme, merchants] of Object.entries(schemes)) {
      if (JIHO_CONDITION_SCHEMES.has(scheme)) continue;
      for (const rawName of Object.keys(merchants)) {
        const name = normalizeMerchantName(rawName);
        if (!byName.has(name)) byName.set(name, new Set());
        byName.get(name).add(scheme);
      }
    }
  }

  return byName;
}

// ---- classification ----
// { primary_category, tags, needsReview? }

const DINING = (tags = []) => ({ primary_category: 'dining', tags: ['restaurant', ...tags] });
const DEPT_STORE = (tags = []) => ({ primary_category: 'department_store', tags: ['mall', ...tags] });
const CONVENIENCE = (tags = []) => ({ primary_category: 'convenience_store', tags: ['chain_store', ...tags] });
const SUPERMARKET = (tags = []) => ({ primary_category: 'supermarket', tags: ['grocery', ...tags] });
const DRUGSTORE = (tags = []) => ({ primary_category: 'drugstore', tags: ['health_beauty', ...tags] });
const GAS = (tags = []) => ({ primary_category: 'gas_station', tags: ['fuel', ...tags] });
const DIGITAL = (tags = []) => ({ primary_category: 'digital', tags: [...tags] });
const TRAVEL = (tags = []) => ({ primary_category: 'travel', tags: [...tags] });
const HOTEL = (tags = []) => ({ primary_category: 'hotel', tags: ['lodging', ...tags] });
const RETAIL = (tags = []) => ({ primary_category: 'retail', tags: [...tags] });
const THEME_PARK = (tags = []) => ({ primary_category: 'theme_park', tags: ['attraction', ...tags] });

// Common alternate names — English brand names, abbreviations, common
// Chinese short forms. Applied uniformly to any merchant regardless of
// whether it came from Allen's crawl, the seed list, or the legacy demo
// set. First pass covering the most likely to actually get typed; not
// exhaustive, flagged for review same as everything else.
const ALIASES = {
  '7-ELEVEN (7-11) 實體門市': ['7-11', '7-ELEVEN', '小七', '統一超商'],
  '全家便利商店 實體門市': ['全家', 'FamilyMart'],
  '萊爾富實體門市': ['萊爾富', 'Hi-Life'],
  '全聯福利中心': ['全聯', 'PX Mart'],
  '麥當勞': ["McDonald's"],
  '屈臣氏': ['Watsons'],
  '康是美': ['Cosmed'],
  'IKEA宜家家居': ['IKEA', '宜家'],
  'UNIQLO': ['優衣庫'],
  'DAISO大創百貨': ['DAISO', '大創'],
  '誠品生活': ['誠品', 'Eslite'],
  'Google Play': ['Play Store'],
  '摩斯漢堡': ['MOS Burger', 'MOS'],
  '肯德基': ['KFC'],
  '漢堡王': ['Burger King'],
  '星巴克': ['Starbucks'],
  'cama café': ['cama'],
  '達美樂': ["Domino's", "Domino's Pizza"],
  '必勝客': ['Pizza Hut'],
  '寶雅': ['POYA'],
  '藏壽司': ['Kura Sushi'],
  '路易莎咖啡': ['路易莎', 'Louisa Coffee'],
  '晶英酒店': ['Silks Place'],

  // Second pass, 2026-08-06: filling out the rest of the directory rather
  // than stopping at the first 23 — airlines, malls, Japan brand English
  // names, ecommerce short forms, hotels, theme parks, a few Japanese
  // restaurant chain romanizations. Same review status as everything
  // else: not verified against official sources beyond general knowledge.
  // Airlines — English/short names are how these are commonly typed
  '土耳其航空': ['Turkish Airlines'],
  '大韓航空': ['Korean Air'],
  '中華航空': ['China Airlines', '華航'],
  '日本航空': ['JAL', 'Japan Airlines'],
  '卡達航空': ['Qatar Airways'],
  '台灣虎航': ['Tigerair Taiwan', '虎航'],
  '法國航空': ['Air France'],
  '長榮航空': ['EVA Air', '長榮'],
  '阿聯酋航空': ['Emirates'],
  '星宇航空': ['STARLUX', '星宇'],
  '國泰航空': ['Cathay Pacific'],
  '捷星航空': ['Jetstar'],
  '越捷航空': ['VietJet'],
  '新加坡航空': ['Singapore Airlines'],
  '達美航空': ['Delta', 'Delta Air Lines'],
  '酷航': ['Scoot'],
  '樂桃航空': ['Peach Aviation', '樂桃'],
  '聯合航空': ['United Airlines'],
  'ANA全日空': ['ANA', 'All Nippon Airways'],
  '亞洲航空': ['AirAsia'],
  // Department stores / malls — commonly shortened
  '新光三越': ['新光', 'Shin Kong Mitsukoshi'],
  '微風廣場': ['微風', 'Breeze Center'],
  '大葉高島屋': ['高島屋', 'Takashimaya'],
  '遠東百貨': ['遠百'],
  '環球購物中心': ['Global Mall'],
  'Big City遠東巨城購物中心': ['巨城', 'Big City'],
  'MITSUI OUTLET PARK(林口、台中港、台南)': ['三井OUTLET', 'MITSUI OUTLET PARK'],
  'Mitsui Shopping Park LaLaport(南港、台中)': ['LaLaport', '三井LaLaport'],
  // Japan department stores — English/romanized names
  '三越(日本)': ['Mitsukoshi'],
  '永旺(日本)': ['AEON', 'Aeon'],
  '高島屋(日本)': ['Takashimaya'],
  // Drugstores
  "三友藥妝Tomod's": ["Tomod's"],
  '松本清': ['Matsumoto Kiyoshi'],
  // Ecommerce — short forms
  '蝦皮購物': ['蝦皮', 'Shopee'],
  'momo購物網': ['momo'],
  'PChome 24h購物': ['PChome'],
  'Coupang 酷澎(台灣)': ['Coupang', '酷澎'],
  '淘寶/天貓': ['淘寶', '天貓', 'Taobao', 'Tmall'],
  // Hotels
  '東橫INN': ['Toyoko Inn'],
  '星野集團': ['Hoshino Resorts'],
  '六福萬怡酒店': ['Marriott', '萬怡'],
  // Theme parks
  '東京迪士尼樂園': ['Tokyo Disneyland', '迪士尼'],
  '東京迪士尼': ['Tokyo Disneyland', '迪士尼'],
  '大阪環球影城(USJ)': ['USJ', '環球影城'],
  '大阪環球影城': ['USJ', '環球影城'],
  '東京華納兄弟哈利波特影城': ['哈利波特影城', 'Harry Potter Studio Tour'],
  // Japanese restaurant chains — romanized names
  '一風堂': ['Ippudo'],
  '丸龜製麵': ['Marugame Seimen'],
  '吉野家': ['Yoshinoya'],
  '食其家': ['Sukiya'],
  '壽司郎': ['Sushiro'],
};

// Explicit per-merchant overrides where the merchant's own identity
// differs from what its scheme would suggest by default (the reason a
// per-scheme-only approach would have been wrong).
const OVERRIDES = {
  // 台塑家 — mixed: fuel, convenience, health retail, grocery, ecommerce
  '台塑石油加油站': GAS(),
  '台亞加油站': GAS(),
  '福懋加油站': GAS(),
  // note: this bracket sits mid-string ("...(限本島)加油站"), not at the
  // end, so normalizeMerchantName's trailing-bracket-only regex doesn't
  // strip it — the real match_value in cube_reward_rules.json also still
  // has "(限本島)" in it, so this key must match verbatim.
  '統一速邁樂(限本島)加油站': GAS(),
  '台塑生醫實體門市': RETAIL(['health_beauty', 'biotech']),
  '長庚生技實體門市': RETAIL(['health_beauty', 'biotech']),
  '台塑蔬菜實體門市': SUPERMARKET(['fresh_produce']),
  '台塑購物網': DIGITAL(['ecommerce']),
  '7-ELEVEN (7-11) 實體門市': CONVENIENCE(),
  '全家便利商店 實體門市': CONVENIENCE(),
  '萊爾富實體門市': CONVENIENCE(),

  // 全支付 — payment channel + supermarket
  '全支付國內合作通路': { primary_category: 'shopping', tags: ['payment_channel'], needsReview: true },
  '全支付國內通路': { primary_category: 'shopping', tags: ['payment_channel'], needsReview: true },
  '大全聯': SUPERMARKET(),
  '全聯福利中心': SUPERMARKET(),

  // 樂饗購 — mostly malls/dept stores + dining, but drugstores hide in here too
  '屈臣氏': DRUGSTORE(),
  '康是美': DRUGSTORE(),
  '誠品生活': { primary_category: 'retail', tags: ['bookstore', 'department_store'], needsReview: true },
  'Uber Eats': DINING(['delivery', 'app']),
  'foodpanda': DINING(['delivery', 'app']),
  '拉亞漢堡': DINING(['fast_food']),
  '% Arabica咖啡': DINING(['coffee']),
  '黑沃咖啡': DINING(['coffee']),
  'SUBWAY': DINING(['fast_food']),
  '50嵐': DINING(['beverage']),
  '麻古茶坊': DINING(['beverage']),
  '六扇門時尚湯鍋': DINING(['hot_pot']),
  '八方雲集': DINING(['fast_food']),
  '麥當勞': DINING(['fast_food']),

  // 集精選 — EV/mobility + supermarket + gas + convenience + home goods
  'U-POWER': { primary_category: 'ev_charging', tags: [] },
  'EVOASIS': { primary_category: 'ev_charging', tags: [] },
  'EVALUE': { primary_category: 'ev_charging', tags: [] },
  'TAIL': { primary_category: 'ev_charging', tags: [] },
  'iCharging': { primary_category: 'ev_charging', tags: [] },
  '車麻吉': { primary_category: 'mobility', tags: ['parking'], needsReview: true },
  'uTagGo': { primary_category: 'mobility', tags: ['parking'], needsReview: true },
  '家樂福(萬家福、樂家康)': SUPERMARKET(['hypermarket']),
  'LOPIA台灣': SUPERMARKET(),
  '全聯福利中心 實體門市': SUPERMARKET(),
  '台灣中油-直營站': GAS(),
  'IKEA宜家家居': RETAIL(['home_goods']),

  // 日本熱門商店 — Japan-specific chains
  '7-ELEVEN(日本)': CONVENIENCE(['japan']),
  'FamilyMart(日本)': CONVENIENCE(['japan']),
  'LAWSON(日本)': CONVENIENCE(['japan']),
  '東京迪士尼': THEME_PARK(['japan']),
  '大阪環球影城': THEME_PARK(['japan']),
  '永旺(日本)': DEPT_STORE(['japan']),
  '三越(日本)': DEPT_STORE(['japan']),
  '高島屋(日本)': DEPT_STORE(['japan']),
  'BIC CAMERA': RETAIL(['electronics', 'japan']),
  'Yodobashi': RETAIL(['electronics', 'japan']),
  '唐吉訶德': RETAIL(['discount_store', 'japan']),

  // 趣旅行 — theme parks and hotels called out specifically (not just "travel")
  '大阪環球影城(USJ)': THEME_PARK(),
  '東京迪士尼樂園': THEME_PARK(),
  '東京華納兄弟哈利波特影城': THEME_PARK(),
  '星野集團': HOTEL(),
  '全球迪士尼飯店': HOTEL(),
  '東橫INN': HOTEL(),
  '海外實體消費(含國外餐飲、飯店到店付款等)': {
    primary_category: 'travel', tags: ['overseas_general'], needsReview: true,
  },
};

// OTA / booking platforms: tagged 'hotel_booking' rather than 'hotel' —
// these book both domestic AND overseas hotels, so folding them into the
// 'hotel' tag would make the domestic-only 趣旅行 category rule (see
// SCHEMA.md) over-match international bookings too. Flagged for review
// since this line is a judgment call, not a confirmed fact.
const OTA_PLATFORMS = new Set(['Agoda', 'Airbnb', 'Booking.com', 'Trip.com', 'ezTravel易遊網', 'KKday', 'Klook']);
for (const name of OTA_PLATFORMS) {
  OVERRIDES[name] = { primary_category: 'travel', tags: ['ota', 'hotel_booking'], needsReview: true };
}

const AIRLINES = new Set([
  '土耳其航空', '大韓航空', '中華航空', '日本航空', '卡達航空', '台灣虎航', '亞洲航空',
  '法國航空', '長榮航空', '阿聯酋航空', '星宇航空', '國泰航空', '捷星航空', '越捷航空',
  '新加坡航空', '達美航空', '酷航', '樂桃航空', '聯合航空', 'ANA全日空',
]);
for (const name of AIRLINES) OVERRIDES[name] = TRAVEL(['airline']);

const TRAVEL_AGENCIES = new Set([
  '三賀旅行社', '山富旅遊', '五福旅遊', '可樂旅遊', '永利旅行社', '東南旅遊', '長汎假期',
  '雄獅旅遊', '燦星旅遊', '鳳凰旅行社', '理想旅遊', 'Ezfly易飛網',
]);
for (const name of TRAVEL_AGENCIES) OVERRIDES[name] = TRAVEL(['travel_agency']);

const TRANSPORT = new Set([
  '台灣大車隊', '台灣高鐵', '和運租車', '格上租車', 'Apple錢包指定交通卡 (ICOCA)',
  'Apple錢包指定交通卡 (PASMO)', 'Apple錢包指定交通卡 (SUICA)', 'Grab', 'Uber', 'iRent', 'yoxi',
]);
for (const name of TRANSPORT) OVERRIDES[name] = TRAVEL(['transport']);

// 國內日系特店加碼 — drugstores + bookstore + apparel, not one category
const JAPANESE_DRUGSTORES = new Set(['三友藥妝Tomod\'s', '日藥本舖', '松本清', '札幌藥妝']);
for (const name of JAPANESE_DRUGSTORES) OVERRIDES[name] = DRUGSTORE(['japanese_brand']);

OVERRIDES['TSUTAYA BOOKSTORE'] = { primary_category: 'retail', tags: ['bookstore', 'japanese_brand'] };
OVERRIDES['DAISO大創百貨'] = RETAIL(['variety_store', 'japanese_brand']);
OVERRIDES['Standard Products'] = RETAIL(['variety_store', 'japanese_brand']);
OVERRIDES['THREEPPY'] = RETAIL(['variety_store', 'japanese_brand']);

const JAPANESE_APPAREL = new Set([
  'UNIQLO', 'GU', '思夢樂', 'GLOBAL WORK', 'niko and …', 'LOWRYS FARM', 'LAKOLE',
  'studio CLIP', 'repipi armario', 'HARE', 'Heather', 'PAGEBOY', 'RAGEBLUE', 'LEPSIM', 'JEANASIS',
]);
for (const name of JAPANESE_APPAREL) OVERRIDES[name] = RETAIL(['apparel', 'japanese_brand']);

// 玩數位 — AI tools / streaming / ecommerce all live under one scheme
const AI_TOOLS = new Set(['ChatGPT', 'Canva', 'Claude', 'Cursor', 'Duolingo', 'Gamma', 'Gemini', 'Notion', 'Perplexity', 'Speak']);
for (const name of AI_TOOLS) OVERRIDES[name] = DIGITAL(['ai_tool', 'productivity']);

const STREAMING = new Set(['Apple 媒體服務', 'Google Play', 'Disney+', 'Netflix', 'Spotify', 'YouTube Premium', 'Max']);
for (const name of STREAMING) OVERRIDES[name] = DIGITAL(['streaming', 'subscription']);

const ECOMMERCE = new Set(['蝦皮購物', 'momo購物網', 'PChome 24h購物', '小樹購', 'Coupang 酷澎(台灣)', '淘寶/天貓']);
for (const name of ECOMMERCE) OVERRIDES[name] = DIGITAL(['ecommerce']);

// Scheme-level defaults for schemes that ARE genuinely homogeneous.
const SCHEME_DEFAULT = {
  '國內日系餐廳優惠': DINING(['japanese_food']),
};

function classify(name, schemes) {
  if (OVERRIDES[name]) return OVERRIDES[name];
  for (const scheme of schemes) {
    if (SCHEME_DEFAULT[scheme]) return SCHEME_DEFAULT[scheme];
  }
  // fallback for department-store-shaped 樂饗購 entries and anything else
  // not explicitly classified above (mostly the ~30 malls/outlets).
  if (schemes.has('樂饗購')) return DEPT_STORE();
  return { primary_category: 'uncategorized', tags: [], needsReview: true };
}

function slugId(name) {
  return (
    'm_' +
    name
      .toLowerCase()
      .replace(/[^a-z0-9一-鿿]+/g, '_')
      .replace(/^_+|_+$/g, '')
      .slice(0, 60)
  );
}

// ---- seed merchants NOT present in Allen's crawl ----
// These exist so the category-type rules (see SCHEMA.md) have something to
// actually match against — every merchant derived from Allen's crawl above
// already has its own exact merchant-type rule, so category matching can
// never fire for any of them (tier 1 always wins first). The whole point
// of category rules is catching merchants the bank never named, so this
// list needs entries the reward-rule files DON'T already cover.
//
// First pass, not verified against official sources beyond a web search
// for "is this chain real / still operating" — flagged for human review
// same as everything else in this script. Researched 2026-08-06.

function seed(name, category, tags, opts = {}) {
  return { name, primary_category: category, tags, needsReview: true, ...opts };
}

const SEED_MERCHANTS = [
  // Fast food
  seed('摩斯漢堡', 'dining', ['restaurant', 'fast_food']),
  seed('肯德基', 'dining', ['restaurant', 'fast_food']),
  seed('頂呱呱', 'dining', ['restaurant', 'fast_food']),
  seed('漢堡王', 'dining', ['restaurant', 'fast_food']),
  // Breakfast chains
  seed('美而美', 'dining', ['restaurant', 'breakfast']),
  seed('弘爺漢堡', 'dining', ['restaurant', 'breakfast']),
  seed('早安美芝城', 'dining', ['restaurant', 'breakfast']),
  seed('麥味登', 'dining', ['restaurant', 'breakfast']),
  // Coffee chains
  seed('星巴克', 'dining', ['restaurant', 'coffee']),
  seed('85度C', 'dining', ['restaurant', 'coffee', 'bakery']),
  seed('cama café', 'dining', ['restaurant', 'coffee']),
  seed('丹堤咖啡', 'dining', ['restaurant', 'coffee']),
  seed('怡客咖啡', 'dining', ['restaurant', 'coffee']),
  // Bubble tea / beverage chains
  seed('大苑子', 'dining', ['restaurant', 'beverage']),
  seed('迷客夏', 'dining', ['restaurant', 'beverage']),
  seed('萬波', 'dining', ['restaurant', 'beverage']),
  seed('老虎堂', 'dining', ['restaurant', 'beverage']),
  seed('清心福全', 'dining', ['restaurant', 'beverage']),
  seed('CoCo都可', 'dining', ['restaurant', 'beverage']),
  seed('一芳水果茶', 'dining', ['restaurant', 'beverage']),
  seed('珍煮丹', 'dining', ['restaurant', 'beverage']),
  seed('得正', 'dining', ['restaurant', 'beverage']),
  seed('天仁茗茶', 'dining', ['restaurant', 'beverage']),
  seed('春水堂', 'dining', ['restaurant', 'beverage']),
  // Hot pot chains
  seed('錢都涮涮鍋', 'dining', ['restaurant', 'hot_pot']),
  seed('石二鍋', 'dining', ['restaurant', 'hot_pot']),
  seed('築間幸福鍋物', 'dining', ['restaurant', 'hot_pot']),
  seed('鼎王麻辣鍋', 'dining', ['restaurant', 'hot_pot']),
  seed('馬辣頂級麻辣鴛鴦火鍋', 'dining', ['restaurant', 'hot_pot']),
  // Taiwanese / Chinese dining chains
  seed('鼎泰豐', 'dining', ['restaurant']),
  seed('三商巧福', 'dining', ['restaurant']),
  seed('度小月', 'dining', ['restaurant']),
  seed('貴族世家', 'dining', ['restaurant']),
  // Japanese dining chains (Taiwan branches)
  seed('壽司郎', 'dining', ['restaurant', 'japanese_food']),
  seed('食其家', 'dining', ['restaurant', 'japanese_food']),
  seed('吉野家', 'dining', ['restaurant', 'japanese_food']),
  seed('丸龜製麵', 'dining', ['restaurant', 'japanese_food']),
  seed('爭鮮', 'dining', ['restaurant', 'japanese_food', 'kaiten_sushi']),
  seed('品田牧場', 'dining', ['restaurant', 'japanese_food']),
  // 王品集團 brands (steakhouse / teppanyaki / yakiniku / Korean BBQ) —
  // user flagged that dining coverage felt thin, expanded 2026-08-06
  seed('王品台塑牛排', 'dining', ['restaurant', 'steakhouse']),
  seed('陶板屋', 'dining', ['restaurant', 'steakhouse', 'teppanyaki']),
  seed('西堤牛排', 'dining', ['restaurant', 'steakhouse']),
  seed('原燒', 'dining', ['restaurant', 'yakiniku']),
  seed('藝奇', 'dining', ['restaurant']),
  seed('舒果', 'dining', ['restaurant', 'vegetarian']),
  seed('就饗鐵板燒', 'dining', ['restaurant', 'teppanyaki']),
  seed('金咕韓式原塊烤肉', 'dining', ['restaurant', 'korean_bbq']),
  // 瓦城泰統集團 brands (Thai / Hunan)
  seed('瓦城', 'dining', ['restaurant', 'thai_food']),
  seed('非常泰', 'dining', ['restaurant', 'thai_food']),
  seed('大心', 'dining', ['restaurant', 'thai_food']),
  seed('1010湘', 'dining', ['restaurant']),
  seed('十食湘', 'dining', ['restaurant']),
  // Buffet
  seed('饗食天堂', 'dining', ['restaurant', 'buffet']),
  seed('漢來海港', 'dining', ['restaurant', 'buffet']),
  // Korean BBQ / hot pot
  seed('涓豆腐', 'dining', ['restaurant', 'korean_bbq', 'hot_pot']),
  seed('老四川', 'dining', ['restaurant', 'hot_pot']),
  seed('大戶屋', 'dining', ['restaurant', 'japanese_food']),
  // Pizza
  seed('達美樂', 'dining', ['restaurant', 'pizza', 'delivery']),
  seed('必勝客', 'dining', ['restaurant', 'pizza', 'delivery']),
  // Taiwanese local chains
  seed('鬍鬚張魯肉飯', 'dining', ['restaurant']),
  seed('欣葉台菜', 'dining', ['restaurant']),
  seed('悟饕池上便當', 'dining', ['restaurant', 'bento']),
  seed('我家牛排', 'dining', ['restaurant', 'steakhouse']),
  // Dim sum
  seed('添好運', 'dining', ['restaurant', 'dim_sum']),
  // Beverage
  seed('樺達奶茶', 'dining', ['restaurant', 'beverage']),
  // Convenience / supermarket not already in the Allen-derived list
  seed('OK超商', 'convenience_store', ['chain_store']),
  seed('美廉社', 'convenience_store', ['chain_store']),
  // Drugstore chains
  seed('寶雅', 'drugstore', ['health_beauty']),
  seed('小三美日', 'drugstore', ['health_beauty']),
  // Bakery
  seed('元祖', 'retail', ['bakery']),
  seed('亞尼克', 'retail', ['bakery']),
  // Hotel chains/brands (not the individually-named jiho/cube hotels
  // already present)
  seed('晶英酒店', 'hotel', ['lodging']),
  seed('老爺酒店', 'hotel', ['lodging']),
  seed('君品酒店', 'hotel', ['lodging']),
  seed('雲品溫泉酒店', 'hotel', ['lodging']),
  seed('翰品酒店', 'hotel', ['lodging']),
  seed('兆品酒店', 'hotel', ['lodging']),
  seed('福容大飯店', 'hotel', ['lodging']),
  seed('六福萬怡酒店', 'hotel', ['lodging']),
];

// Merged back from the original hand-made merchants_mock.json (predates
// Allen's crawl) — 藏壽司/路易莎咖啡 were the original worked examples for
// "a merchant the bank never named, that a category rule should still
// catch." Kept here instead of a separate file so there's one generator.
const LEGACY_DEMO_MERCHANTS = [
  { name: '藏壽司', primary_category: 'dining', tags: ['restaurant', 'chain_store', 'japanese_food'] },
  { name: '路易莎咖啡', primary_category: 'dining', tags: ['restaurant', 'coffee', 'chain_store'] },
  { name: '小北百貨', primary_category: 'retail', tags: ['general_retail'] },
];

// ---- run ----

const universe = collectMerchantUniverse();
const merchants = [];
const reviewNotes = [];
const seenNormalizedNames = new Set();

const normalizeForDedup = (s) => s.trim().toLowerCase().replace(/\s+/g, '');

for (const [name, schemes] of [...universe.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
  const { primary_category, tags, needsReview } = classify(name, schemes);
  const entry = {
    merchant_id: slugId(name),
    canonical_name: name,
    display_name: name,
    primary_category,
    subcategory: null,
    tags,
    aliases: ALIASES[name] || [],
    channel: 'offline',
    country: [...schemes].some((s) => s.includes('日本')) ? 'JP' : 'TW',
    active: true,
  };
  merchants.push(entry);
  seenNormalizedNames.add(normalizeForDedup(name));
  if (needsReview || primary_category === 'uncategorized') {
    reviewNotes.push(`- ${name} (${[...schemes].join('/')}) -> ${primary_category} / [${tags.join(', ')}]`);
  }
}

for (const { name, primary_category, tags, needsReview } of [...SEED_MERCHANTS, ...LEGACY_DEMO_MERCHANTS]) {
  const normalized = normalizeForDedup(name);
  if (seenNormalizedNames.has(normalized)) {
    console.warn(`[merchants] skipping seed "${name}" — already present from Allen's crawl`);
    continue;
  }
  seenNormalizedNames.add(normalized);
  merchants.push({
    merchant_id: slugId(name),
    canonical_name: name,
    display_name: name,
    primary_category,
    subcategory: null,
    tags,
    aliases: ALIASES[name] || [],
    channel: 'offline',
    country: 'TW',
    active: true,
  });
  if (needsReview) {
    reviewNotes.push(`- ${name} (seed, not from Allen's crawl) -> ${primary_category} / [${tags.join(', ')}]`);
  }
}

fs.writeFileSync(
  path.join(DATA_DIR, 'merchants.json'),
  JSON.stringify(merchants, null, 2) + '\n',
  'utf8'
);

console.log(`merchants.json: ${merchants.length} entries`);
console.log(`\n${reviewNotes.length} entries flagged for human review:\n`);
console.log(reviewNotes.join('\n'));
