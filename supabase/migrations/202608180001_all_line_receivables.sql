-- LINE's receivable view now presents the complete outstanding list in one
-- reply. A null p_limit therefore means "all"; callers that pass a number
-- retain the previous bounded-query behavior.
create or replace function public.line_list_receivables(
  p_line_user_id text,
  p_limit integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  items jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  if p_limit is not null then
    p_limit := greatest(1, least(p_limit, 100));
  end if;

  delete from public.line_action_tokens
  where line_user_id = p_line_user_id and expires_at < now();

  with pending as (
    select o.id as order_id, o.name as order_name, p.id as participant_id,
           p.name as participant_name,
           coalesce(p.final_due_minor, p.suggested_due_minor,
                    greatest(p.item_amount_minor + p.shared_fee_minor
                             - p.discount_minor, 0)) as amount_minor,
           o.order_date
    from public.group_orders o
    join public.order_participants p
      on p.user_id = o.user_id and p.order_id = o.id
    where o.user_id = uid and not p.is_self
      and p.collection_status not in ('paid', 'cancelled')
    order by o.order_date desc, p.id
    limit p_limit
  ), issued as (
    insert into public.line_action_tokens(
      user_id, line_user_id, action, payload
    )
    select uid, p_line_user_id, 'mark_received',
           jsonb_build_object(
             'orderId', order_id, 'participantId', participant_id
           )
    from pending
    returning token, payload
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'token', i.token,
    'orderName', p.order_name,
    'participantName', p.participant_name,
    'amountMinor', p.amount_minor
  ) order by p.order_date desc, p.participant_id), '[]'::jsonb)
  into items
  from pending p
  join issued i
    on i.payload->>'orderId' = p.order_id
   and i.payload->>'participantId' = p.participant_id;

  return jsonb_build_object('status', 'ok', 'items', items);
end
$$;

revoke all on function public.line_list_receivables(text, integer) from public;
grant execute on function public.line_list_receivables(text, integer)
  to service_role;
