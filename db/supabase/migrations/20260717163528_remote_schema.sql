


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "cube" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "earthdistance" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."order_status" AS ENUM (
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'delivering',
    'delivered',
    'cancelled'
);


ALTER TYPE "public"."order_status" OWNER TO "postgres";


CREATE TYPE "public"."payment_method" AS ENUM (
    'cash',
    'momo',
    'vnpay'
);


ALTER TYPE "public"."payment_method" OWNER TO "postgres";


CREATE TYPE "public"."payment_status" AS ENUM (
    'unpaid',
    'paid',
    'refunded'
);


ALTER TYPE "public"."payment_status" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'customer',
    'restaurant',
    'rider',
    'admin'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_distance_km"("lat1" numeric, "lng1" numeric, "lat2" numeric, "lng2" numeric) RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select earth_distance(
    ll_to_earth(lat1, lng1),
    ll_to_earth(lat2, lng2)
  ) / 1000; -- earth_distance trả về mét, chia 1000 ra km
$$;


ALTER FUNCTION "public"."calculate_distance_km"("lat1" numeric, "lng1" numeric, "lat2" numeric, "lng2" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_subtotal"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.subtotal := new.quantity * new.price;
  return new;
end;
$$;


ALTER FUNCTION "public"."calculate_subtotal"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  )
  on conflict (id) do update
    set email = excluded.email,
        full_name = excluded.full_name;

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_delivery_fee"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  restaurant_lat numeric;
  restaurant_lng numeric;
  address_lat numeric;
  address_lng numeric;
  distance_km numeric;
begin
  -- Lấy tọa độ nhà hàng qua owner_id -> addresses.user_id
  select a.latitude, a.longitude into restaurant_lat, restaurant_lng
  from public.restaurants r
  join public.addresses a on a.user_id = r.owner_id
  where r.id = new.restaurant_id
  limit 1;

  -- Lấy tọa độ địa chỉ giao hàng
  select latitude, longitude into address_lat, address_lng
  from public.addresses
  where id = new.address_id;

  -- Kiểm tra nếu thiếu tọa độ thì báo lỗi rõ ràng thay vì lỗi ngầm
  if restaurant_lat is null or address_lat is null then
    raise exception 'Không tìm thấy tọa độ nhà hàng hoặc địa chỉ giao hàng';
  end if;

  distance_km := public.calculate_distance_km(restaurant_lat, restaurant_lng, address_lat, address_lng);

  new.delivery_fee := round(distance_km * 5000, 0); -- 5.000đ/km, chỉnh lại theo giá bạn muốn
  return new;
end;
$$;


ALTER FUNCTION "public"."set_delivery_fee"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_order_item_price"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  select price into new.price from public.foods where id = new.food_id;
  new.subtotal := new.quantity * new.price;
  return new;
end;
$$;


ALTER FUNCTION "public"."set_order_item_price"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_order_status"("order_id_input" "uuid", "new_status" "public"."order_status") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- thêm logic validate luồng chuyển trạng thái ở đây
  update public.orders set status = new_status where id = order_id_input;
end;
$$;


ALTER FUNCTION "public"."update_order_status"("order_id_input" "uuid", "new_status" "public"."order_status") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_order_total"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.orders
  set total_price = (
    select coalesce(sum(subtotal), 0)
    from public.order_items
    where order_id = coalesce(new.order_id, old.order_id)
  ) + coalesce((select delivery_fee from public.orders where id = coalesce(new.order_id, old.order_id)), 0)
  where id = coalesce(new.order_id, old.order_id);

  return coalesce(new, old);
end;
$$;


ALTER FUNCTION "public"."update_order_total"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "receiver_name" character varying(255),
    "phone" character varying(20),
    "address" "text" NOT NULL,
    "latitude" numeric(10,7),
    "longitude" numeric(10,7),
    "is_default" boolean DEFAULT false
);


ALTER TABLE "public"."addresses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "restaurant_id" "uuid",
    "name" character varying(100) NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."foods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "restaurant_id" "uuid" NOT NULL,
    "category_id" "uuid",
    "name" character varying(255) NOT NULL,
    "description" "text",
    "price" numeric(10,2) NOT NULL,
    "image" "text",
    "available" boolean DEFAULT true,
    "created_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."foods" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "food_id" "uuid" NOT NULL,
    "quantity" integer NOT NULL,
    "price" numeric(10,2) NOT NULL,
    "subtotal" numeric(10,2) NOT NULL,
    CONSTRAINT "order_items_quantity_check" CHECK (("quantity" > 0))
);


