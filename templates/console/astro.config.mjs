import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://console.popug.cloud',
  output: 'static',
  compressHTML: false,
  build: { assets: 'assets', inlineStylesheets: 'never' },
});
