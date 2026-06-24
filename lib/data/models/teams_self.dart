/// The signed-in user's own identity (`teams_got_self_details`).
class TeamsSelf {
  /// `skypeName` — the account's own mri-less id (e.g. `live:.cid.xxxx`).
  final String username;

  /// Friendly display name from `userDetails.name` (falls back to upn).
  final String displayName;

  /// `primaryMemberName` — an alternate self id used by `teams_is_user_self`.
  final String? primaryMemberName;

  const TeamsSelf({
    required this.username,
    required this.displayName,
    this.primaryMemberName,
  });

  /// Mirrors `teams_is_user_self`: matches either the skype name or the
  /// primary member name (both compared with and without an `8:`-style prefix
  /// already stripped by the caller).
  bool isSelf(String? candidate) {
    if (candidate == null || candidate.isEmpty) return false;
    if (candidate == username) return true;
    if (primaryMemberName != null && candidate == primaryMemberName) {
      return true;
    }
    return false;
  }
}