ALTER TABLE "public"."order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "restaurant_id" "uuid" NOT NULL,
    "rider_id" "uuid",
    "address_id" "uuid",
    "status" "public"."order_status" DEFAULT 'pending'::"public"."order_status",
    "payment_method" "public"."payment_method" DEFAULT 'cash'::"public"."payment_method",
    "payment_status" "public"."payment_status" DEFAULT 'unpaid'::"public"."payment_status",
    "delivery_fee" numeric(10,2) DEFAULT 0,
    "total_price" numeric(10,2) NOT NULL,
    "note" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" character varying(255),
    "phone" character varying(20),
    "avatar" "text",
    "role" "public"."user_role" DEFAULT 'customer'::"public"."user_role" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "email" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."restaurants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "name" character varying(255) NOT NULL,
    "description" "text",
    "phone" character varying(20),
    "address" "text",
    "image" "text",
    "is_open" boolean DEFAULT true,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "address_id" "uuid"
);


ALTER TABLE "public"."restaurants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "restaurant_id" "uuid" NOT NULL,
    "food_id" "uuid",
    "rating" integer,
    "comment" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    CONSTRAINT "reviews_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."reviews" OWNER TO "postgres";


ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."foods"
    ADD CONSTRAINT "foods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."restaurants"
    ADD CONSTRAINT "restaurants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_foods_restaurant_id" ON "public"."foods" USING "btree" ("restaurant_id");



CREATE INDEX "idx_order_items_order_id" ON "public"."order_items" USING "btree" ("order_id");



CREATE INDEX "idx_orders_customer_id" ON "public"."orders" USING "btree" ("customer_id");



CREATE INDEX "idx_orders_restaurant_id" ON "public"."orders" USING "btree" ("restaurant_id");



CREATE INDEX "idx_orders_rider_id" ON "public"."orders" USING "btree" ("rider_id");



CREATE INDEX "idx_reviews_restaurant_id" ON "public"."reviews" USING "btree" ("restaurant_id");



CREATE OR REPLACE TRIGGER "on_order_item_insert_update" BEFORE INSERT OR UPDATE ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."calculate_subtotal"();



CREATE OR REPLACE TRIGGER "on_order_item_set_price" BEFORE INSERT ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_order_item_price"();



CREATE OR REPLACE TRIGGER "on_order_items_changed" AFTER INSERT OR DELETE OR UPDATE ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."update_order_total"();



CREATE OR REPLACE TRIGGER "on_order_set_delivery_fee" BEFORE INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_delivery_fee"();



CREATE OR REPLACE TRIGGER "on_order_updated" BEFORE UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "on_profile_updated" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."foods"
    ADD CONSTRAINT "foods_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."foods"
    ADD CONSTRAINT "foods_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "public"."foods"("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_address_id_fkey" FOREIGN KEY ("address_id") REFERENCES "public"."addresses"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."restaurants"
    ADD CONSTRAINT "restaurants_address_id_fkey" FOREIGN KEY ("address_id") REFERENCES "public"."addresses"("id");



ALTER TABLE ONLY "public"."restaurants"
    ADD CONSTRAINT "restaurants_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_food_id_fkey" FOREIGN KEY ("food_id") REFERENCES "public"."foods"("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id");



CREATE POLICY "Admins have full access" ON "public"."orders" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'admin'::"public"."user_role")))));



CREATE POLICY "All user can update profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "All user can view profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Anyone can view categories" ON "public"."categories" FOR SELECT USING (true);



CREATE POLICY "Anyone can view foods" ON "public"."foods" FOR SELECT USING (true);



CREATE POLICY "Anyone can view restaurants" ON "public"."restaurants" FOR SELECT USING (true);



CREATE POLICY "Anyone can view reviews" ON "public"."reviews" FOR SELECT USING (true);



CREATE POLICY "Customers can create order items for their order" ON "public"."order_items" FOR INSERT WITH CHECK (("order_id" IN ( SELECT "orders"."id"
   FROM "public"."orders"
  WHERE ("orders"."customer_id" = "auth"."uid"()))));



