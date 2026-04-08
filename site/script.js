const domains = {
  'lapinel-home.arpa': 'lapinel-home.arpa',
  'lapinel-fam.club': 'lapinel-fam.club',
};

const hostname = window.location.hostname;
const isRemote = hostname.endsWith('lapinel-fam.club');
const baseDomain = isRemote ? 'lapinel-fam.club' : 'lapinel-home.arpa';

document.querySelectorAll('a[data-subdomain]').forEach(a => {
  a.href = `https://${a.dataset.subdomain}.${baseDomain}`;
});

if (isRemote) {
  document.querySelectorAll('[data-local-only]').forEach(el => {
    el.style.display = 'none';
  });
}
