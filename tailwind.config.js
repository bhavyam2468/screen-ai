/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        serif: ["Libron", "Newsreader", "Charter", "Georgia", "serif"],
        sans: ["Inter", "system-ui", "-apple-system", "sans-serif"],
        mono: ["JetBrainsMono Nerd Font", "JetBrains Mono", "ui-monospace", "SFMono-Regular", "monospace"],
      },
      colors: {
        void: "#08080d",
        panel: "rgba(255,255,255,0.06)",
      },
      boxShadow: {
        glow: "0 8px 60px -8px rgba(139,92,246,0.45), 0 2px 24px rgba(0,0,0,0.6)",
        card: "0 20px 80px -12px rgba(0,0,0,0.75)",
      },
    },
  },
  plugins: [],
};
