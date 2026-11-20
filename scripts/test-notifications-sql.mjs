// Prueba de los SQL preparados en un PostgreSQL 17 LOCAL y desechable (Docker). Nunca se conecta a Supabase.
// Carga un esquema mínimo con las mismas columnas que usan las funciones en producción y aplica, tal como están:
//   supabase/citas-turnos-jornada.sql (sin la activación de pg_cron, que no existe en la imagen básica)
//   supabase/notificaciones-idempotentes.sql
// Escenarios: turno asignado por el servidor, cita vencida → no_asistio sin repetir, avisos de laboratorio sin duplicados
// (repetición, reintento concurrente, resultado distinto), cancelación y cambios de jornada en las cuatro tablas.
// Uso: node scripts/test-notifications-sql.mjs   (requiere Docker con la imagen postgres:17-alpine)
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';

const name = 'hu-sql-test-' + process.pid;
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
const psql = (sql) => execFileSync('docker', ['exec', '-i', name, 'psql', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8' }).trim();
const psqlAsync = (sql) => new Promise((resolve, reject) => {
  const child = spawn('docker', ['exec', '-i', name, 'psql', '-U', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1']);
  let out = '', err = ''; child.stdout.on('data', d => out += d); child.stderr.on('data', d => err += d);
  child.on('close', code => code ? reject(new Error(err)) : resolve(out.trim())); child.stdin.end(sql);
});
const one = (sql) => psql(sql).split('\n').pop();
const results = [];
const ok = (label, fn) => { fn(); results.push(label); };

docker('run', '--rm', '-d', '--name', name, '-e', 'POSTGRES_PASSWORD=local-only', 'postgres:17-alpine');
try {
  for (let i = 0; i < 60; i++) { try { docker('exec', name, 'pg_isready', '-U', 'postgres'); psql('SELECT 1'); break; } catch { await new Promise(r => setTimeout(r, 500)); } }

  // Esquema mínimo (mismas columnas y restricciones relevantes que Hospital Móviles).
  psql(String.raw`
    CREATE SCHEMA private; CREATE SCHEMA auth; CREATE ROLE anon; CREATE ROLE authenticated;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    CREATE TYPE appointment_state AS ENUM ('programada','confirmada','en_atencion','completada','cancelada','no_asistio');
    CREATE TYPE hospital_role AS ENUM ('admin','doctor','recepcionista','paciente','enfermera');
    CREATE TABLE profiles(id uuid PRIMARY KEY, first_name text, last_name text);
    CREATE TABLE user_roles(user_id uuid, role hospital_role, active boolean DEFAULT true);
    CREATE TABLE panel_preferences(user_id uuid PRIMARY KEY, laboratory boolean);
    CREATE TABLE staff(id uuid PRIMARY KEY, profile_id uuid, active boolean DEFAULT true, category text);
    CREATE TABLE patients(id uuid PRIMARY KEY, profile_id uuid, first_name text, last_name text);
    CREATE TABLE medical_records(id uuid PRIMARY KEY, patient_id uuid);
    CREATE TABLE appointments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), patient_id uuid, doctor_id uuid, starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
      status appointment_state NOT NULL DEFAULT 'programada', queue_number integer CHECK (queue_number > 0), queue_date date, cancelled_by uuid, cancellation_reason text, CHECK (ends_at > starts_at));
    CREATE TABLE appointment_status_history(id bigserial PRIMARY KEY, appointment_id uuid NOT NULL, old_status appointment_state, new_status appointment_state NOT NULL, actor_id uuid, changed_at timestamptz NOT NULL DEFAULT now());
    CREATE TABLE clinical_encounters(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), appointment_id uuid UNIQUE, record_id uuid, doctor_id uuid, ended_at timestamptz);
    CREATE TABLE lab_orders(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), encounter_id uuid);
    CREATE TABLE lab_results(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid UNIQUE, summary text, result_values jsonb, parameter_schema jsonb,
      validated_by uuid, validated_at timestamptz, published_at timestamptz, published_to_patient_at timestamptz, published_revision integer NOT NULL DEFAULT 0);
    CREATE TABLE notifications(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), recipient_id uuid NOT NULL, title text NOT NULL, body text, kind text,
      read_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), entity_type text, entity_id text, event_key text);
    CREATE UNIQUE INDEX notification_event_once ON notifications(recipient_id, event_key) WHERE event_key IS NOT NULL;
    CREATE TABLE doctor_schedules(id serial PRIMARY KEY, doctor_id uuid, weekday int, start_time time, end_time time);
    CREATE TABLE staff_shifts(id serial PRIMARY KEY, staff_id uuid, starts_at timestamptz, ends_at timestamptz);
    CREATE TABLE staff_absences(id serial PRIMARY KEY, staff_id uuid, starts_at timestamptz, ends_at timestamptz, reason text, active boolean DEFAULT true);
    CREATE TABLE staff_recurring_journeys(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), staff_id uuid, breaks jsonb);
    -- Personas sintéticas: médico (D), segundo médico (D2), paciente (P).
    INSERT INTO profiles VALUES ('d0000000-0000-4000-8000-000000000001','Ana','Morales'),('d0000000-0000-4000-8000-000000000002','Luis','Herrera'),('a0000000-0000-4000-8000-000000000001','Juan','Pérez');
    INSERT INTO user_roles VALUES ('d0000000-0000-4000-8000-000000000001','doctor',true),('d0000000-0000-4000-8000-000000000002','doctor',true),('a0000000-0000-4000-8000-000000000001','paciente',true);
    INSERT INTO staff VALUES ('50000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001',true,'doctor'),('50000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000002',true,'doctor');
    INSERT INTO patients VALUES ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Juan','Pérez');
    INSERT INTO medical_records VALUES ('c0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001');
    INSERT INTO clinical_encounters(id, record_id, doctor_id) VALUES ('e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001');
    INSERT INTO lab_orders VALUES ('01000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001'),('02000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001');
    -- Estado real del 20/11: el mismo resultado publicado dos veces (revisiones 1 y 2) dejó dos avisos por destinatario.
    INSERT INTO lab_results(order_id, summary, result_values, parameter_schema, validated_by, validated_at, published_at, published_to_patient_at, published_revision)
      VALUES ('01000000-0000-4000-8000-000000000001','Hemoglobina normal','{"hb":{"value":13.8}}','[{"key":"hb"}]','d0000000-0000-4000-8000-000000000001',now(),now(),now(),2);
    INSERT INTO notifications(recipient_id,title,kind,entity_type,entity_id,event_key,created_at,read_at) VALUES
      ('a0000000-0000-4000-8000-000000000001','Resultados de laboratorio disponibles','laboratorio','lab_orders','01000000-0000-4000-8000-000000000001','lab:01000000-0000-4000-8000-000000000001:1:patient',now()-interval '95 seconds',now()),
      ('a0000000-0000-4000-8000-000000000001','Resultados de laboratorio disponibles','laboratorio','lab_orders','01000000-0000-4000-8000-000000000001','lab:01000000-0000-4000-8000-000000000001:2:patient',now(),now()),
      ('d0000000-0000-4000-8000-000000000001','Resultados de laboratorio disponibles','laboratorio','lab_orders','01000000-0000-4000-8000-000000000001','lab:01000000-0000-4000-8000-000000000001:1:doctor',now()-interval '95 seconds',null),
      ('d0000000-0000-4000-8000-000000000001','Resultados de laboratorio disponibles','laboratorio','lab_orders','01000000-0000-4000-8000-000000000001','lab:01000000-0000-4000-8000-000000000001:2:doctor',now(),null);
    -- Citas existentes antes de la migración: el 25/11 ya tiene el turno 7 (el contador debe continuar en 8).
    CREATE FUNCTION private.assign_appointment_queue() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
    INSERT INTO appointments(patient_id, doctor_id, starts_at, ends_at, status, queue_number, queue_date) VALUES
      ('b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002','2026-11-25 08:00-06','2026-11-25 08:30-06','programada',7,'2026-11-25');
    CREATE TRIGGER appointment_queue_assignment BEFORE INSERT OR UPDATE OF doctor_id, starts_at, queue_number, queue_date ON appointments FOR EACH ROW EXECUTE FUNCTION private.assign_appointment_queue();
  `);

  // Migraciones tal como están en el repositorio (se retira solo la activación de pg_cron).
  const citas = readFileSync('supabase/citas-turnos-jornada.sql', 'utf8')
    .replace(/CREATE EXTENSION IF NOT EXISTS pg_cron;[\s\S]*?END \$cron\$;/, '-- pg_cron omitido en la prueba local');
  assert.ok(!/cron\./.test(citas.replace(/--.*$/gm, '')), 'Solo se omite la activación de pg_cron');
  psql(citas);
  psql(readFileSync('supabase/notificaciones-idempotentes.sql', 'utf8'));
  psql(`CREATE TRIGGER laboratory_new_order_notice AFTER INSERT ON lab_orders FOR EACH ROW EXECUTE FUNCTION private.laboratory_notifications();
        CREATE TRIGGER laboratory_published_notice AFTER INSERT OR UPDATE ON lab_results FOR EACH ROW EXECUTE FUNCTION private.laboratory_notifications();`);
  const P = 'a0000000-0000-4000-8000-000000000001', D = 'd0000000-0000-4000-8000-000000000001', O1 = '01000000-0000-4000-8000-000000000001', O2 = '02000000-0000-4000-8000-000000000002';
  const count = (where) => Number(one(`SELECT count(*) FROM notifications WHERE ${where}`));

  // --- Turno y vencimiento (escenarios 1–6) ---
  ok('1. Recepción programa una cita: el servidor asigna el turno siguiente del día (8 tras el 7 existente)', () => {
    const n = one(`INSERT INTO appointments(patient_id, doctor_id, starts_at, ends_at, queue_number) VALUES ('b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','2026-11-25 10:00-06','2026-11-25 10:30-06', 99) RETURNING queue_number`);
    assert.equal(n, '8', 'El número enviado por el cliente (99) se ignora');
  });
  ok('3. Otra cita del mismo día con otro médico recibe un número distinto (turno por hospital y día)', () => {
    assert.equal(one(`INSERT INTO appointments(patient_id, doctor_id, starts_at, ends_at) VALUES ('b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002','2026-11-25 11:00-06','2026-11-25 11:30-06') RETURNING queue_number`), '9');
    assert.equal(one(`SELECT count(*) FROM (SELECT queue_date, queue_number FROM appointments GROUP BY 1,2 HAVING count(*) > 1) d`), '0');
  });
  ok('El turno no se puede editar a mano', () => {
    assert.throws(() => psql(`UPDATE appointments SET queue_number = 50 WHERE queue_number = 8`), /se asigna automáticamente/);
  });
  ok('4–5. Cita terminada sin atención → no_asistio; la iniciada, la que tiene consulta y la ya marcada no cambian; repetir no actualiza nada', () => {
    psql(`INSERT INTO appointments(id, patient_id, doctor_id, starts_at, ends_at, status) VALUES
      ('aa000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001',now()-interval '3 hours',now()-interval '150 minutes','programada'),
      ('aa000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002',now()-interval '5 hours',now()-interval '270 minutes','en_atencion'),
      ('aa000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001',now()-interval '7 hours',now()-interval '390 minutes','confirmada'),
      ('aa000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002',now()+interval '1 hour',now()+interval '90 minutes','programada');
      INSERT INTO clinical_encounters(appointment_id, record_id, doctor_id) VALUES ('aa000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001');`);
    assert.equal(one(`SELECT private.mark_missed_appointments()`), '1', 'Solo la programada vencida y sin consulta');
    assert.equal(one(`SELECT string_agg(status::text, ',' ORDER BY id) FROM appointments WHERE id::text LIKE 'aa000000%'`), 'no_asistio,en_atencion,confirmada,programada');
    assert.equal(one(`SELECT count(*) FROM appointment_status_history WHERE appointment_id='aa000000-0000-4000-8000-000000000001' AND new_status='no_asistio' AND old_status='programada'`), '1');
    assert.equal(one(`SELECT private.mark_missed_appointments()`), '0', 'Segunda pasada: nada que cambiar');
    assert.equal(one(`SELECT count(*) FROM appointment_status_history`), '1', 'Sin historial repetido');
  });
  ok('6. El turno de la cita vencida se conserva para el historial', () => {
    assert.notEqual(one(`SELECT queue_number FROM appointments WHERE id='aa000000-0000-4000-8000-000000000001'`), '');
  });

  // --- Laboratorio (escenarios 7–12) ---
  ok('Duplicados existentes: el más reciente adopta la clave estable y no se borra nada', () => {
    assert.equal(count(`recipient_id='${P}' AND entity_id='${O1}'`), 2, 'No se elimina ningún aviso histórico');
    assert.equal(count(`recipient_id='${P}' AND event_key='lab:${O1}:result:patient'`), 1);
    assert.equal(count(`recipient_id='${D}' AND event_key='lab:${O1}:result:doctor'`), 1);
  });
  ok('9–10. Volver a publicar el mismo resultado (publish_lab_result otra vez) no crea otro aviso', () => {
    psql(`UPDATE lab_results SET published_at=now(), validated_at=now(), published_to_patient_at=now(), published_revision=published_revision+1 WHERE order_id='${O1}'`);
    assert.equal(count(`recipient_id='${P}' AND entity_id='${O1}'`), 2);
    assert.equal(count(`recipient_id='${D}' AND entity_id='${O1}'`), 2);
  });
  ok('7–8 y 11–12. Un resultado de OTRA orden genera un aviso legítimo por destinatario', () => {
    psql(`INSERT INTO lab_results(order_id, summary, result_values, parameter_schema, validated_by, validated_at, published_at, published_to_patient_at, published_revision)
          VALUES ('${O2}','Glucosa 92 mg/dL','{"glu":{"value":92}}','[{"key":"glu"}]','${D}',now(),now(),now(),1)`);
    assert.equal(count(`recipient_id='${P}' AND entity_id='${O2}'`), 1);
    assert.equal(count(`recipient_id='${D}' AND entity_id='${O2}'`), 1);
  });
  ok('Republicar la segunda orden igual: sigue habiendo un solo aviso', () => {
    psql(`UPDATE lab_results SET published_at=now(), published_revision=published_revision+1 WHERE order_id='${O2}'`);
    assert.equal(count(`recipient_id='${P}' AND entity_id='${O2}'`), 1);
  });
  ok('Republicar con contenido corregido: se actualiza el mismo aviso (no leído, «actualizados»), sin crear otro', () => {
    psql(`UPDATE notifications SET read_at=now() WHERE entity_id='${O2}'`);
    psql(`UPDATE lab_results SET summary='Glucosa 95 mg/dL', result_values='{"glu":{"value":95}}', published_at=now(), published_revision=published_revision+1 WHERE order_id='${O2}'`);
    assert.equal(count(`recipient_id='${P}' AND entity_id='${O2}'`), 1);
    assert.equal(one(`SELECT title || '|' || (read_at IS NULL) FROM notifications WHERE recipient_id='${P}' AND entity_id='${O2}'`), 'Resultados de laboratorio actualizados|true');
  });
  results.push(await (async () => {
    // Reintento concurrente: dos publicaciones simultáneas de la misma orden.
    const publish = `BEGIN; UPDATE lab_results SET published_at=now(), published_revision=published_revision+1 WHERE order_id='${O2}'; SELECT pg_sleep(0.6); COMMIT;`;
    await Promise.all([psqlAsync(publish), psqlAsync(publish)]);
    assert.equal(count(`recipient_id='${P}' AND entity_id='${O2}'`), 1);
    assert.equal(count(`recipient_id='${D}' AND entity_id='${O2}'`), 1);
    return 'Dos publicaciones simultáneas de la misma orden: un solo aviso por destinatario';
  })());
  ok('Ningún destinatario tiene dos avisos con la misma clave', () => {
    assert.equal(one(`SELECT count(*) FROM (SELECT recipient_id, event_key FROM notifications WHERE event_key IS NOT NULL GROUP BY 1,2 HAVING count(*)>1) d`), '0');
  });

  // --- Médico: cancelación y jornada ---
  ok('Cancelación por el paciente: un aviso al médico con nombre, fecha y hora; repetir la operación no crea otro', () => {
    psql(`INSERT INTO appointments(id, patient_id, doctor_id, starts_at, ends_at) VALUES ('cc000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','2026-11-20 10:30-06','2026-11-20 11:00-06')`);
    psql(`UPDATE appointments SET status='cancelada', cancelled_by='${P}', cancellation_reason='Viaje' WHERE id='cc000000-0000-4000-8000-000000000001'`);
    psql(`UPDATE appointments SET status='cancelada' WHERE id='cc000000-0000-4000-8000-000000000001'`);
    psql(`UPDATE appointments SET cancellation_reason='Viaje imprevisto' WHERE id='cc000000-0000-4000-8000-000000000001'`);
    assert.equal(count(`recipient_id='${D}' AND entity_id='cc000000-0000-4000-8000-000000000001'`), 1);
    assert.equal(one(`SELECT body FROM notifications WHERE recipient_id='${D}' AND entity_id='cc000000-0000-4000-8000-000000000001'`),
      'El paciente Juan Pérez ha cancelado su cita programada para el 20 de noviembre a las 10:30 a. m. Motivo: Viaje.');
  });
  ok('Una misma modificación de jornada (varias filas y tablas en un guardado) genera un solo aviso', () => {
    psql(`BEGIN;
      INSERT INTO doctor_schedules(doctor_id, weekday, start_time, end_time) VALUES ('50000000-0000-4000-8000-000000000001',1,'07:00','12:00'),('50000000-0000-4000-8000-000000000001',1,'13:00','17:00');
      INSERT INTO staff_shifts(staff_id, starts_at, ends_at) VALUES ('50000000-0000-4000-8000-000000000001',now(),now()+interval '8 hours');
      INSERT INTO staff_absences(staff_id, starts_at, ends_at, reason) VALUES ('50000000-0000-4000-8000-000000000001',now()+interval '1 day',now()+interval '2 days','Capacitación');
      INSERT INTO staff_recurring_journeys(staff_id, breaks) VALUES ('50000000-0000-4000-8000-000000000001','[{"reason":"Almuerzo","start_time":"12:00","end_time":"13:00"}]');
      COMMIT;`);
    assert.equal(count(`recipient_id='${D}' AND kind='jornada'`), 1);
  });
  ok('Cada tabla de jornada avisa por sí sola: semanal, por fecha, ausencias y recurrente (un aviso por guardado)', () => {
    psql(`UPDATE doctor_schedules SET end_time='12:30' WHERE id=1`);
    psql(`UPDATE staff_shifts SET ends_at=ends_at+interval '1 hour'`);
    psql(`UPDATE staff_absences SET reason='Congreso'`);
    psql(`UPDATE staff_recurring_journeys SET breaks='[{"reason":"Almuerzo","start_time":"12:30","end_time":"13:30"}]'`);
    assert.equal(count(`recipient_id='${D}' AND kind='jornada'`), 5);
    assert.equal(one(`SELECT string_agg(DISTINCT entity_type, ',' ORDER BY entity_type) FROM notifications WHERE kind='jornada'`), 'doctor_schedules,staff_absences,staff_recurring_journeys,staff_shifts');
    assert.match(one(`SELECT body FROM notifications WHERE entity_type='staff_recurring_journeys' LIMIT 1`), /jornada recurrente \(horario, almuerzo o descansos\)/);
  });
  ok('Las migraciones se pueden ejecutar otra vez sin duplicar avisos ni objetos', () => {
    const before = one(`SELECT count(*) FROM notifications`);
    psql(citas); psql(readFileSync('supabase/notificaciones-idempotentes.sql', 'utf8'));
    assert.equal(one(`SELECT count(*) FROM notifications`), before);
    assert.equal(one(`SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'doctor_%notice'`), '5');
  });
} finally {
  try { docker('rm', '-f', name); } catch {}
}
for (const line of results) console.log('OK  ' + line);
console.log(`OK SQL local (PostgreSQL 17, contenedor desechable): ${results.length} escenarios de turno, vencimiento y avisos sin duplicados`);
