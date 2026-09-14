/// User-created topic derived from post usage.
/// Kept as a simple value type so future merging/canonical topics can plug in.
class Topic {
  final String name;
  final int postCount;

  const Topic({
    required this.name,
    required this.postCount,
  });
}
