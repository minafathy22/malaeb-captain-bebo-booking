-- Applied to the connected database: public_booking_respect_daily_and_special_work_hours
-- Keep existing pricing, permissions, booking overlap checks and rate limits.
CREATE OR REPLACE FUNCTION private.public_booking_work_hours(p_venue text,p_date date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO public,pg_catalog AS $$
select jsonb_build_object('open',coalesce((chosen->>'open')::integer,open_hour,0),'close',coalesce((chosen->>'close')::integer,close_hour,24))
from (select s.open_hour,s.close_hour,coalesce(s.message_templates->'_special_work_hours_v1'->to_char(p_date,'YYYY-MM-DD'),s.message_templates->'_daily_work_hours_v1'->(extract(dow from p_date)::integer)::text) as chosen
from public.settings s where s.id in ('pricing_'||p_venue,'pricing') order by (s.id='pricing_'||p_venue) desc limit 1) x;
$$;
REVOKE ALL ON FUNCTION private.public_booking_work_hours(text,date) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.pitch_public_availability(p_venue text, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
declare v_hours jsonb; st record; arr jsonb; v_dk text:=private.app_date_to_key(p_date); v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
 if p_date<v_today or p_date>v_today+14 then raise exception 'DATE_OUT_OF_RANGE'; end if;
 if not exists(select 1 from public.venues where id=p_venue and active) then raise exception 'VENUE_NOT_FOUND'; end if;
 select * into st from public.settings where id='pricing_'||p_venue; if not found then select * into st from public.settings where id='pricing'; end if;
 v_hours:=private.public_booking_work_hours(p_venue,p_date);
 with hs as(select generate_series((v_hours->>'open')::int,(v_hours->>'close')::int-1) h)
 select jsonb_agg(jsonb_build_object('hour',h,'price',case when (st.eve_start<coalesce(st.eve_end,6) and h>=st.eve_start and h<st.eve_end) or (st.eve_start>=coalesce(st.eve_end,6) and (h>=st.eve_start or h<st.eve_end)) then st.eve_rate else st.day_rate end,
 'available',not(exists(select 1 from public.bookings b where coalesce(b.venue,'rey')=p_venue and b.deleted_at is null and b.id=p_venue||'-'||v_dk||'-'||h)
 or exists(select 1 from public.repeat_rules r where coalesce(r.venue,'rey')=p_venue and r.deleted_at is null and r.weekday=extract(dow from p_date)::int and coalesce(r.start_date,date '1900-01-01')<=p_date and coalesce(r.until,date '9999-12-31')>=p_date and h>=r.hour and h<r.hour+greatest(1,coalesce(r.span,1)) and not exists(select 1 from public.repeat_exceptions_calendar_v e where e.rule_id=r.id and e.calendar_date=p_date))
 or private.request_slot_overlap(p_venue,p_date,h,null)
 or (p_date=v_today and h<=extract(hour from now() at time zone 'Africa/Cairo')::int)))) into arr from hs;
 return jsonb_build_object('venue',p_venue,'date',p_date,'slots',coalesce(arr,'[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.pitch_public_submit_booking(p_venue text, p_date date, p_hour integer, p_span integer, p_name text, p_phone text, p_details text DEFAULT NULL::text, p_sponsor_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions', 'pg_catalog'
AS $function$
declare v_hours jsonb; st record; v_price numeric:=0; i int; v_id text; v_group text; v_phone text; v_today date:=(now() at time zone 'Africa/Cairo')::date; v_subject text; sd date; sh int; sdk text;
begin
 if p_date<v_today or p_date>v_today+14 then raise exception 'DATE_OUT_OF_RANGE'; end if;
 if p_hour<0 or p_hour>23 or p_span<1 or p_span>6 then raise exception 'INVALID_DURATION'; end if;
 if nullif(trim(p_name),'') is null then raise exception 'NAME_REQUIRED'; end if;
 v_phone:=regexp_replace(coalesce(p_phone,''),'\D','','g');
 if v_phone like '0020%' then v_phone:=substr(v_phone,5); elsif length(v_phone)>=12 and v_phone like '20%' then v_phone:=substr(v_phone,3); end if;
 if length(v_phone)=10 and v_phone like '1%' then v_phone:='0'||v_phone; end if;
 if v_phone !~ '^01[0-9]{9}$' then raise exception 'INVALID_PHONE'; end if;
 if exists(select 1 from public.customers where phone=v_phone and blocked is true) then raise exception 'CUSTOMER_BLOCKED'; end if;
 if not exists(select 1 from public.venues where id=p_venue and active) then raise exception 'VENUE_NOT_FOUND'; end if;
 v_subject:=encode(extensions.digest(v_phone,'sha256'),'hex');
 if not private.public_rate_limit('booking_phone',4,3600,v_subject) or not private.public_rate_limit('booking_client',12,3600,null) then raise exception 'RATE_LIMITED'; end if;
 select * into st from public.settings where id='pricing_'||p_venue; if not found then select * into st from public.settings where id='pricing'; end if;
 for i in 0..p_span-1 loop
   sd:=p_date+((p_hour+i)/24); sh:=(p_hour+i)%24;
   v_hours:=private.public_booking_work_hours(p_venue,sd);
   if v_hours is null or sh<(v_hours->>'open')::int or sh+1>(v_hours->>'close')::int then raise exception 'OUTSIDE_WORK_HOURS'; end if;
 end loop;
 for i in 0..p_span-1 loop sd:=p_date+((p_hour+i)/24); sh:=(p_hour+i)%24; perform pg_advisory_xact_lock(hashtext(p_venue||'|'||sd::text||'|'||sh::text)); end loop;
 for i in 0..p_span-1 loop
   sd:=p_date+((p_hour+i)/24); sh:=(p_hour+i)%24; sdk:=private.app_date_to_key(sd);
   if exists(select 1 from public.bookings b where coalesce(b.venue,'rey')=p_venue and b.deleted_at is null and b.id=p_venue||'-'||sdk||'-'||sh)
   or exists(select 1 from public.repeat_rules r where coalesce(r.venue,'rey')=p_venue and r.deleted_at is null and r.weekday=extract(dow from sd)::int and coalesce(r.start_date,date '1900-01-01')<=sd and coalesce(r.until,date '9999-12-31')>=sd and sh>=r.hour and sh<r.hour+greatest(1,coalesce(r.span,1)) and not exists(select 1 from public.repeat_exceptions_calendar_v e where e.rule_id=r.id and e.calendar_date=sd))
   or private.request_slot_overlap(p_venue,sd,sh,null) then raise exception 'SLOT_TAKEN'; end if;
   v_price:=v_price+(case when (st.eve_start<coalesce(st.eve_end,6) and sh>=st.eve_start and sh<st.eve_end) or (st.eve_start>=coalesce(st.eve_end,6) and (sh>=st.eve_start or sh<st.eve_end)) then st.eve_rate else st.day_rate end);
 end loop;
 v_id:='web_'||replace(gen_random_uuid()::text,'-',''); v_group:='webgrp_'||replace(gen_random_uuid()::text,'-','');
 insert into public.booking_requests(id,date_key,hour,name,phone,details,status,venue,span,quoted_price,source,expires_at,sponsor_code,group_id)
 values(v_id,private.app_date_to_key(p_date),p_hour,trim(p_name),v_phone,nullif(trim(coalesce(p_details,'')),''),'pending',p_venue,p_span,v_price,'public_web',now()+interval '30 minutes',left(p_sponsor_code,80),v_group);
 return jsonb_build_object('id',v_id,'group_id',v_group,'price',v_price,'expires_at',now()+interval '30 minutes','start_date',p_date,'start_hour',p_hour,'span',p_span,'end_date',p_date+((p_hour+p_span-1)/24),'end_hour',(p_hour+p_span)%24);
end $function$
;
