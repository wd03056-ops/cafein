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
  final String question;
  final List<PollOption> options;
  bool hasVoted;

  Poll({
    required this.question,
    required this.options,
    this.hasVoted = false,
  });

  int get totalVotes => options.fold(0, (sum, o) => o.votes + sum);

  Poll copyWith({
    String? question,
    List<PollOption>? options,
    bool? hasVoted,
  }) {
    return Poll(
      question: question ?? this.question,
      options: options ?? this.options,
      hasVoted: hasVoted ?? this.hasVoted,
    );
  }

  factory Poll.fromMap(Map<String, dynamic> data) {
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
    return Poll(question: question, options: options);
  }

  Map<String, dynamic> toMap() => {
        'question': question,
        'options': options.map((o) => o.toMap()).toList(),
      };

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
