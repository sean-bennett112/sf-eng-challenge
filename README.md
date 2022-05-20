# Initial Data Inspection

First, download both files locally:

```bash
curl https://raw.githubusercontent.com/schmidtfutures/sf-eng-challenge/main/opportunities.json > opportunities.json
curl https://raw.githubusercontent.com/schmidtfutures/sf-eng-challenge/main/users.json > users.json
```

Now we'll do some basic analysis using [Nushell](https://www.nushell.sh).

First let's check the overall count, as well as some simple other counts. Basically, I want a sanity check of how clean this data source is.

```
# 1000 records in each file
nu> open ./users.json | length
1000
nu> open ./opportunities.json | length
1000

# `id` is actually unique
nu> open ./users.json | select id | uniq | length
1000
nu> open ./opportunities.json | select id | uniq | length
1000

# Sanity check of duplicate records based on `email`, as well as verification that `email` is
# unique when non-null.
nu> open ./users.json | where email == "" | length
153
nu> open ./users.json | where email == "" | uniq | length
153
nu> open ./users.json | where email != "" | length
847
nu> open ./users.json | where email != "" | uniq | length
847

# Checking if we have any potential duplicates where information is missing. For example, where
# we have duplicate `last_name` but one or more empty `first_name` field, or vice versa. Looks
# like we don't in the current dataset.
nu> open ./users.json | where email == "" && first_name == "" | length
0
nu> open ./users.json | where email == "" && last_name == "" | length
8
nu> open ./users.json | where email == "" && last_name == ""
───┬─────┬────────────┬───────────┬───────┬────────────────
 # │ id  │ first_name │ last_name │ email │ interested_in
───┼─────┼────────────┼───────────┼───────┼────────────────
 0 │ 22  │ Margaux    │           │       │ [table 3 rows]
 1 │ 328 │ Beverie    │           │       │ [table 0 rows]
 2 │ 330 │ Erma       │           │       │ [table 0 rows]
 3 │ 369 │ Ailina     │           │       │
 4 │ 548 │ Neall      │           │       │
 5 │ 555 │ Leah       │           │       │ [table 3 rows]
 6 │ 644 │ Atlanta    │           │       │ [table 0 rows]
 7 │ 997 │ Lazarus    │           │       │ [table 2 rows]
───┴─────┴────────────┴───────────┴───────┴────────────────

# `opportunities.json` looks to be a bit simpler.
nu> open ./opportunities.json | where organization == "" | length
0
nu> open ./opportunities.json | where organization != "" | length
1000
nu> open ./opportunities.json | where organization != "" | uniq | length
1000
nu> open ./opportunities.json | where email == "" | length
51
nu> open ./opportunities.json | where email != "" | select email | length
949
nu> open ./opportunities.json | where email != "" | select email | uniq | length
949
```

So the data source actually looks relatively clean. That being said, I've found it's generally a bad idea to trust this to be the case, or to trust ID fields from outside sources. I'll probably end up doing that in this case purely for expediency, but it's generally not a great idea.

Often, the `email` field is a better source of uniqueness, if for no other reason then because it's quite frequently the username for the application in question. That is, whatever application you're getting the data from. While this isn't universally true, it's often a reasonable place to start.

Now let's take a look at how many roles/interests we're dealing with.

```
nu> open ./users.json | get interested_in | uniq | length
189
nu> open ./opportunities.json | get roles | uniq | length
194
```

Ok so not too many. And just taking a brief glances over them, it sure _looks_ like they're all in the same roughly standardized form. Also, it appears that all of the entries in `interested_in` are actual roles, as opposed to, say, broad fields they'd like to work in. However, in a realistic version of this, I'd find it very likely that users would enter in whole fields they'd like to work in here, particularly if it's based on some sort of free-form entry.

You can get around this by having users enter information in some other way based on the role/field data you actually have, but, given that I don't know where this information came from, I can't strictly assume that here.

For now, I'm going to assume the `interested_in` and `roles` entries match, since I don't believe that doing the data cleaning or a more advanced matching algorithm is the point of this exercise.

# Brief Architectural Overview

I've decided to use a combination of [Postgres](https://www.postgresql.org), [Materialize](https://materialize.com), and [Postgraphile](https://www.graphile.org) for this. The main reasons for this are:

- I'm pretty comfortable with both Postgres and Postgraphile
- I've never used Materialize before and I really want to, and this was a good excuse

The basic idea is that we'll have a schema for our api, called `api_v1`, and any tables/views/functions in there will be automatically considered part of our GraphQL schema. We'll start with two tables, `users` and `opportunities`, that mirror the structure of the `users.json` and `opportunities.json` files. That is, we're just loading in the raw data from our data files in an ELT, rather then ETL, fashion.

From there, we'll tell:

- Postgres to expose those tables as a [Publication]() so that Materialize will be able to see them
- Materialize to create a [Source]() from our Postgres instance so it knows about those tables.

Then we'll perform some basic joining on those views to get a table of `user_id` to `opportunity_id` matches. Our actual matching will be _incredibly simple_, performing a case-insensitive comparison between the roles and interests of the given opportunity and user, respectively.

After that, we'll need to connect those match results back to Postgres, since anything we want to expose in our API via Postgraphile has to first be in the `api_v1` schema of Postgres. We do that via the [`postgres_fdw`]() [Foreign Data Wrapper](). This works because Materialize is wire-compatible with Postgres. So, at least according to Postgres, it's just another postgres instance.

Finally, we wrap those results in another Postgres view to clean up some weird text-formatting from when converting the `jsonb` to `text`. Basically, `jsonb->text` conversion fails to remove wrapping quotes from the text, resulting in values like `\"Software Engineer\"`, which we don't want. Postgres has a nice way of easily cleaning that up, but it appears that Materialize doesn't.

Once that view `api_v1.matches` is created, Postgraphile will pick it up, and you'll be able to see it from `localhost:5433/graphiql`.

Note that, because Materialize is a streaming platform for incremental view maintenance, any changes to the values in `api_v1.users` or `api_v1.opportunities` will be propagated through the Materialize DAG and be visible in the `api_v1.matches` view/API.
