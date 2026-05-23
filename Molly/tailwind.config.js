/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        display: ['"Comfortaa"', '"Nunito"', '"SF Pro Rounded"', 'system-ui', 'sans-serif'],
        body: ['"Nunito"', '"SF Pro Rounded"', 'system-ui', 'sans-serif'],
      },
      colors: {
        // Persona theme tokens are CSS custom properties bound at runtime.
        persona: {
          primary: 'rgb(var(--persona-primary) / <alpha-value>)',
          secondary: 'rgb(var(--persona-secondary) / <alpha-value>)',
          tint: 'rgb(var(--persona-tint) / <alpha-value>)',
          text: 'rgb(var(--persona-text) / <alpha-value>)',
          accent: 'rgb(var(--persona-accent) / <alpha-value>)',
        },
      },
      boxShadow: {
        cute: '0 8px 24px -8px rgb(var(--persona-primary) / 0.35), 0 2px 6px rgb(var(--persona-primary) / 0.15)',
      },
      borderRadius: {
        '4xl': '2rem',
      },
    },
  },
  plugins: [],
};
