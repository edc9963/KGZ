-- Restrict receivable collection to cash or a selected active TWD bank account.

insert into public.accounts(
  user_id, id, name, institution, account_type, currency,
  opening_balance_minor, is_active, note, created_at, updated_at, origin
)
select
  user_id, 'system-cash', '現金', '', '現金', 'TWD',
  0, true, '系統固定帳戶', now(), now(), 'user'
from public.user_settings
on conflict (user_id, id) do nothing;

create or replace function public.line_mark_received(
  p_line_user_id text,
  p_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  action_row public.line_action_tokens%rowtype;
  current_revision bigint;
  next_revision bigint;
  was_paid boolean;
  method text;
  target_account_id text;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select * into action_row from public.line_action_tokens
  where token = p_token and user_id = uid and line_user_id = p_line_user_id
    and action = 'mark_received'
  for update;
  if not found or action_row.expires_at < now() then
    return jsonb_build_object('status', 'expired');
  end if;
  if action_row.consumed_at is not null then
    return jsonb_build_object('status', 'already_processed');
  end if;

  select collection_status = 'paid', collection_method, collection_account_id
  into was_paid, method, target_account_id
  from public.order_participants
  where user_id = uid
    and order_id = action_row.payload->>'orderId'
    and id = action_row.payload->>'participantId'
  for update;
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  if was_paid then return jsonb_build_object('status', 'already_paid'); end if;

  if method = '現金' then
    target_account_id := 'system-cash';
    insert into public.accounts(
      user_id, id, name, institution, account_type, currency,
      opening_balance_minor, is_active, note, created_at, updated_at, origin
    ) values (
      uid, target_account_id, '現金', '', '現金', 'TWD',
      0, true, '系統固定帳戶', now(), now(), 'user'
    ) on conflict (user_id, id) do nothing;
  elsif method = '銀行轉帳' then
    if target_account_id is null or not exists (
      select 1 from public.accounts
      where user_id = uid and id = target_account_id and is_active
        and account_type = '銀行帳戶' and currency = 'TWD'
    ) then
      return jsonb_build_object('status', 'invalid_collection');
    end if;
  else
    return jsonb_build_object('status', 'invalid_collection');
  end if;

  update public.line_action_tokens set consumed_at = now()
  where token = p_token;
  insert into public.finance_sync_state(user_id, revision)
  values (uid, 0) on conflict (user_id) do nothing;
  select revision into current_revision
  from public.finance_sync_state where user_id = uid for update;

  update public.order_participants
  set collection_status = 'paid', collection_account_id = target_account_id,
      collected_at = now()
  where user_id = uid
    and order_id = action_row.payload->>'orderId'
    and id = action_row.payload->>'participantId';
  next_revision := current_revision + 1;
  update public.finance_sync_state
  set revision = next_revision, updated_at = now() where user_id = uid;
  return jsonb_build_object('status', 'saved', 'revision', next_revision);
end
$$;
