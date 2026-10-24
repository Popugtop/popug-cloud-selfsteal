import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://status.popug.cloud',
  output: 'static',
  compressHTML: false,
  build: { assets: 'assets', inlineStylesheets: 'never' },
});
