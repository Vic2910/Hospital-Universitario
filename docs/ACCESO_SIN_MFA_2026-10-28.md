# Acceso con contrasena para la app movil

## Decision actual

El usuario solicito expresamente retirar MFA el 28 de octubre de 2026. Esta decision sustituye las instrucciones historicas que lo exigian para Medico y Paciente. No se inscribieron ni eliminaron factores, ni se modificaron contrasenas.

## Implementacion

- iOS y web entran con correo y contrasena, sin consultar factores ni presentar TOTP. Se eliminaron las vistas, estado y metodos de verificacion sin uso.
- [mobile-password-access.sql](sql/mobile-password-access.sql) actualiza el auxiliar existente `private.session_active(boolean)`. Aplicarlo despues del esquema original y de los modulos. Conserva firma, propietario, ACL y comprobaciones de identidad, perfil activo y sesion no revocada/no expirada.
- La excepcion al requisito AAL2 solo cubre cuentas cuyos roles vigentes son doctor y/o patient. Cuentas con otros roles, incluidas combinaciones con administracion, conservan la condicion anterior. No se modifican los flujos administrativos.
- Las RLS, permisos por sede, autoria, propiedad, vinculos asistenciales y versiones de registros siguen vigentes. No se concede acceso anonimo ni BYPASSRLS.
- El login con contrasena pierde la proteccion adicional del segundo factor. No usar contrasenas compartidas ni reutilizadas.

## Verificaciones de esta intervencion

La actualizacion se aplico en Supabase. [test-mobile-flows.sql](sql/test-mobile-flows.sql) paso con claims AAL1 y sesiones temporales: consultas, expediente, orden, receta, solicitud, cancelacion y cierre; se mantuvieron las denegaciones por rol incorrecto, paciente sin vinculo, version obsoleta, consulta cerrada y sesion expirada. Toda la prueba termino en ROLLBACK y no genero datos clinicos permanentes. No equivale a login HTTPS real.

Las verificaciones locales y pendientes finales constan en la bitacora. Windows no compila Swift con el SDK de Apple. Los catalogos institucionales vacios y los demas pendientes anteriores no se resuelven retirando MFA.
