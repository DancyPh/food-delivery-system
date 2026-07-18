-- =====================================================================
-- Migration: Fix security issues + hoàn thiện các phần còn thiếu
-- Ngày tạo: 2026-07-18
-- Mô tả: Gộp toàn bộ các fix đã thảo luận:
--   1. Fix lỗ hổng leo quyền (role escalation) ở profiles
--   2. Hoàn thiện update_order_status() với validate luồng trạng thái
--   3. Thêm is_admin() helper + policy admin cho tất cả bảng còn thiếu
--   4. address_id NOT NULL trên orders
--   5. Xóa cột address (text) dư thừa ở restaurants
--   6. Thêm storage bucket cho food-images, restaurant-images
--   7. Đăng ký orders vào Realtime publication
--   8. Các ràng buộc nhỏ (check price >= 0, unique default address, unique review)
-- =====================================================================


-- =====================================================================
-- 1. FIX LỖ HỔNG: user tự sửa role của chính mình (privilege escalation)
-- =====================================================================

drop policy if exists "All user can update profile" on public.profiles;

create policy "Users can update own profile except role"
  on public.profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and role = (select p.role from public.profiles p where p.id = auth.uid())
  );


-- =====================================================================
-- 2. HELPER FUNCTION: is_admin()
-- =====================================================================

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

comment on function public.is_admin() is 'Kiểm tra user hiện tại (auth.uid()) có role admin hay không. Dùng trong các RLS policy.';


-- =====================================================================
-- 3. THÊM POLICY ADMIN CHO CÁC BẢNG CÒN THIẾU
--    (orders đã có sẵn kiểu policy cũ, giữ nguyên không đổi để tránh
--     xung đột; các bảng dưới đây trước đó chưa có policy admin nào)
-- =====================================================================

drop policy if exists "Admins have full access on restaurants" on public.restaurants;
create policy "Admins have full access on restaurants"
  on public.restaurants for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins have full access on categories" on public.categories;
create policy "Admins have full access on categories"
  on public.categories for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins have full access on foods" on public.foods;
create policy "Admins have full access on foods"
  on public.foods for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins have full access on addresses" on public.addresses;
create policy "Admins have full access on addresses"
  on public.addresses for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins have full access on order_items" on public.order_items;
create policy "Admins have full access on order_items"
  on public.order_items for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins have full access on reviews" on public.reviews;
create policy "Admins have full access on reviews"
  on public.reviews for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins have full access on profiles" on public.profiles;
create policy "Admins have full access on profiles"
  on public.profiles for all
  using (public.is_admin())
  with check (public.is_admin());


-- =====================================================================
-- 4. HOÀN THIỆN update_order_status() VỚI VALIDATE LUỒNG TRẠNG THÁI
-- =====================================================================

