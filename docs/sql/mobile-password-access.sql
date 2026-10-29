-- Apply after the existing schema and mobile module scripts.
-- User decision 2026-10-28: password authentication for mobile doctor/patient roles.
begin;
create or replace function private.session_active(require_mfa boolean default false)
returns boolean language sql stable security definer set search_path = '' as $function$
 select auth.uid() is not null
 and exists(select 1 from hospital.profiles p where p.id=auth.uid() and p.status='active')
 and exists(select 1 from auth.sessions s where s.id::text=auth.jwt()->>'session_id'
   and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()))
 and (not require_mfa or auth.jwt()->>'aal'='aal2' or (
   exists(select 1 from hospital.user_role_assignments a join hospital.roles r on r.id=a.role_id
     where a.profile_id=auth.uid() and a.revoked_at is null and r.code in ('doctor','patient'))
   and not exists(select 1 from hospital.user_role_assignments a join hospital.roles r on r.id=a.role_id
     where a.profile_id=auth.uid() and a.revoked_at is null and r.code not in ('doctor','patient'))
 ));
$function$;
-- The signature, owner and ACL of the existing helper remain unchanged.
notify pgrst, 'reload schema';
commit;
