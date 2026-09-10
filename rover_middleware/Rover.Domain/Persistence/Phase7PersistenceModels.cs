namespace Rover.Domain.Persistence;

public sealed record DeviceInstallation(Guid DeviceInstallationId, Guid ProfileId, string InstallationId, DateTimeOffset CreatedAtUtc);
public sealed record WalkSessionRecord(Guid WalkSessionRecordId, Guid ProfileId, string WalkSessionId, string Status, DateTimeOffset CreatedAtUtc, DateTimeOffset UpdatedAtUtc, uint Version);
public sealed record WalkStopSnapshot(Guid WalkStopSnapshotId, Guid WalkSessionRecordId, string StopId, int SequenceNumber, string Name, double Latitude, double Longitude, string ContentSnapshotId);
public sealed record WalkContentSnapshot(Guid WalkContentSnapshotId, string Title, string Summary, string Narration, string ContentType, string ContentSource);
public sealed record RouteRevisionRecord(Guid RouteRevisionRecordId, Guid WalkSessionRecordId, int Revision, string Reason, DateTimeOffset AppliedAtUtc);
public sealed record AdaptationProposalRecord(Guid AdaptationProposalRecordId, Guid WalkSessionRecordId, string AdaptationId, string Type, string Status, DateTimeOffset CreatedAtUtc, DateTimeOffset ExpiresAtUtc);
public sealed record AdaptationDecision(Guid AdaptationDecisionId, Guid AdaptationProposalRecordId, string Decision, DateTimeOffset DecidedAtUtc);
public sealed record WalkFeedback(Guid WalkFeedbackId, Guid WalkSessionRecordId, string TargetId, string Value, DateTimeOffset CreatedAtUtc);
public sealed record NarrationProgress(Guid NarrationProgressId, Guid WalkSessionRecordId, string StopId, int SegmentIndex, DateTimeOffset UpdatedAtUtc);
public sealed record ProviderReference(Guid ProviderReferenceId, string Provider, string ExternalId, string ReferenceType, DateTimeOffset CreatedAtUtc);
