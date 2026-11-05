import 'dart:io';
import 'dart:math';

import 'sun_zones.dart';

/// Sunrise and sunset where the computer's time zone puts it: the zone's
/// main city, found offline from the zone's name. Nothing is looked up on
/// the network and no location is read.
class SunTimes {
  SunTimes._(this.latitude, this.longitude, this.zone);

  final double latitude;
  final double longitude;
  /// The IANA zone the place came from, none when only the UTC offset was known.
  final String? zone;

  static SunTimes? _here;

  /// The place for this computer's time zone, read once.
  static SunTimes get here => _here ??= _find();

  /// For tests.
  static SunTimes at(double latitude, double longitude) => SunTimes._(latitude, longitude, null);

  static SunTimes _find() {
    final zone = _ianaZone();
    final place = zone == null ? null : zoneCoordinates[zone];
    if (place != null) return SunTimes._(place.$1, place.$2, zone);
    // Only the offset: the zone's middle meridian, at a latitude most
    // people live near.
    final offset = DateTime.now().timeZoneOffset.inMinutes / 60;
    return SunTimes._(35, offset * 15, null);
  }

  static String? _ianaZone() {
    try {
      final tz = Platform.environment['TZ'];
      if (tz != null && zoneCoordinates.containsKey(tz)) return tz;
      if (Platform.isWindows) {
        final result = Process.runSync('reg', ['query', r'HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation', '/v', 'TimeZoneKeyName']);
        final name = RegExp(r'TimeZoneKeyName\s+REG_SZ\s+(.+)').firstMatch('${result.stdout}')?.group(1)?.trim();
        return name == null ? null : windowsZones[name];
      }
      final file = File('/etc/timezone');
      if (file.existsSync()) {
        final name = file.readAsStringSync().trim();
        if (zoneCoordinates.containsKey(name)) return name;
      }
      final target = Link('/etc/localtime').targetSync();
      final at = target.indexOf('zoneinfo/');
      return at < 0 ? null : target.substring(at + 'zoneinfo/'.length);
    } catch (_) {
      return null;
    }
  }

  /// Today's sunrise and sunset in local time, or none when the sun stays
  /// up or down all day; then [polarNight] says which.
  (DateTime, DateTime)? on(DateTime day) {
    final rad = pi / 180;
    final noon = DateTime.utc(day.year, day.month, day.day, 12);
    final julian = noon.millisecondsSinceEpoch / 86400000 + 2440587.5;
    final n = (julian - 2451545.0 + 0.0008).roundToDouble();
    final meanNoon = n - longitude / 360;
    final anomaly = (357.5291 + 0.98560028 * meanNoon) % 360;
    final centre = 1.9148 * sin(anomaly * rad) + 0.02 * sin(2 * anomaly * rad) + 0.0003 * sin(3 * anomaly * rad);
    final ecliptic = (anomaly + centre + 180 + 102.9372) % 360;
    final transit = 2451545.0 + meanNoon + 0.0053 * sin(anomaly * rad) - 0.0069 * sin(2 * ecliptic * rad);
    final declination = asin(sin(ecliptic * rad) * sin(23.4397 * rad));
    final cosHour = (sin(-0.833 * rad) - sin(latitude * rad) * sin(declination)) / (cos(latitude * rad) * cos(declination));
    if (cosHour.abs() > 1) return null;
    final hour = acos(cosHour) / rad / 360;
    DateTime local(double j) => DateTime.fromMillisecondsSinceEpoch(((j - 2440587.5) * 86400000).round(), isUtc: true).toLocal();
    return (local(transit - hour), local(transit + hour));
  }

  /// Whether the sun stays down all of [day].
  bool polarNight(DateTime day) {
    final month = day.month;
    final winter = latitude >= 0 ? (month >= 10 || month <= 2) : (month >= 4 && month <= 8);
    return on(day) == null && winter;
  }

  /// Whether it is night at [now]: before sunrise or from sunset on.
  bool isNight(DateTime now) {
    final times = on(now);
    if (times == null) return polarNight(now);
    return now.isBefore(times.$1) || !now.isBefore(times.$2);
  }
}

/// Whether [now] falls between [start] and [end] o'clock, through midnight
/// when [end] is earlier.
bool inHours(DateTime now, int start, int end) {
  if (start == end) return true;
  return start < end ? now.hour >= start && now.hour < end : now.hour >= start || now.hour < end;
}
