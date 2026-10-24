// Local convenience for the two demo accounts. Never connects to Supabase.
import { accounts, totp } from './test-account-tools.mjs';
for (const account of accounts()) {
  if (!account.totp_secret) throw new Error('La cuenta todavía no tiene el autenticador configurado.');
  console.log(`${account.name} (${account.email}): ${totp(account.totp_secret)}`);
}
console.log(`Códigos válidos durante aproximadamente ${30 - Math.floor(Date.now()/1000)%30} segundos. No son contraseñas.`);
