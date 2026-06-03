module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  parserOptions: { ecmaVersion: 'latest', sourceType: 'module', ecmaFeatures: { jsx: true } },
  plugins: ['@typescript-eslint', 'react', 'react-hooks'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:react/recommended',
    'plugin:react-hooks/recommended'
  ],
  settings: { react: { version: 'detect' } },
  ignorePatterns: ['out/**', 'dist/**', 'node_modules/**', 'out-types/**'],
  rules: {
    'react/react-in-jsx-scope': 'off',
    // This is a TypeScript codebase — prop types are enforced statically.
    'react/prop-types': 'off'
  }
};
