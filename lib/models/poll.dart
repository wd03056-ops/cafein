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

  int get totalVotes => options.fold(0, (sum, o) => sum + o.votes);

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
}
