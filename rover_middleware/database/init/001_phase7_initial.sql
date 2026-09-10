CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS guest_profiles (
    profile_id uuid PRIMARY KEY,
    installation_id text NOT NULL UNIQUE,
    created_at_utc timestamptz NOT NULL,
    updated_at_utc timestamptz NOT NULL,
    version integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS device_installations (
    device_installation_id uuid PRIMARY KEY,
    profile_id uuid NOT NULL REFERENCES guest_profiles(profile_id) ON DELETE CASCADE,
    installation_id text NOT NULL UNIQUE,
    created_at_utc timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS user_preferences (
    profile_id uuid PRIMARY KEY REFERENCES guest_profiles(profile_id) ON DELETE CASCADE,
    interests text[] NOT NULL DEFAULT '{}',
    walking_pace text NOT NULL,
    accessibility_needs text[] NOT NULL DEFAULT '{}',
    distance_units text NOT NULL,
    direction_voice_enabled boolean NOT NULL,
    narration_enabled boolean NOT NULL,
    speech_rate double precision NOT NULL,
    preferred_narration_length text NOT NULL,
    save_walk_history boolean NOT NULL,
    improve_recommendations boolean NOT NULL,
    location_retention text NOT NULL
);

CREATE TABLE IF NOT EXISTS walk_sessions (
    walk_session_record_id uuid PRIMARY KEY,
    profile_id uuid REFERENCES guest_profiles(profile_id) ON DELETE SET NULL,
    walk_session_id text NOT NULL UNIQUE,
    status text NOT NULL,
    route_revision integer NOT NULL,
    started_at_utc timestamptz,
    completed_at_utc timestamptz,
    updated_at_utc timestamptz NOT NULL,
    version integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS walk_content_snapshots (
    walk_content_snapshot_id uuid PRIMARY KEY,
    title text NOT NULL,
    summary text NOT NULL,
    narration text NOT NULL,
    content_type text NOT NULL,
    content_source text NOT NULL
);

CREATE TABLE IF NOT EXISTS walk_stop_snapshots (
    walk_stop_snapshot_id uuid PRIMARY KEY,
    walk_session_record_id uuid NOT NULL REFERENCES walk_sessions(walk_session_record_id) ON DELETE CASCADE,
    stop_id text NOT NULL,
    sequence_number integer NOT NULL,
    name text NOT NULL,
    location geography(Point, 4326) NOT NULL,
    content_snapshot_id uuid NOT NULL REFERENCES walk_content_snapshots(walk_content_snapshot_id)
);

CREATE TABLE IF NOT EXISTS route_revisions (
    route_revision_record_id uuid PRIMARY KEY,
    walk_session_record_id uuid NOT NULL REFERENCES walk_sessions(walk_session_record_id) ON DELETE CASCADE,
    revision integer NOT NULL,
    reason text NOT NULL,
    route_geometry geography(LineString, 4326),
    applied_at_utc timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS adaptation_proposals (
    adaptation_proposal_record_id uuid PRIMARY KEY,
    walk_session_record_id uuid NOT NULL REFERENCES walk_sessions(walk_session_record_id) ON DELETE CASCADE,
    adaptation_id text NOT NULL UNIQUE,
    type text NOT NULL,
    status text NOT NULL,
    created_at_utc timestamptz NOT NULL,
    expires_at_utc timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS adaptation_decisions (
    adaptation_decision_id uuid PRIMARY KEY,
    adaptation_proposal_record_id uuid NOT NULL REFERENCES adaptation_proposals(adaptation_proposal_record_id) ON DELETE CASCADE,
    decision text NOT NULL,
    decided_at_utc timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS saved_discoveries (
    saved_discovery_id uuid PRIMARY KEY,
    profile_id uuid NOT NULL REFERENCES guest_profiles(profile_id) ON DELETE CASCADE,
    discovery_id text NOT NULL,
    name text NOT NULL,
    category text NOT NULL,
    source text NOT NULL,
    saved_at_utc timestamptz NOT NULL,
    UNIQUE(profile_id, discovery_id)
);

CREATE TABLE IF NOT EXISTS walk_feedback (
    walk_feedback_id uuid PRIMARY KEY,
    walk_session_record_id uuid NOT NULL REFERENCES walk_sessions(walk_session_record_id) ON DELETE CASCADE,
    target_id text NOT NULL,
    value text NOT NULL,
    created_at_utc timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS preference_signals (
    preference_signal_id uuid PRIMARY KEY,
    profile_id uuid NOT NULL REFERENCES guest_profiles(profile_id) ON DELETE CASCADE,
    topic text NOT NULL,
    weight integer NOT NULL,
    reason text NOT NULL,
    created_at_utc timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS narration_progress (
    narration_progress_id uuid PRIMARY KEY,
    walk_session_record_id uuid NOT NULL REFERENCES walk_sessions(walk_session_record_id) ON DELETE CASCADE,
    stop_id text NOT NULL,
    segment_index integer NOT NULL,
    updated_at_utc timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS provider_references (
    provider_reference_id uuid PRIMARY KEY,
    provider text NOT NULL,
    external_id text NOT NULL,
    reference_type text NOT NULL,
    created_at_utc timestamptz NOT NULL,
    UNIQUE(provider, external_id, reference_type)
);

CREATE INDEX IF NOT EXISTS ix_walk_sessions_profile_status ON walk_sessions(profile_id, status);
CREATE INDEX IF NOT EXISTS ix_walk_sessions_updated ON walk_sessions(updated_at_utc);
CREATE INDEX IF NOT EXISTS ix_route_revisions_session_revision ON route_revisions(walk_session_record_id, revision);
CREATE INDEX IF NOT EXISTS ix_saved_discoveries_profile_saved ON saved_discoveries(profile_id, saved_at_utc);
CREATE INDEX IF NOT EXISTS ix_preference_signals_profile_topic ON preference_signals(profile_id, topic);
CREATE INDEX IF NOT EXISTS ix_walk_stop_snapshots_location ON walk_stop_snapshots USING gist(location);
CREATE INDEX IF NOT EXISTS ix_route_revisions_geometry ON route_revisions USING gist(route_geometry);
