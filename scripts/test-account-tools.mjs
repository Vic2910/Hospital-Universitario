import { createHmac } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
export const local = new URL('../.local/', import.meta.url);
export function accounts() { return JSON.parse(readFileSync(new URL('test-accounts.json',local),'utf8')); }
export function totp(secret, now = Date.now(), digits = 6) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let bits = 0, value = 0; const bytes = [];
  for (const char of secret.toUpperCase().replace(/[\s=]/g,'')) {
    const index = alphabet.indexOf(char); if (index < 0) throw new Error('Secreto TOTP inválido');
    value = (value << 5) | index; bits += 5;
    if (bits >= 8) { bytes.push((value >>> (bits - 8)) & 255); bits -= 8; }
  }
  const counter = Buffer.alloc(8); counter.writeBigUInt64BE(BigInt(Math.floor(now / 30000)));
  const hash = createHmac('sha1',Buffer.from(bytes)).update(counter).digest();
  return String((hash.readUInt32BE(hash[19] & 15) & 0x7fffffff) % 10 ** digits).padStart(digits,'0');
}
export function saveAccounts(data) {
  writeFileSync(new URL('test-accounts.json',local),JSON.stringify(data,null,2));
  writeFileSync(new URL('CREDENCIALES_PRUEBA.md',local),
    '# Cuentas de prueba · Hospital Universitario\n\nSolo demostración. No usar con pacientes reales. Archivo excluido de Git y no servido por la vista previa.\n\n' +
    data.map(a => `## ${a.name}\n\n- Correo: ${a.email}\n- Contraseña: ${a.password}\n- Rol: ${a.role}\n- Secreto del autenticador TOTP: ${a.totp_secret || 'No configurado'}\n`).join('\n') +
    '\n## Iniciar sesión\n\n1. Abre la app o http://127.0.0.1:4173/ y usa el login real.\n2. Introduce el correo y la contraseña de una cuenta.\n3. Si la cuenta tiene autenticador configurado, introduce su código cuando se solicite.\n\nActualmente el resumen clínico puede requerir MFA; no se reducen las políticas del servidor para mostrarlo.\n\nSolo si se autoriza y completa la inscripción TOTP, los códigos se consultan con:\n\n```powershell\nnode --preserve-symlinks --preserve-symlinks-main scripts/test-account-codes.mjs\n```\n\nPara un autenticador inscrito: TOTP, SHA-1, 6 dígitos y período de 30 segundos. Si un código ya se usó en una prueba, espera al siguiente período antes de reutilizarlo. No envíes correo a estas direcciones: el dominio .test es de demostración.\n');
}
