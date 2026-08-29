import type { GoldieConfig } from "./src/config.ts";

const APP_ROOT = "/Users/yegl/Downloads/GorillaTranslation";

const config: GoldieConfig = {
  appRoot: APP_ROOT,
  appPath: `${APP_ROOT}/build/Build/Products/Release-iphonesimulator/GorillaTranslate.app`,
  bundleId: "com.gorilla.translation",

  devices: ["iphone-6.9"],
  locales: ["zh-TW", "en-US"],
  appearance: "light",

  frame: { variant: "17-pro-blue" },

  theme: {
    background: "linear-gradient(160deg, #1a1a2e 0%, #16213e 55%, #0f3460 100%)",
    headlineColor: "#FFFFFF",
    subheadColor: "#B0B0B0",
    fontFamily: '-apple-system, "SF Pro Display", system-ui, sans-serif',
    copyHeightRatio: 0.24,
    deviceWidthRatio: 0.84,
    layout: "classic",
  },

  store: {
    name: "GorillaTranslate",
    subtitle: { "zh-TW": "智能泊車與翻譯助手", "en-US": "Smart Parking & Translation" },
    developer: "YeGL18",
    category: "Navigation",
    rating: 4.8,
    ratingCount: "100+ Ratings",
    ageRating: "4+",
    price: "Free",
    description: {
      "zh-TW": "智能泊車記憶、即時翻譯、樓層探測，讓你的出行更輕鬆。",
      "en-US": "Smart parking memory, real-time translation, and floor detection for easier travel."
    },
  },

  scenes: [
    {
      kind: "screenshot",
      id: "speed",
      flow: "store-01-speed",
      headline: { "zh-TW": "即時速度監測", "en-US": "Real-time Speed Monitor" },
      subhead: { "zh-TW": "精確顯示行車速度", "en-US": "Accurate driving speed display" },
    },
    {
      kind: "screenshot",
      id: "home",
      flow: "store-02-home",
      headline: { "zh-TW": "智能地圖追蹤", "en-US": "Smart Map Tracking" },
      subhead: { "zh-TW": "即時定位與導航", "en-US": "Real-time location & navigation" },
    },
    {
      kind: "screenshot",
      id: "parking",
      flow: "store-03-parking",
      headline: { "zh-TW": "泊車記憶", "en-US": "Parking Memory" },
      subhead: { "zh-TW": "自動記錄停車位置", "en-US": "Auto-record parking location" },
    },
    {
      kind: "screenshot",
      id: "settings",
      flow: "store-04-settings",
      headline: { "zh-TW": "個性化設定", "en-US": "Personalized Settings" },
      subhead: { "zh-TW": "自訂你的使用體驗", "en-US": "Customize your experience" },
    },
  ],
};

export default config;
