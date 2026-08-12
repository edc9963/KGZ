-- Allow a high-entropy collection token to expose only the matching payment
-- request, and to move that request from unpaid to pending. No owner id,
-- account id, card data, or unrelated finance data is returned.

-- Earlier demo datasets used fixed sample tokens. Rotate duplicates before
-- enforcing global uniqueness so a token can never resolve to two users.
with ranked_tokens as (
  select ctid,
         row_number() over (
           partition by collection_token
           order by user_id, order_id, id
         ) as position
  from public.order_participants
  where not is_self
)
update public.order_participants p
set collection_token = gen_random_uuid()::text
from ranked_tokens ranked
where p.ctid = ranked.ctid
  and (ranked.position > 1 or p.collection_token = '');

create unique index if not exists order_participants_collection_token_idx
  on public.order_participants(collection_token)
  where not is_self;

create or replace function public.load_public_collection(p_token text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select jsonb_build_object(
      'status', 'ok',
      'orderName', o.name,
      'orderDate', o.order_date,
      'orderNote', o.note,
      'participantName', p.name,
      'itemName', p.item_name,
      'itemAmountMinor', p.item_amount_minor,
      'sharedFeeMinor', p.shared_fee_minor,
      'discountMinor', p.discount_minor,
      'dueMinor', coalesce(
        p.final_due_minor,
        p.suggested_due_minor,
        greatest(p.item_amount_minor + p.shared_fee_minor - p.discount_minor, 0)
      ),
      'collectionStatus', p.collection_status,
      'collectionMethod', p.collection_method,
      'bankQrData', case
        when p.collection_method = '銀行轉帳' then coalesce(s.bank_qr_data, '')
        else ''
      end,
      'bankAccountInfo', case
        when p.collection_method = '銀行轉帳' then coalesce(s.bank_account_info, '')
        else ''
      end
    )
    from public.order_participants p
    join public.group_orders o
      on o.user_id = p.user_id and o.id = p.order_id
    left join public.user_settings s on s.user_id = p.user_id
    where p.collection_token = p_token
      and not p.is_self
    limit 1
  ), jsonb_build_object('status', 'not_found'));
$$;

create or replace function public.mark_public_collection_pending(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_user uuid;
  changed integer;
begin
  update public.order_participants
  set collection_status = 'pending'
  where collection_token = p_token
    and not is_self
    and collection_status = 'unpaid'
  returning user_id into target_user;

  get diagnostics changed = row_count;
  if changed = 1 then
    insert into public.finance_sync_state(user_id, revision, updated_at)
    values (target_user, 1, now())
    on conflict (user_id) do update
      set revision = public.finance_sync_state.revision + 1,
          updated_at = now();
  end if;

  if not exists (
    select 1 from public.order_participants
    where collection_token = p_token and not is_self
  ) then
    return jsonb_build_object('status', 'not_found');
  end if;

  return jsonb_build_object('status', 'ok');
end
$$;

revoke all on function public.load_public_collection(text) from public;
revoke all on function public.mark_public_collection_pending(text) from public;
grant execute on function public.load_public_collection(text) to anon, authenticated;
grant execute on function public.mark_public_collection_pending(text) to anon, authenticated;
