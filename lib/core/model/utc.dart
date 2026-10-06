/// Returns [t] as a plain UTC [DateTime], truncated to whole milliseconds.
///
/// `TZDateTime.toUtc()` returns another `TZDateTime`, and a `DateTime` never
/// equals a `TZDateTime`, even for the same instant. Every model constructor
/// that stores an instant runs it through this, so equality and map keys work
/// no matter where the value came from. The database stores milliseconds, so
/// dropping sub-millisecond parts keeps a value (and an occurrence key) the
/// same before and after a round trip (decision 25).
DateTime plainUtc(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