CREATE POLICY "Customers can create their own order" ON "public"."orders" FOR INSERT WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can create their own review" ON "public"."reviews" FOR INSERT WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can delete their own review" ON "public"."reviews" FOR DELETE USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers can update their own review" ON "public"."reviews" FOR UPDATE USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Owners can create their restaurant" ON "public"."restaurants" FOR INSERT WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can delete their restaurant" ON "public"."restaurants" FOR DELETE USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners can update their restaurant" ON "public"."restaurants" FOR UPDATE USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Related parties can update order" ON "public"."orders" FOR UPDATE USING ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "rider_id") OR ("restaurant_id" IN ( SELECT "restaurants"."id"
   FROM "public"."restaurants"
  WHERE ("restaurants"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Related parties can view order" ON "public"."orders" FOR SELECT USING ((("auth"."uid"() = "customer_id") OR ("auth"."uid"() = "rider_id") OR ("restaurant_id" IN ( SELECT "restaurants"."id"
   FROM "public"."restaurants"
  WHERE ("restaurants"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Related parties can view order items" ON "public"."order_items" FOR SELECT USING (("order_id" IN ( SELECT "orders"."id"
   FROM "public"."orders"
  WHERE (("orders"."customer_id" = "auth"."uid"()) OR ("orders"."rider_id" = "auth"."uid"()) OR ("orders"."restaurant_id" IN ( SELECT "restaurants"."id"
           FROM "public"."restaurants"
          WHERE ("restaurants"."owner_id" = "auth"."uid"())))))));



CREATE POLICY "Restaurant owners manage their categories" ON "public"."categories" USING (("restaurant_id" IN ( SELECT "restaurants"."id"
   FROM "public"."restaurants"
  WHERE ("restaurants"."owner_id" = "auth"."uid"())))) WITH CHECK (("restaurant_id" IN ( SELECT "restaurants"."id"
   FROM "public"."restaurants"
  WHERE ("restaurants"."owner_id" = "auth"."uid"()))));



CREATE POLICY "Restaurant owners manage their foods" ON "public"."foods" USING (("restaurant_id" IN ( SELECT "restaurants"."id"
   FROM "public"."restaurants"
  WHERE ("restaurants"."owner_id" = "auth"."uid"())))) WITH CHECK (("restaurant_id" IN ( SELECT "restaurants"."id"
   FROM "public"."restaurants"
  WHERE ("restaurants"."owner_id" = "auth"."uid"()))));



CREATE POLICY "Users manage their own addresses" ON "public"."addresses" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."addresses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."foods" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."restaurants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reviews" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."calculate_distance_km"("lat1" numeric, "lng1" numeric, "lat2" numeric, "lng2" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_distance_km"("lat1" numeric, "lng1" numeric, "lat2" numeric, "lng2" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_distance_km"("lat1" numeric, "lng1" numeric, "lat2" numeric, "lng2" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_subtotal"() TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_subtotal"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_subtotal"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "postgres";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."earth"() TO "postgres";
GRANT ALL ON FUNCTION "public"."earth"() TO "anon";
GRANT ALL ON FUNCTION "public"."earth"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "postgres";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "postgres";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "anon";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "postgres";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "postgres";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "postgres";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_delivery_fee"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_delivery_fee"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_delivery_fee"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_order_item_price"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_order_item_price"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_order_item_price"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_order_status"("order_id_input" "uuid", "new_status" "public"."order_status") TO "anon";
GRANT ALL ON FUNCTION "public"."update_order_status"("order_id_input" "uuid", "new_status" "public"."order_status") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_order_status"("order_id_input" "uuid", "new_status" "public"."order_status") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_order_total"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_order_total"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_order_total"() TO "service_role";


















GRANT ALL ON TABLE "public"."addresses" TO "anon";
GRANT ALL ON TABLE "public"."addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."addresses" TO "service_role";



GRANT ALL ON TABLE "public"."categories" TO "anon";
GRANT ALL ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON TABLE "public"."foods" TO "anon";
GRANT ALL ON TABLE "public"."foods" TO "authenticated";
GRANT ALL ON TABLE "public"."foods" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."restaurants" TO "anon";
GRANT ALL ON TABLE "public"."restaurants" TO "authenticated";
GRANT ALL ON TABLE "public"."restaurants" TO "service_role";



GRANT ALL ON TABLE "public"."reviews" TO "anon";
GRANT ALL ON TABLE "public"."reviews" TO "authenticated";
GRANT ALL ON TABLE "public"."reviews" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";

CREATE TRIGGER on_auth_user_insert AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_auth_user_updated AFTER UPDATE ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


  create policy "Anyone can view avatars"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = 'avatars'::text));



  create policy "Users can upload their own avatar"
  on "storage"."objects"
  as permissive
  for insert
  to public
with check (((bucket_id = 'avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));



