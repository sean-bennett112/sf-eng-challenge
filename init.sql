
create schema api_v1;

create table api_v1.users (
  id bigint primary key,
  first_name text,
  last_name text,
  email text,
  interested_in jsonb
);

create table api_v1.opportunities (
  id bigint primary key,
  organization text,
  email text,
  roles jsonb
);

alter table api_v1.users replica identity full;
alter table api_v1.opportunities replica identity full;

create publication users_source for table api_v1.users;
create publication opportunities_source for table api_v1.opportunities;

create role graphile noinherit login password 'changeme';
create role materialize noinherit login replication password 'seriouslychangeme';

grant usage on schema api_v1 to graphile, materialize;
grant select on table api_v1.users, api_v1.opportunities to materialize;
grant all on table api_v1.users, api_v1.opportunities to graphile;

