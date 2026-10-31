import http from 'node:http';
import { readFile } from 'node:fs/promises';

const shared = new URL('../HospitalUniversitario/HospitalUniversitario/Shared/', import.meta.url);
const files = new Map([
  ['/', [new URL('./index.html', import.meta.url), 'text/html; charset=utf-8']],
  ['/doctor-dashboard.js', [new URL('./doctor-dashboard.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/clinical-labs.js', [new URL('./clinical-labs.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/patient-history.js', [new URL('./patient-history.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/patient-prescriptions.js', [new URL('./patient-prescriptions.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/patient-appointments.js', [new URL('./patient-appointments.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/app.js', [new URL('./app.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/api.js', [new URL('./api.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/modules.js', [new URL('./modules.js', import.meta.url), 'text/javascript; charset=utf-8']],
  ['/style.css', [new URL('./style.css', import.meta.url), 'text/css; charset=utf-8']],
  ['/design-fixtures.json', [new URL('./design-fixtures.json', import.meta.url), 'application/json; charset=utf-8']],
  ['/shared/hospital-core.js', [new URL('hospital-core.js', shared), 'text/javascript; charset=utf-8']],
  ['/shared/contract.json', [new URL('contract.json', shared), 'application/json; charset=utf-8']],
  ['/shared/screens.json', [new URL('screens.json', shared), 'application/json; charset=utf-8']]
]);
const port = Number(process.env.PORT || 4173);
const server = http.createServer(async (req, res) => {
  if (new URL(req.url, 'http://localhost').pathname === '/document-access') {
    const allowed = [`http://127.0.0.1:${port}`, `http://localhost:${port}`];
    res.setHeader('Cache-Control','no-store');
    res.setHeader('Content-Type','application/json');
    if (req.method !== 'POST' || !allowed.includes(req.headers.origin) || !/^Bearer [A-Za-z0-9._-]+$/.test(req.headers.authorization || '')) {
      res.writeHead(403); res.end(JSON.stringify({error:'Acceso no autorizado'})); return;
    }
    try {
      let body = '';
      for await (const chunk of req) {
        body += chunk.toString('utf8');
        if (Buffer.byteLength(body)>2048) { res.writeHead(413); res.end('{}'); return; }
      }
      const input = JSON.parse(body);
      if (Object.keys(input).length !== 1 || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(input.document_id)) {
        res.writeHead(400); res.end('{}'); return;
      }
      const contract = JSON.parse(await readFile(new URL('contract.json',shared),'utf8'));
      const result = await fetch(contract.url + '/functions/v1/document-access',{method:'POST',
        headers:{Authorization:req.headers.authorization,apikey:contract.publishableKey,'Content-Type':'application/json'},
        body:JSON.stringify(input),signal:AbortSignal.timeout(25000)});
      res.writeHead(result.status); res.end(await result.text());
    } catch { res.writeHead(502); res.end(JSON.stringify({error:'No se pudo autorizar el documento'})); }
    return;
  }
  const entry = files.get(new URL(req.url, 'http://localhost').pathname);
  if (!entry || !['GET', 'HEAD'].includes(req.method)) { res.writeHead(404); res.end('Not found'); return; }
  try {
    const body = await readFile(entry[0]);
    res.writeHead(200, {
      'Content-Type': entry[1], 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
      'Content-Security-Policy': "default-src 'self'; connect-src 'self' https://kgulityewtcyvjnxeskd.supabase.co; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
    });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch { res.writeHead(500); res.end('No se pudo leer el recurso'); }
});
server.listen(port, '127.0.0.1', () => console.log(`Vista previa local: http://127.0.0.1:${port}`));
