-- Atomic composition of existing clinical RPCs; no privileged bypass.
begin;
create or replace function public.doctor_submit_lab_request(
  p_encounter uuid, p_test uuid, p_instructions text, p_request_key uuid,
  p_weight numeric, p_height numeric
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_order jsonb;
begin
  if p_weight is null or p_height is null or p_weight < 0.1 or p_weight > 500 or p_height < 20 or p_height > 250 then
    raise check_violation using message='Peso o altura fuera del intervalo permitido';
  end if;
  v_order := public.doctor_issue_lab_order(p_encounter,p_test,p_instructions,p_request_key);
  perform public.create_record('vital_sign_sets',
    jsonb_build_object('encounter_id',p_encounter,'weight_kg',p_weight,'height_cm',p_height),
    md5(p_request_key::text || ':vitals')::uuid);
  return v_order;
end $$;
revoke all on function public.doctor_submit_lab_request(uuid,uuid,text,uuid,numeric,numeric) from public,anon;
grant execute on function public.doctor_submit_lab_request(uuid,uuid,text,uuid,numeric,numeric) to authenticated;
notify pgrst,'reload schema';
commit;

