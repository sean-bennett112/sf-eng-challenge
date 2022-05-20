
create source users_source
  from postgres connection 'host=postgres port=5432 user=materialize dbname=postgres'
  publication 'users_source';
create source opportunities_source
  from postgres connection 'host=postgres port=5432 user=materialize dbname=postgres'
  publication 'opportunities_source';

create materialized views
  from source users_source (api_v1.users as users);
create materialized views
  from source opportunities_source (api_v1.opportunities as opportunities);

create view flattened_user_interests as (
  select
    id as user_id,
    interested
  from users, jsonb_array_elements(interested_in) as interested
);

create view flattened_opportunity_roles as (
  select
    id as opportunity_id,
    role
  from opportunities, jsonb_array_elements(roles) as role
);

create materialized view matches as (
  select
    user_id,
    opportunity_id,
    role::text as matched_role
  from flattened_user_interests as u
  join flattened_opportunity_roles as o
    on lower(interested::text) = lower(role::text)
  order by user_id, opportunity_id
);

