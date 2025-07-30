create
extension if not exists "uuid-ossp";

create table public.gear
(
    id           uuid primary key         default uuid_generate_v4(),
    name         text    not null,
    category     text    not null,
    condition    text,
    rental_price numeric not null,
    is_available boolean                  default true,
    created_at   timestamp with time zone default now()
);
