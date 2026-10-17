/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Geist Variable", "Geist", "system-ui", "-apple-system", "sans-serif"],
        mono: ["Geist Mono Variable", "Geist Mono", "ui-monospace", "SFMono-Regular", "monospace"],
      },
      colors: {
        void: "#111925",
        panel: "rgba(25,38,54,0.72)",
      },
      boxShadow: {
        glow: "0 8px 48px -16px rgba(72,126,214,0.32), 0 2px 20px rgba(6,12,22,0.46)",
        card: "0 22px 70px -20px rgba(6,12,22,0.72)",
      },
    },
  },
  plugins: [],
};
