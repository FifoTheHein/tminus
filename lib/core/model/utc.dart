/// Returns [t] as a plain UTC [DateTime].
///
/// `TZDateTime.toUtc()` returns another `TZDateTime`, and a `DateTime` never
/// equals a `TZDateTime`, even for the same instant. Every model constructor
/// that stores an instant runs it through this, so equality and map keys work
/// no matter where the value came from.
DateTime plainUtc(DateTime t) =>
    DateTime.fromMicrosecondsSinceEpoch(t.microsecondsSinceEpoch, isUtc: true);
