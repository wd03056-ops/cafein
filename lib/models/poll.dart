/// Poll option
class PollOption {
  final String id;
  final String text;
  int votes;
  bool selectedByMe;

  PollOption({
    required this.id,
    required this.text,
    this.votes = 0,
    this.selectedByMe = false,
  });

  /// Firestore field alias.
  int get voteCount => votes;

  PollOption copyWith({
    String? id,
    String? text,
    int? votes,
    bool? selectedByMe,
  }) {
    return PollOption(
      id: id ?? this.id,
      text: text ?? this.text,
      votes: votes ?? this.votes,
      selectedByMe: selectedByMe ?? this.selectedByMe,
    );
  }

  factory PollOption.fromMap(Map<String, dynamic> data) {
    final id = (data['id'] as String?)?.trim() ?? '';
    final text = (data['text'] as String?)?.trim() ?? '';
    final count = _asInt(data['voteCount'] ?? data['votes']) ?? 0;
    return PollOption(id: id, text: text, votes: count);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'voteCount': votes,
      };

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Poll attached to a post
class Poll {
  /// Short poll headline shown above the question when set.
  final String? title;
  final String question;
  final List<PollOption> options;
  bool hasVoted;

  Poll({
    this.title,
    required this.question,
    required this.options,
    this.hasVoted = false,
  });

  int get totalVotes => options.fold(0, (sum, o) => o.votes + sum);

  String? get trimmedTitle {
    final t = title?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  Poll copyWith({
    String? title,
    String? question,
    List<PollOption>? options,
    bool? hasVoted,
    bool clearTitle = false,
  }) {
    return Poll(
      title: clearTitle ? null : (title ?? this.title),
      question: question ?? this.question,
      options: options ?? this.options,
      hasVoted: hasVoted ?? this.hasVoted,
    );
  }

  factory Poll.fromMap(Map<String, dynamic> data) {
    final title = (data['title'] as String?)?.trim();
    final question = (data['question'] as String?)?.trim() ?? '';
    final rawOptions = data['options'];
    final options = <PollOption>[];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        if (item is Map<String, dynamic>) {
          final opt = PollOption.fromMap(item);
          if (opt.id.isNotEmpty && opt.text.isNotEmpty) {
            options.add(opt);
          }
        } else if (item is Map) {
          final opt = PollOption.fromMap(Map<String, dynamic>.from(item));
          if (opt.id.isNotEmpty && opt.text.isNotEmpty) {
            options.add(opt);
          }
        }
      }
    }
    return Poll(
      title: title == null || title.isEmpty ? null : title,
      question: question,
      options: options,
    );
  }

  /// Deep copy so callers never share mutable option vote counts.
  Poll clone() {
    return Poll(
      title: title,
      question: question,
      hasVoted: hasVoted,
      options: [
        for (final o in options)
          PollOption(
            id: o.id,
            text: o.text,
            votes: o.votes,
            selectedByMe: o.selectedByMe,
          ),
      ],
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'question': question,
      'options': options.map((o) => o.toMap()).toList(),
    };
    final t = trimmedTitle;
    if (t != null) map['title'] = t;
    return map;
  }

  /// Apply the current user's vote selection without mutating counts.
  Poll withMyVote(String? optionId) {
    if (optionId == null || optionId.isEmpty) {
      return copyWith(
        hasVoted: false,
        options: [
          for (final o in options) o.copyWith(selectedByMe: false),
        ],
      );
    }
    return copyWith(
      hasVoted: true,
      options: [
        for (final o in options)
          o.copyWith(selectedByMe: o.id == optionId),
      ],
    );
  }
}
