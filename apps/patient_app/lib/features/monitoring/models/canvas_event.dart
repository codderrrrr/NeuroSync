/// One event of a canvas (tracing) recording, exactly as the runner captured
/// it.
///
/// Strokes are explicit rather than inferred from timing: a start opens one, a
/// point extends it and an end closes it. The backend rejects a stream that
/// does not nest like this, because guessing where one movement ended and the
/// next began would change the pass count the recording's quality depends on.
enum CanvasEventType {
  strokeStart('stroke_start'),
  strokePoint('stroke_point'),
  strokeEnd('stroke_end');

  const CanvasEventType(this.wireName);

  /// The event type name the API expects.
  final String wireName;
}

class CanvasEvent {
  const CanvasEvent(this.type, this.offsetMs, this.x, this.y);

  /// Opens a new stroke at this point.
  const CanvasEvent.strokeStart(int offsetMs, double x, double y)
      : this(CanvasEventType.strokeStart, offsetMs, x, y);

  /// Continues the open stroke.
  const CanvasEvent.strokePoint(int offsetMs, double x, double y)
      : this(CanvasEventType.strokePoint, offsetMs, x, y);

  /// Closes the open stroke at this point.
  const CanvasEvent.strokeEnd(int offsetMs, double x, double y)
      : this(CanvasEventType.strokeEnd, offsetMs, x, y);

  final CanvasEventType type;

  /// Milliseconds since the recording started.
  final int offsetMs;

  /// Device-independent logical pixels, the unit every canvas feature is in.
  final double x;
  final double y;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'event_type': type.wireName,
        'offset_ms': offsetMs,
        'payload': <String, dynamic>{'x': x, 'y': y},
      };
}

/// One continuous movement of the finger, from where it went down to where it
/// came up.
class CanvasStroke {
  CanvasStroke();

  final List<CanvasSample> points = <CanvasSample>[];

  bool get isEmpty => points.isEmpty;

  int get length => points.length;
}

class CanvasSample {
  const CanvasSample(this.offsetMs, this.x, this.y);

  final int offsetMs;
  final double x;
  final double y;
}
