import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://popug.cloud',
  output: 'static',
  compressHTML: true,
  build: { assets: 'assets', inlineStylesheets: 'never' },
});
