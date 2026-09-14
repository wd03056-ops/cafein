import '../models/comment.dart';
import '../models/poll.dart';
import '../models/post.dart';

/// Temporary mock data before backend (cafe staff experiences)
List<Post> createMockPosts() {
  final now = DateTime.now();

  Comment c(
    String id,
    String postId,
    String content,
    Duration ago, {
    int likes = 3,
  }) {
    return Comment(
      id: id,
      postId: postId,
      content: content,
      createdAt: now.subtract(ago),
      likeCount: likes,
    );
  }

  return [
    // ── 마감 / 마감 업무 ──
    Post(
      id: '1',
      content:
          '다른 카페는 마감 몇 분 전에 시작해요?\n우리 매장은 손님 없어도 닫기 30분 전부터 청소하래서 좀 이른 것 같음…',
      createdAt: now.subtract(const Duration(hours: 2)),
      likeCount: 132,
      tags: ['마감'],
      poll: Poll(
        question: '다른 카페는 마감 몇 분 전에 시작해요?',
        options: [
          PollOption(id: '1a', text: '10분 전', votes: 12),
          PollOption(id: '1b', text: '20분 전', votes: 28),
          PollOption(id: '1c', text: '30분 전', votes: 45),
          PollOption(id: '1d', text: '1시간 전', votes: 19),
        ],
      ),
      comments: [
        c('c1-1', '1', '저희는 마감 20분 전이요. 손님 있으면 그냥 열고 청소는 그 후에 해요.',
            const Duration(hours: 1, minutes: 40),
            likes: 8),
        c('c1-2', '1', '프랜차이즈는 30분 전이 거의 고정이더라고요.',
            const Duration(hours: 1),
            likes: 5),
      ],
    ),
    Post(
      id: '2',
      content:
          '마감 업무가 너무 많은데 원래 이런가요?\n머신 세척, 바닥, 쓰레기, 재고까지… 혼자 하면 한 시간 넘게 걸림',
      createdAt: now.subtract(const Duration(hours: 5)),
      likeCount: 164,
      tags: ['마감 업무'],
      comments: [
        c('c2-1', '2', '혼자면 진짜 많아요. 저희도 한 명일 때만 상상 이상으로 남아요.',
            const Duration(hours: 4),
            likes: 14),
        c('c2-2', '2', '체크리스트 만들어달라고 하세요. 없으면 끝도 없어요.',
            const Duration(hours: 3),
            likes: 9),
      ],
    ),
    Post(
      id: '3',
      content: '마감하고 나왔는데 사장님이 “내일 오픈 때 우유 채워놔” 카톡 옴.\n이미 집인데… 이런 거 정상인가요?',
      createdAt: now.subtract(const Duration(hours: 9)),
      likeCount: 88,
      tags: ['마감'],
      comments: [
        c('c3-1', '3', '그건 근무시간 밖 업무 지시예요. 선을 그어야 해요.',
            const Duration(hours: 8),
            likes: 21),
      ],
    ),
    Post(
      id: '4',
      content: '주말 마감이 유독 힘듦.\n손님은 많은데 인원은 평일 그대로라 항상 늦게 끝남',
      createdAt: now.subtract(const Duration(days: 1, hours: 2)),
      likeCount: 73,
      tags: ['마감'],
    ),

    // ── 진상 / 진상손님 ──
    Post(
      id: '5',
      content:
          '손님이 아이스 아메리카노 다 마시더니\n처음 시켰고 환불해달라고 ㅋㅋ?\n매니저님이 그냥 환불해주시던데…',
      createdAt: now.subtract(const Duration(hours: 8)),
      likeCount: 187,
      tags: ['진상'],
      comments: [
        c('c5-1', '5', '그거 거의 사기급 진상인데 진짜 환불해줬어요?',
            const Duration(hours: 7),
            likes: 22),
        c('c5-2', '5', '다 마신 후에 환불은 말도 안 됨… 공감합니다',
            const Duration(hours: 6),
            likes: 31),
        c('c5-3', '5', '저희는 CCTV 보고 거절했어요.',
            const Duration(hours: 5),
            likes: 17),
      ],
    ),
    Post(
      id: '6',
      content: '진상손님한테 “알바 주제에” 소리 들음.\n참느라 입술 깨물었음. 다들 어떻게 넘기세요?',
      createdAt: now.subtract(const Duration(hours: 14)),
      likeCount: 221,
      tags: ['진상손님'],
      poll: Poll(
        question: '진상 응대, 보통 어떻게 하세요?',
        options: [
          PollOption(id: '6a', text: '그냥 참고 넘김', votes: 58),
          PollOption(id: '6b', text: '매니저/사장 호출', votes: 72),
          PollOption(id: '6c', text: '단호하게 거절', votes: 41),
          PollOption(id: '6d', text: '매장마다 다름', votes: 33),
        ],
      ),
      comments: [
        c('c6-1', '6', '인신공격은 바로 매니저 부르는 게 맞아요.',
            const Duration(hours: 12),
            likes: 45),
      ],
    ),
    Post(
      id: '7',
      content: '테이크아웃인데 매장 좌석 차지하고 노트북 3시간…\n눈치 주기도 애매하고 진짜 난감함',
      createdAt: now.subtract(const Duration(days: 1, hours: 5)),
      likeCount: 96,
      tags: ['진상'],
    ),
    Post(
      id: '8',
      content: '커스텀 주문 엄청 복잡하게 시키고 나서\n“이거 왜 이렇게 오래 걸려요?” 하는 손님…',
      createdAt: now.subtract(const Duration(days: 2)),
      likeCount: 54,
      tags: ['진상손님'],
      comments: [
        c('c8-1', '8', '레시피 카드 보여드리라고 하세요 ㅋㅋ',
            const Duration(days: 1, hours: 20),
            likes: 12),
      ],
    ),

    // ── 급여 / 급여 문제 / 주휴수당 ──
    Post(
      id: '9',
      content:
          '급여 인상 얘기 꺼냈더니 사장님이\n요즘엔 손님 없다만 반복하심.\n그래도 최저임금은 맞춰줘야 하는 거 맞죠?',
      createdAt: now.subtract(const Duration(days: 1, hours: 3)),
      likeCount: 195,
      tags: ['급여'],
      comments: [
        c('c9-1', '9', '네 최저임금은 법이에요. 손님 수는 별개입니다…',
            const Duration(days: 1, hours: 1),
            likes: 40),
        c('c9-2', '9', '근로계약서랑 급여명세서 꼭 남겨두세요.',
            const Duration(hours: 20),
            likes: 28),
      ],
    ),
    Post(
      id: '10',
      content: '급여 문제인데… 이번 달 시급이 갑자기 깎여서 나옴.\n사장님은 “실수”라는데 내달에도 그럴까 불안',
      createdAt: now.subtract(const Duration(days: 1, hours: 8)),
      likeCount: 143,
      tags: ['급여 문제'],
      comments: [
        c('c10-1', '10', '문자/카톡으로 확인 받아두세요. 증거 남기는 게 중요해요.',
            const Duration(days: 1, hours: 6),
            likes: 33),
      ],
    ),
    Post(
      id: '11',
      content:
          '주휴수당 제대로 받는 곳 많나요?\n저는 알바인데 주 15시간 넘게 일해도 주휴가 안 찍혀요.',
      createdAt: now.subtract(const Duration(days: 1)),
      likeCount: 212,
      tags: ['주휴수당'],
      poll: Poll(
        question: '지금 카페에서 주휴수당 받고 있나요?',
        options: [
          PollOption(id: '11a', text: '제대로 받음', votes: 41),
          PollOption(id: '11b', text: '일부만 / 애매함', votes: 67),
          PollOption(id: '11c', text: '아예 안 받음', votes: 89),
          PollOption(id: '11d', text: '잘 모르겠음', votes: 23),
        ],
      ),
      comments: [
        c('c11-1', '11', '저도 이제 받았어요. 근로계약서 다시 확인해보세요.',
            const Duration(hours: 20),
            likes: 18),
      ],
    ),
    Post(
      id: '12',
      content: '급여일에 항상 이틀씩 늦음.\n“입금 처리 중”만 반복인데 다들 참으세요?',
      createdAt: now.subtract(const Duration(days: 2, hours: 4)),
      likeCount: 118,
      tags: ['급여'],
    ),
    Post(
      id: '13',
      content: '주휴수당을 “보너스”라고 부르는 사장님…\n법적으로 당연히 줘야 하는 건데 말이죠',
      createdAt: now.subtract(const Duration(days: 3)),
      likeCount: 167,
      tags: ['주휴수당'],
      comments: [
        c('c13-1', '13', '고용노동부 상담 한번 해보세요. 익명도 됩니다.',
            const Duration(days: 2, hours: 18),
            likes: 52),
      ],
    ),
    Post(
      id: '14',
      content: '야간수당 안 주고 “시급에 포함”이라고만 함.\n22시 넘어서 일하는데 이게 맞나요?',
      createdAt: now.subtract(const Duration(days: 3, hours: 6)),
      likeCount: 154,
      tags: ['급여 문제'],
    ),

    // ── 근무시간 / 근무 시간 ──
    Post(
      id: '15',
      content: '새벽 2시에 사장님이 “내일 일찍 나와” 카톡.\n근무시간 아닌데 연락오면 답해야 하나요?',
      createdAt: now.subtract(const Duration(hours: 6)),
      likeCount: 91,
      tags: ['근무시간'],
      comments: [
        c('c15-1', '15', '근무 외 연락은 안 받는 게 정신건강에 좋아요…',
            const Duration(hours: 5),
            likes: 19),
      ],
    ),
    Post(
      id: '16',
      content: '스케줄표에 없는 날 갑자기 호출.\n“사람 없대서”인데 거절하면 눈치 주심',
      createdAt: now.subtract(const Duration(days: 1, hours: 10)),
      likeCount: 128,
      tags: ['근무 시간'],
      poll: Poll(
        question: '갑작스러운 호출, 거절해 본 적 있나요?',
        options: [
          PollOption(id: '16a', text: '자주 거절함', votes: 29),
          PollOption(id: '16b', text: '가끔만', votes: 61),
          PollOption(id: '16c', text: '거의 못 거절함', votes: 88),
        ],
      ),
    ),
    Post(
      id: '17',
      content: '오픈 알바인데 출근 30분 전에 나와서 준비하래.\n그 시간은 근무로 안 친대요…',
      createdAt: now.subtract(const Duration(days: 2, hours: 8)),
      likeCount: 176,
      tags: ['근무시간'],
      comments: [
        c('c17-1', '17', '준비 시간도 근로시간입니다. 기록 남기세요.',
            const Duration(days: 2, hours: 4),
            likes: 61),
      ],
    ),
    Post(
      id: '18',
      content: '피크 타임만 몰아서 스케줄 짜주심.\n쉬는 날 없이 주말+저녁만… 체력이 안 됨',
      createdAt: now.subtract(const Duration(days: 4)),
      likeCount: 82,
      tags: ['근무 시간'],
    ),

    // ── 휴게시간 / 휴게 ──
    Post(
      id: '19',
      content: '4시간 근무인데 휴게시간 없음.\n화장실도 눈치 보이면서 감… 다른 매장은 어때요?',
      createdAt: now.subtract(const Duration(days: 1, hours: 14)),
      likeCount: 139,
      tags: ['휴게시간'],
      comments: [
        c('c19-1', '19', '4시간이면 최소 휴게가 있어야 정상이에요.',
            const Duration(days: 1, hours: 10),
            likes: 27),
      ],
    ),
    Post(
      id: '20',
      content: '휴게 시간에 손님 오면 바로 튀어나오라고 함.\n그게 휴게인가요…',
      createdAt: now.subtract(const Duration(days: 2, hours: 12)),
      likeCount: 201,
      tags: ['휴게'],
      poll: Poll(
        question: '휴게시간에 손님 응대 강요당한 적?',
        options: [
          PollOption(id: '20a', text: '자주 있음', votes: 94),
          PollOption(id: '20b', text: '가끔', votes: 51),
          PollOption(id: '20c', text: '거의 없음', votes: 22),
        ],
      ),
    ),
    Post(
      id: '21',
      content: '휴게시간 식사도 매장 구석에서 눈치 보면서 먹음.\n제대로 된 휴게실 있는 카페 부럽다',
      createdAt: now.subtract(const Duration(days: 3, hours: 4)),
      likeCount: 67,
      tags: ['휴게시간'],
    ),

    // ── 식대 / 직원식사 ──
    Post(
      id: '22',
      content: '식대 안 주는 매장인데 근무 중 배고프면 어떻게 하세요?\n사비로 사 먹는 중…',
      createdAt: now.subtract(const Duration(hours: 11)),
      likeCount: 74,
      tags: ['식대'],
      poll: Poll(
        question: '다니는 카페 식대는?',
        options: [
          PollOption(id: '22a', text: '식대 줌', votes: 48),
          PollOption(id: '22b', text: '식대 안 줌', votes: 71),
          PollOption(id: '22c', text: '음료만 가능', votes: 39),
        ],
      ),
    ),
    Post(
      id: '23',
      content: '직원식사로 유통기한 지난 빵만 줌 ㅋㅋ\n손님용은 새 건데…',
      createdAt: now.subtract(const Duration(days: 2, hours: 3)),
      likeCount: 158,
      tags: ['직원식사'],
      comments: [
        c('c23-1', '23', '와 그건 좀… 위생이랑 존중 문제예요.',
            const Duration(days: 2),
            likes: 44),
      ],
    ),
    Post(
      id: '24',
      content: '식대 대신 “음료 무제한”이라는데\n식사 대체가 안 됨. 배고파서 힘듦',
      createdAt: now.subtract(const Duration(days: 4, hours: 2)),
      likeCount: 59,
      tags: ['식대'],
    ),

    // ── 이직 / 퇴사 / 퇴사 통보 ──
    Post(
      id: '25',
      content:
          '개인카페 vs 프랜차이즈\n이직 고민 중인데 솔직히 어디가 나을까요?\n업무량·사수 스트레스 쪽이라면요',
      createdAt: now.subtract(const Duration(days: 1, hours: 6)),
      likeCount: 148,
      tags: ['이직'],
      poll: Poll(
        question: '다시 고른다면?',
        options: [
          PollOption(id: '25a', text: '개인카페', votes: 34),
          PollOption(id: '25b', text: '프랜차이즈', votes: 52),
          PollOption(id: '25c', text: '카페 말고 다른 곳', votes: 28),
        ],
      ),
      comments: [
        c('c25-1', '25', '사람 따라 다르지만 저는 프차가 시스템이라도 있어서 나았어요.',
            const Duration(days: 1, hours: 2),
            likes: 16),
      ],
    ),
    Post(
      id: '26',
      content: '퇴사 통보 2주 전에 했는데 사장님이\n“당장 나와” 하심. 남은 스케줄은요…?',
      createdAt: now.subtract(const Duration(days: 1, hours: 16)),
      likeCount: 183,
      tags: ['퇴사'],
      comments: [
        c('c26-1', '26', '근로계약서 확인하세요. 일방 해고면 문제될 수 있어요.',
            const Duration(days: 1, hours: 12),
            likes: 37),
      ],
    ),
    Post(
      id: '27',
      content: '이직 면접에서 “왜 그만두냐” 물어보면\n솔직히 어디까지 말해야 해요?',
      createdAt: now.subtract(const Duration(days: 2, hours: 6)),
      likeCount: 91,
      tags: ['이직'],
    ),
    Post(
      id: '28',
      content: '퇴사 통보하고 나서 남은 기간 동안\n근무표 엉망으로 짜주시네… 보복인가요',
      createdAt: now.subtract(const Duration(days: 3, hours: 8)),
      likeCount: 124,
      tags: ['퇴사 통보'],
      comments: [
        c('c28-1', '28', '증거 남기고 조용히 버티세요. 마지막까지 프로로.',
            const Duration(days: 3, hours: 2),
            likes: 29),
      ],
    ),
    Post(
      id: '29',
      content: '카페 그만두고 다른 업종 가신 분?\n적응 어떻게 하셨어요',
      createdAt: now.subtract(const Duration(days: 5)),
      likeCount: 77,
      tags: ['이직'],
    ),

    // ── 오픈 / 피크 / 재고 ──
    Post(
      id: '30',
      content: '오픈 알바 혼자인데 머신 예열이랑 세팅이\n한 시간 가까이 걸림. 원래 이런가요?',
      createdAt: now.subtract(const Duration(hours: 4)),
      likeCount: 63,
      tags: ['오픈'],
      comments: [
        c('c30-1', '30', '매장 크기에 따라 다르지만 혼자면 꽤 걸려요.',
            const Duration(hours: 3),
            likes: 8),
      ],
    ),
    Post(
      id: '31',
      content: '피크 때 줄 섰는데 사장님이 “천천히 해도 돼”\n손님한테는 화내심… 우리만 중간에 낀 느낌',
      createdAt: now.subtract(const Duration(hours: 7)),
      likeCount: 109,
      tags: ['피크'],
    ),
    Post(
      id: '32',
      content: '재고 실수로 원두가 떨어질 뻔함.\n발주 시스템 없는 개인카페라 항상 불안',
      createdAt: now.subtract(const Duration(days: 1, hours: 4)),
      likeCount: 45,
      tags: ['재고'],
      poll: Poll(
        question: '매장 발주/재고 관리 방식은?',
        options: [
          PollOption(id: '32a', text: '앱/시스템', votes: 55),
          PollOption(id: '32b', text: '수기/감', votes: 62),
          PollOption(id: '32c', text: '사장님만 함', votes: 40),
        ],
      ),
    ),
    Post(
      id: '33',
      content: '오픈 직후 단체 손님이 몰려와서\n정신없었음. 오픈 알바 체력 소모 실화…',
      createdAt: now.subtract(const Duration(days: 2, hours: 1)),
      likeCount: 58,
      tags: ['오픈'],
    ),
    Post(
      id: '34',
      content: '피크 타임에 POS랑 제조 동시에 하니까\n실수 잦아짐. 역할 분담이 필요할 듯',
      createdAt: now.subtract(const Duration(days: 3, hours: 5)),
      likeCount: 71,
      tags: ['피크'],
      comments: [
        c('c34-1', '34', '저희는 피크 때 포스 전담 한 명 둡니다.',
            const Duration(days: 3),
            likes: 11),
      ],
    ),

    // ── 유니폼 / 위생 / 교육 ──
    Post(
      id: '35',
      content: '유니폼 세탁비도 알바 부담이래요.\n검은 티인데 커피 묻으면 바로 티 남…',
      createdAt: now.subtract(const Duration(days: 1, hours: 18)),
      likeCount: 86,
      tags: ['유니폼'],
    ),
    Post(
      id: '36',
      content: '위생 점검 앞두고 평소엔 안 하던 청소를\n밤새 시킴. 평소에 하지…',
      createdAt: now.subtract(const Duration(days: 2, hours: 14)),
      likeCount: 112,
      tags: ['위생'],
      comments: [
        c('c36-1', '36', '점검용 쇼인 매장 많죠…',
            const Duration(days: 2, hours: 8),
            likes: 20),
      ],
    ),
    Post(
      id: '37',
      content: '교육 기간인데 시급 안 주고 “연습”이라 함.\n이게 합법인가요?',
      createdAt: now.subtract(const Duration(days: 4, hours: 3)),
      likeCount: 234,
      tags: ['교육'],
      poll: Poll(
        question: '교육/트레이닝 기간 시급 받았나요?',
        options: [
          PollOption(id: '37a', text: '정상 시급', votes: 38),
          PollOption(id: '37b', text: '일부만', votes: 44),
          PollOption(id: '37c', text: '거의/전혀 못 받음', votes: 97),
        ],
      ),
      comments: [
        c('c37-1', '37', '교육도 근로입니다. 안 주면 신고 사유예요.',
            const Duration(days: 3, hours: 20),
            likes: 71),
      ],
    ),
    Post(
      id: '38',
      content: '유니폼 사이즈가 없어서 큰 거 입으라는데\n손님 앞에서 너무 후줄근해 보임',
      createdAt: now.subtract(const Duration(days: 5, hours: 2)),
      likeCount: 41,
      tags: ['유니폼'],
    ),

    // ── 사장님 / 동료 / 고충 ──
    Post(
      id: '39',
      content: '사장님이 손님 앞에서는 착한데\n알바한테만 말투가 확 달라짐…',
      createdAt: now.subtract(const Duration(hours: 13)),
      likeCount: 198,
      tags: ['사장님'],
      comments: [
        c('c39-1', '39', '그런 매장 은근 많아요. 오래 버티기 힘듦.',
            const Duration(hours: 10),
            likes: 35),
      ],
    ),
    Post(
      id: '40',
      content: '같이 일하는 알바생이 일 미루고 폰만 함.\n내가 다 커버하는 중인데 말해도 되나',
      createdAt: now.subtract(const Duration(days: 1, hours: 7)),
      likeCount: 121,
      tags: ['동료'],
      poll: Poll(
        question: '무능/무책임 동료, 어떻게 하세요?',
        options: [
          PollOption(id: '40a', text: '직접 말함', votes: 47),
          PollOption(id: '40b', text: '매니저에게', votes: 68),
          PollOption(id: '40c', text: '참고 혼자 함', votes: 53),
        ],
      ),
    ),
    Post(
      id: '41',
      content: '카페 알바 고충…\n손목이랑 허리가 너무 아픔. 스트레칭 팁 있을까요?',
      createdAt: now.subtract(const Duration(days: 2, hours: 9)),
      likeCount: 94,
      tags: ['고충'],
      comments: [
        c('c41-1', '41', '손목 보호대랑 교대 스트레칭 필수예요.',
            const Duration(days: 2, hours: 5),
            likes: 22),
      ],
    ),
    Post(
      id: '42',
      content: '사장님 자녀가 매장에 와서 알바처럼 지시함.\n서열이 너무 애매해…',
      createdAt: now.subtract(const Duration(days: 3, hours: 11)),
      likeCount: 156,
      tags: ['사장님'],
    ),
    Post(
      id: '43',
      content: '좋은 동료 만나면 알바가 살아요.\n오늘 피크 같이 버티고 서로 음료 쏘기로 함',
      createdAt: now.subtract(const Duration(days: 4, hours: 6)),
      likeCount: 88,
      tags: ['동료'],
    ),
    Post(
      id: '44',
      content: '감정노동 고충이 제일 큼.\n웃으면서 “네~” 하는데 속은 진짜…',
      createdAt: now.subtract(const Duration(days: 5, hours: 4)),
      likeCount: 173,
      tags: ['고충'],
    ),

    // ── 배달 / 포스 / 웨이팅 ──
    Post(
      id: '45',
      content: '배달앱 주문이 피크랑 겹치면 지옥.\n제조 + 포장 + 호출 동시…',
      createdAt: now.subtract(const Duration(hours: 15)),
      likeCount: 102,
      tags: ['배달'],
      comments: [
        c('c45-1', '45', '배달 피크엔 포장 전담 한 명 있으면 숨 쉬어요.',
            const Duration(hours: 12),
            likes: 14),
      ],
    ),
    Post(
      id: '46',
      content: '포스기 먹통인데 손님 줄 서 있음.\n수동 계산하다 금액 틀려서 혼남 ㅠ',
      createdAt: now.subtract(const Duration(days: 1, hours: 9)),
      likeCount: 69,
      tags: ['포스'],
    ),
    Post(
      id: '47',
      content: '웨이팅 관리하다가 손님끼리 싸움 날 뻔함.\n순번 시스템 없는 매장은 진짜 힘듦',
      createdAt: now.subtract(const Duration(days: 2, hours: 16)),
      likeCount: 81,
      tags: ['웨이팅'],
      poll: Poll(
        question: '매장 웨이팅 방식은?',
        options: [
          PollOption(id: '47a', text: '앱/번호표', votes: 57),
          PollOption(id: '47b', text: '수기 명단', votes: 43),
          PollOption(id: '47c', text: '그냥 줄 섬', votes: 36),
        ],
      ),
    ),
    Post(
      id: '48',
      content: '배달 리뷰에 “맛없음” 별 1개 달렸는데\n사장님이 알바 탓으로 돌리심…',
      createdAt: now.subtract(const Duration(days: 3, hours: 14)),
      likeCount: 147,
      tags: ['배달'],
    ),

    // ── 꿀알바 / 질문 / 기타 ──
    Post(
      id: '49',
      content: '요즘 카페 중에 괜찮았던 매장 포인트?\n저는 “휴게 보장 + 식대 + 인수인계 문서”요',
      createdAt: now.subtract(const Duration(hours: 3)),
      likeCount: 56,
      tags: ['꿀알바'],
      comments: [
        c('c49-1', '49', '스케줄 미리 나오는 곳도 진짜 중요해요.',
            const Duration(hours: 2),
            likes: 10),
      ],
    ),
    Post(
      id: '50',
      content: '라떼아트 연습하고 싶은데\n남는 우유로 해도 되는지 눈치 보임. 다들 어때요?',
      createdAt: now.subtract(const Duration(hours: 10)),
      likeCount: 48,
      tags: ['질문'],
    ),
    Post(
      id: '51',
      content: '첫 카페 알바인데 용어가 너무 많음.\n샷 / 리츄 / 디카페인… 메모장 필수인가요?',
      createdAt: now.subtract(const Duration(days: 1, hours: 1)),
      likeCount: 79,
      tags: ['질문'],
      comments: [
        c('c51-1', '51', '첫 주는 메모 필수예요. 일주일만 지나도 입에 붙어요.',
            const Duration(hours: 18),
            likes: 15),
      ],
    ),
    Post(
      id: '52',
      content: '비 오는 날 손님 없어서 꿀이었음.\n이런 날엔 재고 정리하면서 숨 고르기',
      createdAt: now.subtract(const Duration(days: 2, hours: 7)),
      likeCount: 37,
      tags: ['꿀알바'],
    ),
    Post(
      id: '53',
      content: '여름 시즌 아이스만 주문이어서\n팔이 따로 놀음. 얼음 셔블 근육 생김 ㅋㅋ',
      createdAt: now.subtract(const Duration(days: 4, hours: 8)),
      likeCount: 65,
      tags: ['고충'],
    ),
    Post(
      id: '54',
      content: '겨울엔 오픈할 때 손이 너무 시림.\n핫워터로 녹이면서 시작…',
      createdAt: now.subtract(const Duration(days: 6)),
      likeCount: 52,
      tags: ['오픈'],
    ),
    Post(
      id: '55',
      content: '카페 알바하면서 배운 점?\n저는 “빠른 판단 + 감정 분리”가 제일 크네요',
      createdAt: now.subtract(const Duration(days: 6, hours: 8)),
      likeCount: 99,
      tags: ['고충'],
      comments: [
        c('c55-1', '55', '감정 분리 못하면 진짜 오래 못 해요…',
            const Duration(days: 6, hours: 2),
            likes: 18),
      ],
    ),
    Post(
      id: '56',
      content: '급여 명세서에 항목이 뭉뚱그려져 있음.\n주휴/야간 구분이 안 보여서 불안해요',
      createdAt: now.subtract(const Duration(days: 7)),
      likeCount: 134,
      tags: ['급여'],
    ),
    Post(
      id: '57',
      content: '마감 후 쓰레기 분리까지 하는데\n음식물 냄새가… 위생복 필수인 이유 알겠음',
      createdAt: now.subtract(const Duration(days: 7, hours: 5)),
      likeCount: 44,
      tags: ['마감 업무'],
    ),
    Post(
      id: '58',
      content: '진상 손님 블랙리스트 제도 있는 매장?\n있으면 얼마나 효과 있어요?',
      createdAt: now.subtract(const Duration(days: 8)),
      likeCount: 117,
      tags: ['진상'],
      poll: Poll(
        question: '매장에 진상 블랙리스트가 있나요?',
        options: [
          PollOption(id: '58a', text: '있음', votes: 49),
          PollOption(id: '58b', text: '없음', votes: 71),
          PollOption(id: '58c', text: '비공식으로만', votes: 38),
        ],
      ),
    ),
    Post(
      id: '59',
      content: '근무시간 기록용 앱 쓰시는 분?\n사장님 몰래(?) 아니라 내 기록용으로요',
      createdAt: now.subtract(const Duration(days: 8, hours: 6)),
      likeCount: 76,
      tags: ['근무시간'],
      comments: [
        c('c59-1', '59', '저만의 출퇴근 메모 꼭 해요. 나중에 도움이 됩니다.',
            const Duration(days: 8, hours: 1),
            likes: 24),
      ],
    ),
    Post(
      id: '60',
      content: '카페인(앱) 덕분에 혼자만 힘든 줄 알았는데\n다들 비슷한 고민이구나… 응원합니다',
      createdAt: now.subtract(const Duration(days: 9)),
      likeCount: 205,
      tags: ['고충'],
      comments: [
        c('c60-1', '60', '맞아요. 익명이라 더 편하게 말할 수 있어서 좋아요.',
            const Duration(days: 8, hours: 20),
            likes: 41),
        c('c60-2', '60', '오늘도 수고하셨어요!',
            const Duration(days: 8, hours: 18),
            likes: 19),
      ],
    ),
  ];
}