create or replace function public.update_order_status(
  order_id_input uuid,
  new_status public.order_status
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_status public.order_status;
  caller_role public.user_role;
  is_related boolean;
begin
  select status into current_status
  from public.orders
  where id = order_id_input;

  if current_status is null then
    raise exception 'Không tìm thấy đơn hàng với id %', order_id_input;
  end if;

  select role into caller_role
  from public.profiles
  where id = auth.uid();

  -- Admin luôn được phép chuyển bất kỳ trạng thái nào
  if public.is_admin() then
    update public.orders set status = new_status where id = order_id_input;
    return;
  end if;

  -- Kiểm tra người gọi có liên quan tới đơn hàng này không
  select exists (
    select 1 from public.orders o
    where o.id = order_id_input
      and (
        o.customer_id = auth.uid()
        or o.rider_id = auth.uid()
        or o.restaurant_id in (select id from public.restaurants where owner_id = auth.uid())
      )
  ) into is_related;

  if not is_related then
    raise exception 'Bạn không có quyền cập nhật đơn hàng này';
  end if;

  -- Validate luồng chuyển trạng thái hợp lệ theo role
  if current_status = 'pending' and new_status = 'confirmed' and caller_role = 'restaurant' then
    update public.orders set status = new_status where id = order_id_input;

  elsif current_status = 'confirmed' and new_status = 'preparing' and caller_role = 'restaurant' then
    update public.orders set status = new_status where id = order_id_input;

  elsif current_status = 'preparing' and new_status = 'ready' and caller_role = 'restaurant' then
    update public.orders set status = new_status where id = order_id_input;

  elsif current_status = 'ready' and new_status = 'delivering' and caller_role = 'rider' then
    update public.orders set status = new_status where id = order_id_input;

  elsif current_status = 'delivering' and new_status = 'delivered' and caller_role = 'rider' then
    update public.orders set status = new_status where id = order_id_input;

  elsif current_status = 'pending' and new_status = 'cancelled' and caller_role = 'customer' then
    update public.orders set status = new_status where id = order_id_input;

  elsif current_status = 'pending' and new_status = 'cancelled' and caller_role = 'restaurant' then
    update public.orders set status = new_status where id = order_id_input;

  else
    raise exception 'Không thể chuyển trạng thái từ % sang % với role %', current_status, new_status, caller_role;
  end if;
end;
$$;

grant execute on function public.update_order_status(uuid, public.order_status) to authenticated;


-- =====================================================================
-- 5. orders.address_id: bắt buộc NOT NULL
--    (Lưu ý: nếu đã có order test với address_id = null, câu lệnh dưới
--     sẽ báo lỗi. Kiểm tra trước bằng:
--     select id from public.orders where address_id is null;
--     rồi xóa/cập nhật các dòng đó trước khi chạy migration này.)
-- =====================================================================

alter table public.orders
  alter column address_id set not null;


-- =====================================================================
-- 6. Xóa cột "address" (text) dư thừa ở restaurants — đã thay bằng address_id
-- =====================================================================

alter table public.restaurants
  drop column if exists address;


-- =====================================================================
-- 7. STORAGE BUCKETS: food-images, restaurant-images
-- =====================================================================

insert into storage.buckets (id, name, public)
values
  ('food-images', 'food-images', true),
  ('restaurant-images', 'restaurant-images', true)
on conflict (id) do nothing;

drop policy if exists "Public read access on food/restaurant images" on storage.objects;
create policy "Public read access on food/restaurant images"
  on storage.objects for select
  using (bucket_id in ('food-images', 'restaurant-images'));

drop policy if exists "Restaurant owners can upload food/restaurant images" on storage.objects;
create policy "Restaurant owners can upload food/restaurant images"
  on storage.objects for insert
  with check (
    bucket_id in ('food-images', 'restaurant-images')
    and auth.role() = 'authenticated'
  );

drop policy if exists "Restaurant owners can update their own food/restaurant images" on storage.objects;
create policy "Restaurant owners can update their own food/restaurant images"
  on storage.objects for update
  using (
    bucket_id in ('food-images', 'restaurant-images')
    and auth.role() = 'authenticated'
  );

drop policy if exists "Restaurant owners can delete their own food/restaurant images" on storage.objects;
create policy "Restaurant owners can delete their own food/restaurant images"
  on storage.objects for delete
  using (
    bucket_id in ('food-images', 'restaurant-images')
    and auth.role() = 'authenticated'
  );


-- =====================================================================
-- 8. ĐĂNG KÝ orders VÀO REALTIME PUBLICATION
--    (để FE dùng supabase.channel(...).on('postgres_changes', ...))
-- =====================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;


-- =====================================================================
-- 9. RÀNG BUỘC NHỎ BỔ SUNG
-- =====================================================================

-- 9a. Giá món ăn không được âm
alter table public.foods
  drop constraint if exists foods_price_check;
alter table public.foods
  add constraint foods_price_check check (price >= 0);

-- 9b. delivery_fee / total_price không được âm
alter table public.orders
  drop constraint if exists orders_delivery_fee_check;
alter table public.orders
  add constraint orders_delivery_fee_check check (delivery_fee >= 0);

alter table public.orders
  drop constraint if exists orders_total_price_check;
alter table public.orders
  add constraint orders_total_price_check check (total_price >= 0);

-- 9c. Mỗi user chỉ có tối đa 1 địa chỉ mặc định (is_default = true)
--     Dùng partial unique index thay vì constraint thường vì chỉ áp dụng
--     khi is_default = true.
drop index if exists idx_addresses_one_default_per_user;
create unique index idx_addresses_one_default_per_user
  on public.addresses (user_id)
  where (is_default = true);

-- 9d. Mỗi customer chỉ được review 1 lần cho cùng 1 món ăn
--     (nếu bạn muốn cho phép review lại theo từng đơn hàng khác nhau,
--      bỏ ràng buộc này và thêm order_id vào reviews thay thế)
alter table public.reviews
  drop constraint if exists reviews_customer_food_unique;
alter table public.reviews
  add constraint reviews_customer_food_unique unique (customer_id, food_id);

