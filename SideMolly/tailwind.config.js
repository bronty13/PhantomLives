/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        // Paper Daisy is the wordmark font (and the burned-in video text);
        // body text stays in Nunito for readability at small sizes.
        display: ['"Paper Daisy"', '"Comfortaa"', 'system-ui', 'sans-serif'],
        body: ['"Nunito"', '"SF Pro Rounded"', 'system-ui', 'sans-serif'],
      },
      colors: {
        // SideMolly's quiet workbench palette. Persona chips on bundle rows
        // pick up persona-color CSS variables when active; surface stays
        // neutral so multi-persona work doesn't visually thrash.
        surface: {
          base: 'rgb(var(--surface-base) / <alpha-value>)',
          card: 'rgb(var(--surface-card) / <alpha-value>)',
          input: 'rgb(var(--surface-input) / <alpha-value>)',
          border: 'rgb(var(--surface-border) / <alpha-value>)',
          text: 'rgb(var(--surface-text) / <alpha-value>)',
          muted: 'rgb(var(--surface-muted) / <alpha-value>)',
          accent: 'rgb(var(--surface-accent) / <alpha-value>)',
        },
        persona: {
          coc: 'rgb(var(--persona-coc) / <alpha-value>)',
          poa: 'rgb(var(--persona-poa) / <alpha-value>)',
          sa: 'rgb(var(--persona-sa) / <alpha-value>)',
        },
      },
      borderRadius: {
        '4xl': '2rem',
      },
    },
  },
  plugins: [],
};
