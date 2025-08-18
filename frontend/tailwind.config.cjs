module.exports = {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx,html}",
  ],
  darkMode: 'class', // use the `.dark` class on <html> to enable dark mode
  theme: {
    extend: {
      colors: {
        // application palette helpers
        accent: {
          DEFAULT: '#2563eb', // blue-600
          light: '#60a5fa',
          dark: '#1e40af'
        },
        muted: {
          DEFAULT: '#6b7280', // gray-500
          light: '#9ca3af',
          dark: '#374151'
        },
        step: {
          green: '#16a34a', // success
          yellow: '#d97706', // action / smoked
          indigo: '#4f46e5'  // primary action
        }
      }
    },
  },
  plugins: [],
}