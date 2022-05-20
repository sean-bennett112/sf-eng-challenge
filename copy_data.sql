
begin;

create temporary table users_json(data jsonb);
create temporary table opportunities_json(data jsonb);

\copy users_json from '/postgres_users.json';
\copy opportunities_json from '/postgres_opportunities.json';

insert into api_v1.users
  (id, first_name, last_name, email, interested_in)
select
  u.id,
  u.first_name,
  u.last_name,
  u.email,
  u.interested_in
from users_json, jsonb_populate_record(null::api_v1.users, data) as u;

insert into api_v1.opportunities
  (id, organization, roles, email)
select
  o.id,
  o.organization,
  o.roles,
  o.email
from opportunities_json, jsonb_populate_record(null::api_v1.opportunities, data) as o;

drop table users_json;
drop table opportunities_json;

commit;

