/// The aspect ratio to show a video in: the [forced] one, else the video's
/// own from its displayed [width] and [height] (already rotated), else 16:9
/// until the size is known.
double videoAspectFor(double? forced, int? width, int? height) {
  if (forced != null) return forced;
  if (width != null && height != null && width > 0 && height > 0) return width / height;
  return 16 / 9;
}
