create table if not exists user_accounts (
    account_id uuid primary key,
    status text not null,
    created_at_utc timestamptz not null,
    updated_at_utc timestamptz not null,
    version bigint not null default 0
);

create table if not exists external_identities (
    external_identity_id uuid primary key,
    account_id uuid not null references user_accounts(account_id) on delete cascade,
    provider text not null,
    subject text not null,
    verified_email text null,
    created_at_utc timestamptz not null,
    updated_at_utc timestamptz not null,
    unique(provider, subject)
);

create table if not exists guest_profile_links (
    guest_profile_link_id uuid primary key,
    account_id uuid not null references user_accounts(account_id) on delete cascade,
    profile_id uuid not null references guest_profiles(profile_id) on delete cascade,
    linked_at_utc timestamptz not null,
    unique(profile_id)
);

create table if not exists device_registrations (
    device_registration_id uuid primary key,
    account_id uuid not null references user_accounts(account_id) on delete cascade,
    installation_id text not null,
    created_at_utc timestamptz not null,
    last_seen_at_utc timestamptz not null,
    unique(account_id, installation_id)
);

create table if not exists account_deletion_requests (
    account_deletion_request_id uuid primary key,
    account_id uuid not null,
    requested_at_utc timestamptz not null,
    status text not null
);

create table if not exists security_audit_events (
    security_audit_event_id uuid primary key,
    account_id uuid null,
    event_type text not null,
    outcome text not null,
    occurred_at_utc timestamptz not null,
    subject_hash text null,
    correlation_id text null
);

create index if not exists ix_external_identities_account_id on external_identities(account_id);
create index if not exists ix_guest_profile_links_account_id on guest_profile_links(account_id);
create index if not exists ix_guest_profile_links_profile_id on guest_profile_links(profile_id);
create index if not exists ix_device_registrations_account_id on device_registrations(account_id);
create index if not exists ix_security_audit_events_account_id on security_audit_events(account_id);
create index if not exists ix_security_audit_events_event_type_occurred on security_audit_events(event_type, occurred_at_utc);
