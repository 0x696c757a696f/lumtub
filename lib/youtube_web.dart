/// How Lumtub appears to YouTube: as YouTube's own website in Chrome on
/// Windows, the client yt-dlp imitates too. Services other than YouTube are
/// told it is Lumtub.
abstract final class YoutubeWeb {
  static const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';

  /// The website's InnerTube client version, as yt-dlp sends it; a page
  /// Lumtub read gives the current one.
  static const clientVersion = '2.20260708.00.00';

  /// Skips the cookie consent page shown in some regions; no visitor id.
  static const consentCookie = 'CONSENT=YES+cb; SOCS=CAI';

  /// What the website sends with an InnerTube request.
  static Map<String, String> apiHeaders({String? clientVersion, String acceptLanguage = 'en'}) => {
        'User-Agent': userAgent,
        'Accept-Language': acceptLanguage,
        'Content-Type': 'application/json',
        'Origin': 'https://www.youtube.com',
        'X-YouTube-Client-Name': '1',
        'X-YouTube-Client-Version': clientVersion ?? YoutubeWeb.clientVersion,
        'Cookie': consentCookie,
      };
}
