/// SkyPort application constants.
///
/// All magic numbers and hard-coded values should be defined here
/// for better maintainability and code readability.
class SkyPortConstants {
  // Prevent instantiation
  SkyPortConstants._();

  // =====================================================
  // Data Buffer Constants
  // =====================================================

  /// Maximum pending bytes before forcing flush (256KB)
  static const int maxPendingBytes = 256 * 1024;

  /// Maximum entries per log chunk
  static const int chunkSizeLimit = 1000;

  // =====================================================
  // UI Scroll Constants
  // =====================================================

  /// Threshold in pixels to determine if scrolled to bottom
  static const int scrollBottomThreshold = 50;

  /// Distance threshold to force jump scroll instead of animation
  static const int forceScrollDistance = 1000;

  /// Scroll animation duration in milliseconds
  static const int scrollAnimationDurationMs = 100;

  // =====================================================
  // History & Cache Constants
  // =====================================================

  /// Maximum number of sent messages to keep in history
  static const int maxHistorySize = 100;

  /// Maximum entries in LRU cache
  static const int lruCacheMaxSize = 500;

  /// Maximum display length for log entries
  static const int logDisplayMaxLength = 5000;

  // =====================================================
  // Timing Constants
  // =====================================================

  /// Default write timeout in milliseconds
  static const int defaultWriteTimeoutMs = 100;

  /// Connection settle delay in milliseconds
  static const int connectionSettleDelayMs = 200;

  /// Port polling interval in milliseconds
  static const int portPollIntervalMs = 500;

  /// Default auto-send interval in milliseconds (1 second)
  static const int defaultAutoSendIntervalMs = 1000;

  // =====================================================
  // UI Dimension Constants
  // =====================================================

  /// Width for interval input field
  static const int intervalInputWidth = 100;

  /// Width for settings popup
  static const int settingsPopupWidth = 300;
}
