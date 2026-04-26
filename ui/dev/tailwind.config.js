import plugin from "tailwindcss/plugin";

/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        dark: "#121212",
        "4B": "#4B4B4B",
        "0B": "#0B0B0B",
        43: "#434343",
        FFA944: "#FFA944",
        FF4747: "#FF4747",
      },
      fontFamily: {},
      fontSize: { 9: "9px", 11: "11px", 13: "13px" },
      screens: {
        "2k": "2560px",
        "4k": "3840px",
        "3xl": "1680px",
      },
      backgroundImage: {},
    },
  },
  plugins: [
    plugin(function ({ addUtilities }) {
      const newUtilities = {
        ".scrollbar-hide::-webkit-scrollbar": { display: "none" },
        ".scrollbar-hide": {
          "scrollbar-width": "none",
          "-ms-overflow-style": "none",
        },
      };
      addUtilities(newUtilities);
    }),
  ],
};
