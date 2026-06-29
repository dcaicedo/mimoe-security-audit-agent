const js = require('@eslint/js');
const globals = require('globals');

module.exports = [
  js.configs.recommended,
  {
    files: ['**/*.js'],
    languageOptions: {
      parser: require('@babel/eslint-parser'),
      parserOptions: {
        requireConfigFile: false,
        babelOptions: {
          presets: ['@babel/preset-env']
        }
      },
      globals: {
        ...globals.node,
        mimikModule: true,
        Duktape: true,
        TextDecoder: true,
        TextEncoder: true,
        globalThis: true
      }
    },
    rules: {
      // Spacing and formatting rules
      'arrow-spacing': ['error', { before: true, after: true }],
      'block-spacing': ['error', 'always'],
      'comma-spacing': ['error', { before: false, after: true }],
      'semi-spacing': ['error', { before: false, after: true }],
      'no-multi-spaces': ['error', {
        exceptions: {
          Property: false,
          BinaryExpression: false,
          VariableDeclarator: false
        }
      }],
      'func-call-spacing': ['error', 'never'],
      'indent': ['error', 2, { SwitchCase: 1 }],
      'key-spacing': ['error', { beforeColon: false, afterColon: true }],
      'keyword-spacing': ['error', { before: true, after: true }],
      'object-curly-spacing': ['error', 'always'],
      'space-before-blocks': ['error', 'always'],
      'space-before-function-paren': ['error', {
        anonymous: 'always',    // async () => {}
        named: 'never',         // function name() {}
        asyncArrow: 'always'    // async () => {}
      }],
      'space-in-parens': ['error', 'never'],
      'space-infix-ops': 'error',
      'array-bracket-spacing': ['error', 'never'],
      'brace-style': ['error', '1tbs'],
      'no-trailing-spaces': 'error',
      'eol-last': ['error', 'always'],

      // Code style rules
      'consistent-return': 'error',
      'curly': ['error', 'multi-line'],
      'eqeqeq': ['error', 'always'],
      'prefer-const': 'error',
      'quotes': ['error', 'single', { allowTemplateLiterals: true }],
      'semi': ['error', 'always'],
      'comma-dangle': ['error', {
        arrays: 'always-multiline',
        objects: 'always-multiline',
        imports: 'always-multiline',
        exports: 'always-multiline',
        functions: 'always-multiline'
      }],
      'spaced-comment': ['error', 'always', { markers: ['/'] }],

      // Project-specific overrides
      'max-len': ['error', { code: 180 }],
      'linebreak-style': 'off',
      'no-warning-comments': 'off',
      'no-console': 'off',
      'no-underscore-dangle': 'off',

      // Rules you had disabled in your original config
      'no-await-in-loop': 'off',
      'no-plusplus': 'off',
      'no-continue': 'off',
      'no-restricted-syntax': 'off',

      // Variable handling
      'no-unused-vars': [
        'warn',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_'
        }
      ],
      'no-use-before-define': ['error', { functions: false, classes: true }]
    }
  }
];
