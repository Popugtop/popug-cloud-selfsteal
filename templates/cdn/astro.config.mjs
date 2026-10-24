import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://cdn.popug.cloud',
  output: 'static',
  compressHTML: false,
  build: { assets: 'assets', inlineStylesheets: 'never' },
});
