/** Shared links so every template points at the same places. */
export const links = {
  home: 'https://popug.cloud',
  docs: 'https://docs.popug.cloud',
  status: 'https://status.popug.cloud',
  console: 'https://console.popug.cloud',
  api: 'https://api.popug.cloud',
  cdn: 'https://cdn.popug.cloud',
  s3: 'https://s3.popug.cloud',
};
export const nav = [
  { label: 'Products', href: `${links.home}/#products` },
  { label: 'Pricing', href: `${links.home}/#pricing` },
  { label: 'Docs', href: links.docs },
  { label: 'Status', href: links.status },
];
