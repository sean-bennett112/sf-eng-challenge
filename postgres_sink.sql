
create extension "postgres_fdw";

create server materialize
  foreign data wrapper postgres_fdw
  options (
    host 'materialize',
    dbname 'materialize',
    port '6875'
  );

create user mapping
  for postgres
  server materialize
  options (user 'materialize');
create user mapping
  for graphile
  server materialize
  options (
    user 'materialize',
    password_required 'false'
  );

create schema materialize;

create foreign table materialize.computed_matches (
  user_id bigint,
  opportunity_id bigint,
  matched_role text
)
server materialize
options ( schema_name 'public', table_name 'matches' );

-- Need this to get rid of the extraneous quotes from the jsonb output
create view api_v1.matches as (
  select
    user_id,
    opportunity_id,
    trim(both '"' from matched_role) as matched_role
  from materialize.computed_matches
);
comment on view api_v1.matches is '@omit insert,update,delete';

grant select on table materialize.computed_matches to graphile;
grant select on table api_v1.matches to graphile;

