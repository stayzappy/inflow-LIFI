const path = require('path');
const webpack = require('webpack'); // 🔥 ADD THIS IMPORT

module.exports = {
  entry: './src/bridge.ts',
  mode: 'production',
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
    ],
  },
  resolve: {
    extensions: ['.tsx', '.ts', '.js'],
    fallback: {
        // 🔥 This tells Webpack to ignore missing Node modules if they aren't needed
        "crypto": false,
        "stream": false,
        "http": false,
        "https": false,
        "zlib": false,
        "assert": false,
        "url": false,
        "os": false,
        "buffer": require.resolve("buffer/") // 🔥 This points to the polyfill we just installed
    }
  },
  output: {
    filename: 'zapbridge.js',
    path: path.resolve(__dirname, '../web'), // Drops the compiled JS directly into the Flutter web folder
  },
  plugins: [
    // 🔥 THIS IS THE CRITICAL FIX: It injects Buffer into the browser window globally
    new webpack.ProvidePlugin({
      Buffer: ['buffer', 'Buffer'],
    }),
  ],
};