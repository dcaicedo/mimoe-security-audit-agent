const TerserPlugin = require('terser-webpack-plugin');
const ESLintPlugin = require('eslint-webpack-plugin');
const path = require('path');

const BUILD_DIR = path.resolve(__dirname, 'build');
const SRC_DIR = path.resolve(__dirname, 'src');

// Check for debug mode - can be set via environment variable
const DEBUG = process.env.DEBUG === 'true' || process.env.NODE_ENV === 'development';

// Debug optimization configuration (more readable, easier debugging)
const debugOptimization = {
  minimize: true,
  minimizer: [
    new TerserPlugin({
      terserOptions: {
        // Keep more readable formatting
        format: {
          beautify: true,        // Format code nicely
          indent_level: 2,       // Use 2-space indentation
          wrap_iife: true,       // Wrap IIFEs properly
          comments: false,       // Remove comments
        },
        compress: {
          // Reduce aggressive compression that makes debugging hard
          sequences: false,      // Don't join consecutive statements with commas
          join_vars: false,      // Don't join variable declarations
          collapse_vars: false,  // Don't collapse single-use variables
          reduce_vars: false,    // Don't reduce variables
          hoist_funs: false,     // Don't hoist functions
          drop_console: false,   // Keep console statements for debugging
          drop_debugger: false,  // Keep debugger statements
        },
        mangle: {
          // Disable name mangling for easier debugging
          keep_fnames: true,     // Keep function names
          keep_classnames: true, // Keep class names
        },
        keep_fnames: true,       // Global option to keep function names
      },
      extractComments: false,
    }),
  ],
  // Disable module concatenation to keep modules separate
  concatenateModules: false,
};

// Production optimization configuration (fully minified)
const productionOptimization = {
  minimize: true,
  minimizer: [
    new TerserPlugin({
      terserOptions: {
        output: {
          comments: false,
        },
      },
    }),
  ],
  concatenateModules: true,
};

module.exports = {
  mode: DEBUG ? 'development' : 'production',
  target: ['web', 'es5'],
  entry: [
    `${SRC_DIR}/polyfills.js`,
    `${SRC_DIR}/index.js`,
  ],
  output: {
    path: BUILD_DIR,
    filename: 'index.js',
  },
  // Use debug optimization if DEBUG is true, otherwise use production optimization
  optimization: DEBUG ? debugOptimization : productionOptimization,
  plugins: [
    new ESLintPlugin({
      context: SRC_DIR,
      extensions: ['js'],
      fix: true, // Enable auto-fix
      emitWarning: true, // Emit warnings instead of errors
      failOnError: false, // Don't fail build on ESLint errors
      exclude: 'node_modules',
    }),
  ],
  module: {
    rules: [
      {
        test: /\.(?:js|mjs|cjs)$/,
        exclude: [
          /node_modules[\\/]webpack[\\/]buildin/,
          /node_modules[\\/]@babel[\\/]runtime/,
        ],
        use: {
          loader: 'babel-loader',
          options: {
            presets: [
              ['@babel/preset-env', {
                useBuiltIns: false,
                modules: 'commonjs',
                targets: {
                  browsers: ['ie 11'],
                },
              }]
            ],
            sourceType: 'unambiguous', // important
          },
        },
      },
    ],
  },
  resolve: {
    symlinks: false,
    extensions: ['*', '.js'],
    fallback: {
      url: require.resolve('url/'),
    },
  },
  // Add source maps in debug mode for easier debugging
  devtool: DEBUG ? 'source-map' : false,
};
