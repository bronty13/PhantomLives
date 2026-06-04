/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        // Paper Daisy is the soft rounded wordmark/display font; body text
        // stays in Nunito for readability at small sizes.
        display: ['"Paper Daisy"', '"Comfortaa"', 'system-ui', 'sans-serif'],
        body: ['"Nunito"', '"SF Pro Rounded"', 'system-ui', 'sans-serif'],
      },
      colors: {
        // PurpleMind's soft purple palette. Surface tokens flip in dark
        // mode (see styles/index.css); the `purple` ramp is the brand
        // accent used on nodes, buttons, and the active sidebar row.
        surface: {
          base: 'rgb(var(--surface-base) / <alpha-value>)',
          card: 'rgb(var(--surface-card) / <alpha-value>)',
          input: 'rgb(var(--surface-input) / <alpha-value>)',
          border: 'rgb(var(--surface-border) / <alpha-value>)',
          text: 'rgb(var(--surface-text) / <alpha-value>)',
          muted: 'rgb(var(--surface-muted) / <alpha-value>)',
        },
        brand: {
          50: 'rgb(var(--brand-50) / <alpha-value>)',
          100: 'rgb(var(--brand-100) / <alpha-value>)',
          200: 'rgb(var(--brand-200) / <alpha-value>)',
          300: 'rgb(var(--brand-300) / <alpha-value>)',
          400: 'rgb(var(--brand-400) / <alpha-value>)',
          500: 'rgb(var(--brand-500) / <alpha-value>)',
          600: 'rgb(var(--brand-600) / <alpha-value>)',
          700: 'rgb(var(--brand-700) / <alpha-value>)',
        },
      },
      borderRadius: {
        '4xl': '2rem',
      },
      boxShadow: {
        cute: '0 8px 24px -8px rgb(var(--brand-500) / 0.35)',
      },
    },
  },
  plugins: [],
};
