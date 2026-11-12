import 'l10n/l10n.dart';

/// Why a video is on the home feed, in a word or two for its card; the
/// full reason shows when the pointer rests on it.
enum ReasonKind {
  following('Following'),
  justPosted('Just posted'),
  oftenWatched('Often watched'),
  related('Related'),
  similar('Similar'),
  nextUp('Next up'),
  searched('Searched'),
  explore('Explore'),
  popular('Popular'),
  youtube('Recommended');

  const ReasonKind(this._label);
  final String _label;
  String get label => tr(_label);
}

/// A reason as the feed keeps it: its kind and its full text in one string,
/// so reasons saved before kinds existed still read as text.
abstract final class FeedReason {
  static const _mark = '\u001f';

  static String of(ReasonKind kind, String text) => '${kind.name}$_mark$text';

  static (ReasonKind?, String) read(String reason) {
    final at = reason.indexOf(_mark);
    if (at < 0) return (null, reason);
    final kind = ReasonKind.values.where((k) => k.name == reason.substring(0, at)).firstOrNull;
    return (kind, reason.substring(at + 1));
  }
}
