/// SkyPort application constants.
///
/// All magic numbers and hard-coded values should be defined here
/// for better maintainability and code readability.
class SkyPortConstants {
  // Prevent instantiation
  SkyPortConstants._();

  /// Threshold in pixels to determine if scrolled to bottom
  static const int scrollBottomThreshold = 50;

  /// Maximum entries in LRU cache
  static const int lruCacheMaxSize = 500;

  /// Maximum display length for log entries
  static const int logDisplayMaxLength = 5000;

  /// Width for interval input field
  static const int intervalInputWidth = 100;
}
