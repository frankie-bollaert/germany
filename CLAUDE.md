# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org): each commit
subject is `<type>[optional scope]: <description>` (e.g. `feat(jobs): add
tif-to-cog job kind`, `fix: bound the swap wait for ACCESS EXCLUSIVE locks`).
Common types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`,
`ci`, `build`. Breaking changes use `!` before the colon or a
`BREAKING CHANGE:` footer.

The end goal is to populate the following tables from the alkis data. The tables go in a duckdb database.

Plots
create table plots
(
    id              uuid      default gen_random_uuid() not null
    primary key,
    local_id        text                                not null,
    local_id_region text                                not null,
    region          text                                not null,
    geometry        geometry(Polygon, 4326)             not null,
    area            double precision                    not null,
    metadata        jsonb                               not null,
    valid_from      date                                not null,
    valid_to        date,
    created_at      timestamp default now()             not null,
    updated_at      timestamp default now()             not null,
    constraint plots_local_id_local_id_region_unique
    unique (local_id, local_id_region)
);

create table structures (
    tableoid oid not null,
    cmax cid not null,
    xmax xid not null,
    cmin cid not null,
    xmin xid not null,
    ctid tid not null,
    id uuid primary key not null default gen_random_uuid(),
    local_id text not null,
    local_id_region text not null,
    created_at timestamp without time zone not null default now(),
    updated_at timestamp without time zone not null default now()
);

create table structure_versions
(
    id           uuid      default gen_random_uuid() not null
    constraint structures_pkey
    primary key,
    geometry     geometry(Polygon, 4326)             not null,
    type         text                                not null,
    valid_from   date                                not null,
    valid_to     date,
    created_at   timestamp default now()             not null,
    updated_at   timestamp default now()             not null,
    structure_id uuid                                not null
    constraint structure_versions_structure_id_structures_id_fk
    references public.structures
);



