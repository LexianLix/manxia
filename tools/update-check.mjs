const api = 'https://api.github.com/repos/LexianLix/manxia/releases/latest';
const latest = 'https://github.com/LexianLix/manxia/releases/latest';
const validTag = /^v?\d+\.\d+\.\d+$/;

export function publicRelease(location) {
  const url = new URL(location, latest);
  const parts = url.pathname.split('/');
  if (url.origin !== 'https://github.com' || url.username || url.password ||
      parts.slice(0,5).join('/') !== '/LexianLix/manxia/releases/tag' ||
      parts.length !== 6 || !validTag.test(parts[5])) throw new Error('Invalid release redirect');
  return {tag_name:parts[5], body:'', assets:[], source:'public-page'};
}

// A fixed repository endpoint; this is deliberately not a general URL proxy.
export async function latestRelease(request = fetch) {
  const deadline = AbortSignal.timeout(25000);
  try {
    const response = await request(api, {headers:{Accept:'application/vnd.github+json','User-Agent':'Manxia'},
      redirect:'error', signal:AbortSignal.any([deadline,AbortSignal.timeout(6000)])});
    if (response.ok) {
      const data = await response.json();
      if (!validTag.test(data.tag_name) || data.draft || data.prerelease) throw new Error('Invalid release');
      return data;
    }
    await response.body?.cancel();
  } catch { /* Anonymous API limits must not disable the check. */ }
  const response = await request(latest,{method:'HEAD',redirect:'manual',signal:deadline,headers:{'User-Agent':'Manxia'}});
  try {
    if ([301,302,303,307,308].includes(response.status)) return publicRelease(response.headers.get('location') ?? '');
    throw new Error('Release unavailable');
  } finally { await response.body?.cancel(); }
}
