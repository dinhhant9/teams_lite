/// Pure helper functions ported from `teams_util.c`.
library;

class TeamsUtil {
  TeamsUtil._();

  /// JS-style epoch milliseconds (`teams_get_js_time`).
  static int jsTime() => DateTime.now().millisecondsSinceEpoch;

  /// `teams_strip_user_prefix` — drop a leading `N:` prefix (except `2:`).
  ///
  /// e.g. `8:orgid:abc` → `orgid:abc`, `8:live:.cid.x` → `live:.cid.x`.
  static String stripUserPrefix(String who) {
    if (who.length >= 2 && who[1] == ':' && who[0] != '2') {
      return who.substring(2);
    }
    return who;
  }

  /// `teams_contact_url_to_name` — extract the contact id from a user url like
  /// `https://.../v1/users/ME/contacts/8:orgid:abc` → `orgid:abc`.
  ///
  /// `8:`, `1:`, `4:` prefixes are stripped; `2:`, `28:`, `48:` are kept.
  static String? contactUrlToName(String? url) {
    if (url == null) return null;

    int? start;
    // Strip the numeric prefix off these ones (skip the "N" but keep "...")
    for (final p in const ['/8:', '/1:', '/4:']) {
      final idx = url.lastIndexOf(p);
      if (idx != -1) {
        start = idx + 2; // points at the char after "N", i.e. ":..."→ skip ':'
        break;
      }
    }
    if (start != null) {
      // start currently points at ':' of "8:"; advance past it.
      start += 1;
    }

    // Keep the prefix on these ones
    if (start == null) {
      for (final p in const ['/2:', '/28:', '/48:']) {
        final idx = url.lastIndexOf(p);
        if (idx != -1) {
          start = idx + 1; // keep the prefix, drop the leading '/'
          break;
        }
      }
    }
    if (start == null) return null;

    final tail = url.substring(start);
    final slash = tail.indexOf('/');
    return slash == -1 ? tail : tail.substring(0, slash);
  }

  /// `teams_thread_url_to_name` — extract a `19:...` thread id from a url.
  static String? threadUrlToName(String? url) {
    if (url == null) return null;
    final idx = url.lastIndexOf('/19:');
    if (idx == -1) return null;
    final tail = url.substring(idx + 1);
    final slash = tail.indexOf('/');
    return slash == -1 ? tail : tail.substring(0, slash);
  }

  /// Build the conversation id used when messaging a personal contact directly
  /// without a thread (`teams_send_im`, personal branch: `8:` + who).
  static String directConversationId(String who) =>
      who.contains(':') ? who : '8:$who';
}
