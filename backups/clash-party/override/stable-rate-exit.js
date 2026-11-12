// Run after AI-Rule. One url-test for rate <= 1; fallback climbs higher rates
// only after that pool is dead. REJECT must not be a member: fallback keeps
// proxies[0] selected, so REJECT first blocks all traffic when the config
// reloads. empty-fallback already covers the all-dead case.
function main(config) {
  // The plain subscription host 103.182.97.141 is unreachable from CN; the official
  // client's UA receives yzapp.myzxdy.top (Shenzhen Telecom relay), same credentials.
  const SERVER_REWRITE = { 'yz.myzxdy.top': 'yzapp.myzxdy.top' };
  const eligible = [];
  const seen = new Set();
  for (const proxy of config.proxies || []) {
    if (SERVER_REWRITE[proxy.server]) proxy.server = SERVER_REWRITE[proxy.server];
    const name = proxy.name || '';
    if (!name || seen.has(name) || /剩余流量|距离下次重置|套餐到期|DirectNIC/.test(name)) continue;
    if (['direct', 'reject', 'reject-drop', 'pass'].includes((proxy.type || '').toLowerCase())) continue;
    seen.add(name);
    eligible.push(proxy);
  }
  let nodes = eligible.map(proxy => {
    const match = proxy.name.match(/(\d+(?:\.\d+)?)\s*(?:x\b|倍率)/i);
    // Only iNetS's existing unlabelled-node convention implies 1x.
    const rate = match ? Number(match[1]) : /\.inetsnode\.de$/i.test(proxy.server || '') ? 1 : NaN;
    return { name: proxy.name, rate, inets: /\.inetsnode\.de$/i.test(proxy.server || '') };
  });
  // Subscriptions without any rate label (BoostNet) are still usable: treat all as 1x.
  if (!nodes.some(node => Number.isFinite(node.rate))) {
    nodes.forEach(node => { node.rate = 1; });
  }
  nodes = nodes.filter(node => Number.isFinite(node.rate) && node.rate > 0);
  // Prefer iNetS within the low-rate pool; retain each subscription's stable order.
  const low = nodes.filter(node => node.rate <= 1).sort((a, b) => Number(b.inets) - Number(a.inets));
  const high = nodes.filter(node => node.rate > 1).sort((a, b) => a.rate - b.rate);
  const probe = {
    url: 'https://api2.cursor.sh/',
    interval: 300,
    timeout: 5000,
    'max-failed-times': 2,
    lazy: false,
    'expected-status': 200,
    'empty-fallback': 'REJECT'
  };
  const groups = [];
  const ladder = [];
  if (low.length) {
    groups.push({
      name: '低倍率',
      type: 'url-test',
      proxies: low.map(node => node.name),
      tolerance: 150,
      ...probe
    });
    ladder.push('低倍率');
  }
  ladder.push(...high.map(node => node.name));
  groups.push({
    name: '倍率优先',
    type: 'fallback',
    proxies: ladder,
    ...probe
  });
  config['proxy-groups'] = [...groups, ...(config['proxy-groups'] || []).filter(
    item => !['低倍率', '高倍率', '倍率优先'].includes(item.name)
  )];
  return config;
}
