/// Writing systems that do not put spaces between words: Chinese,
/// Japanese, Korean (whose words are spaced but whose syllables join
/// without one when a line runs on), Thai, Lao, Khmer, Burmese and
/// Tibetan. Lines of them join without a space and break between
/// letters, not only at spaces.
final unspacedScript = RegExp(r'[฀-໿ༀ-࿿က-႟ក-៿᧠-᧿぀-ヿㇰ-ㇿ㐀-鿿ꩠ-ꩿ가-힯豈-﫿]');

/// A letter outside the Latin alphabet.
final nonLatinLetter = RegExp(r'(?!\p{Script=Latin})\p{L}', unicode: true);
