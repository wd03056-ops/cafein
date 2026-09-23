/**
 * CAFEIN Play Store screenshot seed payload.
 * Field shapes match PostsFirestoreService / CommentsFirestoreService /
 * TopicsFirestoreService + Post/Comment/Poll/Topic parsers.
 *
 * No Flutter app code imports this file.
 */

const SEED_TAG = 'cafein_play_screenshot';

/** Stable fake Kakao-like author ids (not real users). */
const AUTHORS = {
  a1: {
    id: 'screenshot_author_01',
    nickname: '마감요정',
    cafeType: '프랜차이즈',
    experience: '1~3년',
  },
  a2: {
    id: 'screenshot_author_02',
    nickname: '샷 내린 알바',
    cafeType: '개인카페',
    experience: '6개월 이상',
  },
  a3: {
    id: 'screenshot_author_03',
    nickname: '오픈담당',
    cafeType: '프랜차이즈',
    experience: '3개월 이상',
  },
  a4: {
    id: 'screenshot_author_04',
    nickname: '시급계산기',
    cafeType: '개인카페',
    experience: '1~3년',
  },
  a5: {
    id: 'screenshot_author_05',
    nickname: '피크생존자',
    cafeType: '프랜차이즈',
    experience: '1개월 이상',
  },
  a6: {
    id: 'screenshot_author_06',
    nickname: '라떼고수',
    cafeType: '개인카페',
    experience: '4~5년 이상',
  },
  a7: {
    id: 'screenshot_author_07',
    nickname: '진상방어막',
    cafeType: '프랜차이즈',
    experience: '6개월 이상',
  },
  a8: {
    id: 'screenshot_author_08',
    nickname: '출근5분전',
    cafeType: '개인카페',
    experience: '1개월 미만',
  },
};

/**
 * Fixed topic ids — posts reference these for fetchSimilarPosts / topic feed.
 */
const TOPICS = [
  {
    id: 'screenshot_topic_jinsang',
    name: '진상손님',
    usageCount: 3,
  },
  {
    id: 'screenshot_topic_weekly',
    name: '주휴수당',
    usageCount: 3,
  },
  {
    id: 'screenshot_topic_close',
    name: '마감',
    usageCount: 3,
  },
  {
    id: 'screenshot_topic_pay',
    name: '급여',
    usageCount: 3,
  },
  {
    id: 'screenshot_topic_hardship',
    name: '알바고충',
    usageCount: 3,
  },
  {
    id: 'screenshot_topic_open',
    name: '오픈',
    usageCount: 3,
  },
  {
    id: 'screenshot_topic_quit',
    name: '퇴사',
    usageCount: 3,
  },
  {
    id: 'screenshot_topic_tips',
    name: '카페꿀팁',
    usageCount: 3,
  },
];

/**
 * Hours ago from seed run time → createdAt (home feed orderBy createdAt desc).
 * Interleaved topics so the first screen is mixed.
 */
const POSTS = [
  // ── 홈 상단 믹스 ──
  {
    id: 'screenshot_post_001',
    topicId: 'screenshot_topic_close',
    topicName: '마감',
    author: AUTHORS.a1,
    hoursAgo: 1,
    likeCount: 86,
    content:
      '마감 10분 전에 손님 들어오면 진짜 당황함…\n문 닫기 직전인데 어떻게 하세요?',
    poll: {
      question: '마감 직전 손님, 보통 어떻게 하세요?',
      options: [
        { id: 'opt_0', text: '그냥 받음', voteCount: 42 },
        { id: 'opt_1', text: '포장만 가능하다고 함', voteCount: 57 },
        { id: 'opt_2', text: '정중히 거절', voteCount: 19 },
      ],
    },
    comments: [
      {
        id: 'screenshot_cmt_001_1',
        author: AUTHORS.a2,
        minutesAgo: 40,
        likeCount: 12,
        content: '저희는 마감 시간 기준으로 포장만 받아요.',
      },
      {
        id: 'screenshot_cmt_001_2',
        author: AUTHORS.a5,
        minutesAgo: 25,
        likeCount: 7,
        content: '사장 눈치 보면서 받긴 하는데 속으로는…',
      },
      {
        id: 'screenshot_cmt_001_3',
        author: AUTHORS.a7,
        minutesAgo: 10,
        likeCount: 4,
        content: '문 앞에 마감 안내 붙여두면 조금 나아지더라고요.',
      },
    ],
  },
  {
    id: 'screenshot_post_002',
    topicId: 'screenshot_topic_jinsang',
    topicName: '진상손님',
    author: AUTHORS.a7,
    hoursAgo: 2,
    likeCount: 214,
    content:
      '아이스 아메리카노 다 마시더니 처음 시켰다고 환불 요청함.\n매니저님이 그냥 환불해주셨는데… 다들 이런 경우 어떻게 하세요?',
    comments: [
      {
        id: 'screenshot_cmt_002_1',
        author: AUTHORS.a1,
        minutesAgo: 90,
        likeCount: 31,
        content: '그거 CCTV 보면 끝인데 왜 환불을…',
      },
      {
        id: 'screenshot_cmt_002_2',
        author: AUTHORS.a3,
        minutesAgo: 70,
        likeCount: 18,
        content: '저희는 다 마신 건 절대 안 해줘요.',
      },
      {
        id: 'screenshot_cmt_002_3',
        author: AUTHORS.a6,
        minutesAgo: 45,
        likeCount: 9,
        content: '진상 응대 매뉴얼이 있으면 그나마 덜 힘들어요.',
      },
      {
        id: 'screenshot_cmt_002_4',
        author: AUTHORS.a4,
        minutesAgo: 20,
        likeCount: 6,
        content: '공감… 알바만 중간에 껴서 멘탈 털림',
      },
    ],
  },
  {
    id: 'screenshot_post_003',
    topicId: 'screenshot_topic_weekly',
    topicName: '주휴수당',
    author: AUTHORS.a4,
    hoursAgo: 3,
    likeCount: 198,
    content:
      '주 15시간 넘게 일하는데 주휴수당이 명세서에 안 보여요.\n개인카페인데 이게 흔한가요?',
    poll: {
      question: '지금 카페에서 주휴수당 받고 있나요?',
      options: [
        { id: 'opt_0', text: '제대로 받음', voteCount: 41 },
        { id: 'opt_1', text: '일부만 / 애매함', voteCount: 67 },
        { id: 'opt_2', text: '아예 안 받음', voteCount: 89 },
        { id: 'opt_3', text: '잘 모르겠음', voteCount: 23 },
      ],
    },
    comments: [
      {
        id: 'screenshot_cmt_003_1',
        author: AUTHORS.a6,
        minutesAgo: 110,
        likeCount: 44,
        content: '주휴는 법이에요. 계약서랑 명세서 다시 보세요.',
      },
      {
        id: 'screenshot_cmt_003_2',
        author: AUTHORS.a2,
        minutesAgo: 80,
        likeCount: 21,
        content: '저도 처음엔 몰랐어요. 물어보니까 “포함”이라더라고요.',
      },
      {
        id: 'screenshot_cmt_003_3',
        author: AUTHORS.a1,
        minutesAgo: 35,
        likeCount: 11,
        content: '항목이 없으면 문자로라도 확인 받아두세요.',
      },
    ],
  },
  {
    id: 'screenshot_post_004',
    topicId: 'screenshot_topic_open',
    topicName: '오픈',
    author: AUTHORS.a3,
    hoursAgo: 4,
    likeCount: 72,
    content: '오픈 알바 혼자인데 세팅만 한 시간… 원래 이런가요?',
    comments: [
      {
        id: 'screenshot_cmt_004_1',
        author: AUTHORS.a8,
        minutesAgo: 100,
        likeCount: 8,
        content: '혼자면 거의 그 정도 걸려요.',
      },
      {
        id: 'screenshot_cmt_004_2',
        author: AUTHORS.a5,
        minutesAgo: 50,
        likeCount: 5,
        content: '체크리스트 있으면 조금 빨라지긴 해요.',
      },
    ],
  },
  {
    id: 'screenshot_post_005',
    topicId: 'screenshot_topic_hardship',
    topicName: '알바고충',
    author: AUTHORS.a5,
    hoursAgo: 5,
    likeCount: 156,
    content:
      '감정노동이 제일 힘듦.\n웃으면서 “네~” 하는데 속은 진짜…\n손목이랑 허리도 슬슬 아프고.\n다들 스트레칭이나 멘탈 관리 어떻게 하세요?',
    comments: [
      {
        id: 'screenshot_cmt_005_1',
        author: AUTHORS.a6,
        minutesAgo: 140,
        likeCount: 27,
        content: '손목 보호대랑 교대 스트레칭이요.',
      },
      {
        id: 'screenshot_cmt_005_2',
        author: AUTHORS.a1,
        minutesAgo: 90,
        likeCount: 14,
        content: '감정 분리 못하면 오래 못 버텨요… 공감합니다.',
      },
      {
        id: 'screenshot_cmt_005_3',
        author: AUTHORS.a7,
        minutesAgo: 40,
        likeCount: 9,
        content: '퇴근하고 바로 씻고 자는 게 제 루틴이에요.',
      },
    ],
  },
  {
    id: 'screenshot_post_006',
    topicId: 'screenshot_topic_pay',
    topicName: '급여',
    author: AUTHORS.a4,
    hoursAgo: 6,
    likeCount: 131,
    content: '급여일에 이틀씩 늦는 거 정상인가요? “입금 처리 중”만 반복함',
    comments: [
      {
        id: 'screenshot_cmt_006_1',
        author: AUTHORS.a2,
        minutesAgo: 200,
        likeCount: 19,
        content: '늦는 건 이상한 거예요. 날짜 문자로 남겨두세요.',
      },
      {
        id: 'screenshot_cmt_006_2',
        author: AUTHORS.a6,
        minutesAgo: 120,
        likeCount: 11,
        content: '근로계약서에 지급일이 있을 거예요.',
      },
    ],
  },
  {
    id: 'screenshot_post_007',
    topicId: 'screenshot_topic_tips',
    topicName: '카페꿀팁',
    author: AUTHORS.a6,
    hoursAgo: 7,
    likeCount: 64,
    content:
      '피크 때 실수 줄이는 팁 있으면 공유해주세요.\n저는 POS랑 제조를 아예 나눠서 하는 쪽이 덜 헷갈리더라고요.',
    poll: {
      question: '피크 때 제일 도움 되는 건?',
      options: [
        { id: 'opt_0', text: '역할 분담 (POS/제조)', voteCount: 54 },
        { id: 'opt_1', text: '주문 복창', voteCount: 39 },
        { id: 'opt_2', text: '사전 세팅', voteCount: 28 },
      ],
    },
    comments: [
      {
        id: 'screenshot_cmt_007_1',
        author: AUTHORS.a3,
        minutesAgo: 160,
        likeCount: 10,
        content: '주문 크게 복창하는 게 제일 효과 있었어요.',
      },
      {
        id: 'screenshot_cmt_007_2',
        author: AUTHORS.a5,
        minutesAgo: 70,
        likeCount: 6,
        content: '샷 타이머 습관화하면 덜 밀려요.',
      },
    ],
  },
  {
    id: 'screenshot_post_008',
    topicId: 'screenshot_topic_quit',
    topicName: '퇴사',
    author: AUTHORS.a2,
    hoursAgo: 8,
    likeCount: 177,
    content:
      '퇴사 통보 2주 전에 했는데 사장님이 “당장 나와” 하심.\n남은 스케줄이랑 급여는 어떻게 되는 거죠?',
    comments: [
      {
        id: 'screenshot_cmt_008_1',
        author: AUTHORS.a4,
        minutesAgo: 300,
        likeCount: 38,
        content: '일방 해고면 문제될 수 있어요. 대화는 카톡으로 남기세요.',
      },
      {
        id: 'screenshot_cmt_008_2',
        author: AUTHORS.a6,
        minutesAgo: 210,
        likeCount: 22,
        content: '근로계약서부터 다시 확인하세요.',
      },
      {
        id: 'screenshot_cmt_008_3',
        author: AUTHORS.a1,
        minutesAgo: 90,
        likeCount: 8,
        content: '비슷한 일 겪었는데 증거 남긴 게 도움이 됐어요.',
      },
    ],
  },

  // ── 진상손님 (비슷한 글용 추가) ──
  {
    id: 'screenshot_post_009',
    topicId: 'screenshot_topic_jinsang',
    topicName: '진상손님',
    author: AUTHORS.a5,
    hoursAgo: 10,
    likeCount: 143,
    content: '테이크아웃인데 자리 잡고 노트북 3시간… 눈치 주기도 애매함',
    comments: [
      {
        id: 'screenshot_cmt_009_1',
        author: AUTHORS.a7,
        minutesAgo: 400,
        likeCount: 16,
        content: '저희는 콘센트 옆만 시간 제한 걸어뒀어요.',
      },
      {
        id: 'screenshot_cmt_009_2',
        author: AUTHORS.a3,
        minutesAgo: 200,
        likeCount: 7,
        content: '매장마다 다르긴 한데 난감하죠…',
      },
    ],
  },
  {
    id: 'screenshot_post_010',
    topicId: 'screenshot_topic_jinsang',
    topicName: '진상손님',
    author: AUTHORS.a1,
    hoursAgo: 14,
    likeCount: 97,
    content:
      '커스텀 주문 엄청 복잡하게 시키고 “왜 이렇게 오래 걸려요?” 하는 손님.\n진상손님 응대할 때 제일 힘든 포인트가 뭐예요?',
    poll: {
      question: '카페 알바하면서 제일 힘든 건 뭐예요?',
      options: [
        { id: 'opt_0', text: '손님 응대', voteCount: 78 },
        { id: 'opt_1', text: '사장님/매니저', voteCount: 61 },
        { id: 'opt_2', text: '같이 일하는 직원', voteCount: 34 },
        { id: 'opt_3', text: '급여/근무조건', voteCount: 52 },
      ],
    },
    comments: [
      {
        id: 'screenshot_cmt_010_1',
        author: AUTHORS.a7,
        minutesAgo: 500,
        likeCount: 25,
        content: '손님 응대가 압도적…',
      },
      {
        id: 'screenshot_cmt_010_2',
        author: AUTHORS.a4,
        minutesAgo: 320,
        likeCount: 13,
        content: '저는 급여/근무조건이 더 오래 남아요.',
      },
      {
        id: 'screenshot_cmt_010_3',
        author: AUTHORS.a2,
        minutesAgo: 100,
        likeCount: 5,
        content: '레시피 카드 보여드리면 말이 줄어들긴 해요.',
      },
    ],
  },

  // ── 주휴수당 추가 ──
  {
    id: 'screenshot_post_011',
    topicId: 'screenshot_topic_weekly',
    topicName: '주휴수당',
    author: AUTHORS.a2,
    hoursAgo: 16,
    likeCount: 121,
    content: '주휴수당을 “보너스”라고 부르는 사장님… 법적으로 당연히 줘야 하는 건데',
    comments: [
      {
        id: 'screenshot_cmt_011_1',
        author: AUTHORS.a4,
        minutesAgo: 600,
        likeCount: 33,
        content: '고용노동부 상담 익명으로도 됩니다.',
      },
      {
        id: 'screenshot_cmt_011_2',
        author: AUTHORS.a6,
        minutesAgo: 280,
        likeCount: 14,
        content: '보너스 아니라 수당이에요.',
      },
    ],
  },
  {
    id: 'screenshot_post_012',
    topicId: 'screenshot_topic_weekly',
    topicName: '주휴수당',
    author: AUTHORS.a8,
    hoursAgo: 20,
    likeCount: 88,
    content: '주휴 계산법이 헷갈려요. 시급 × 몇 시간으로 찍혀야 정상인가요?',
    comments: [
      {
        id: 'screenshot_cmt_012_1',
        author: AUTHORS.a4,
        minutesAgo: 700,
        likeCount: 17,
        content: '1일 소정근로시간만큼이 기본이에요. 매장마다 소정이 다를 수 있어요.',
      },
      {
        id: 'screenshot_cmt_012_2',
        author: AUTHORS.a1,
        minutesAgo: 360,
        likeCount: 8,
        content: '명세서에 주휴 항목이 분리돼 있는지가 중요해요.',
      },
    ],
  },

  // ── 마감 추가 ──
  {
    id: 'screenshot_post_013',
    topicId: 'screenshot_topic_close',
    topicName: '마감',
    author: AUTHORS.a2,
    hoursAgo: 22,
    likeCount: 109,
    content:
      '마감 업무가 너무 많음.\n머신 세척, 바닥, 쓰레기, 재고까지 혼자면 한 시간 넘게 걸림.\n체크리스트도 없고 사장님은 “알아서”만 하심.\n어제 12시 넘어서 나왔는데 오늘 또 오픈이라 힘듦.',
    comments: [
      {
        id: 'screenshot_cmt_013_1',
        author: AUTHORS.a1,
        minutesAgo: 800,
        likeCount: 21,
        content: '혼자 마감이면 진짜 많아요. 인수인계 문서라도 받아두세요.',
      },
      {
        id: 'screenshot_cmt_013_2',
        author: AUTHORS.a3,
        minutesAgo: 500,
        likeCount: 12,
        content: '오픈이랑 붙으면 거의 생존 모드죠…',
      },
      {
        id: 'screenshot_cmt_013_3',
        author: AUTHORS.a5,
        minutesAgo: 200,
        likeCount: 6,
        content: '체크리스트 만들어달라고 하세요. 없으면 끝도 없어요.',
      },
    ],
  },
  {
    id: 'screenshot_post_014',
    topicId: 'screenshot_topic_close',
    topicName: '마감',
    author: AUTHORS.a5,
    hoursAgo: 28,
    likeCount: 74,
    content: '주말 마감이 유독 힘듦. 손님은 많은데 인원은 평일 그대로',
    comments: [
      {
        id: 'screenshot_cmt_014_1',
        author: AUTHORS.a7,
        minutesAgo: 900,
        likeCount: 9,
        content: '주말 인원 추가는 거의 전쟁이에요.',
      },
      {
        id: 'screenshot_cmt_014_2',
        author: AUTHORS.a3,
        minutesAgo: 400,
        likeCount: 4,
        content: '저희도 똑같아요…',
      },
    ],
  },

  // ── 급여 추가 ──
  {
    id: 'screenshot_post_015',
    topicId: 'screenshot_topic_pay',
    topicName: '급여',
    author: AUTHORS.a2,
    hoursAgo: 30,
    likeCount: 168,
    content:
      '시급 인상 얘기 꺼냈더니 사장님이 손님 없다만 반복하심.\n그래도 최저임금은 맞춰줘야 하는 거 맞죠?',
    comments: [
      {
        id: 'screenshot_cmt_015_1',
        author: AUTHORS.a4,
        minutesAgo: 1000,
        likeCount: 41,
        content: '네. 손님 수랑 최저임금은 별개예요.',
      },
      {
        id: 'screenshot_cmt_015_2',
        author: AUTHORS.a6,
        minutesAgo: 600,
        likeCount: 19,
        content: '계약서·명세서 꼭 남겨두세요.',
      },
      {
        id: 'screenshot_cmt_015_3',
        author: AUTHORS.a1,
        minutesAgo: 240,
        likeCount: 7,
        content: '야간수당도 같이 확인해보세요.',
      },
    ],
  },
  {
    id: 'screenshot_post_016',
    topicId: 'screenshot_topic_pay',
    topicName: '급여',
    author: AUTHORS.a8,
    hoursAgo: 34,
    likeCount: 93,
    content: '야간수당 안 주고 “시급에 포함”이라고만 함. 22시 넘어서 일하는데 맞나요?',
    poll: {
      question: '야간/주휴 등 수당, 제대로 받고 있나요?',
      options: [
        { id: 'opt_0', text: '제대로 받음', voteCount: 36 },
        { id: 'opt_1', text: '애매함', voteCount: 58 },
        { id: 'opt_2', text: '거의 못 받음', voteCount: 71 },
      ],
    },
    comments: [
      {
        id: 'screenshot_cmt_016_1',
        author: AUTHORS.a4,
        minutesAgo: 1100,
        likeCount: 28,
        content: '포함이라고 해도 실질적으로 최저+야간이 안 되면 문제예요.',
      },
      {
        id: 'screenshot_cmt_016_2',
        author: AUTHORS.a2,
        minutesAgo: 500,
        likeCount: 10,
        content: '출퇴근 기록부터 남겨두세요.',
      },
    ],
  },

  // ── 알바고충 추가 ──
  {
    id: 'screenshot_post_017',
    topicId: 'screenshot_topic_hardship',
    topicName: '알바고충',
    author: AUTHORS.a1,
    hoursAgo: 38,
    likeCount: 119,
    content: '사장님이 손님 앞에선 착한데 알바한테만 말투가 확 달라짐…',
    comments: [
      {
        id: 'screenshot_cmt_017_1',
        author: AUTHORS.a5,
        minutesAgo: 1200,
        likeCount: 24,
        content: '이중 태도는 진짜 멘탈 깎여요.',
      },
      {
        id: 'screenshot_cmt_017_2',
        author: AUTHORS.a7,
        minutesAgo: 700,
        likeCount: 11,
        content: '그런 매장 은근 많아요…',
      },
    ],
  },
  {
    id: 'screenshot_post_018',
    topicId: 'screenshot_topic_hardship',
    topicName: '알바고충',
    author: AUTHORS.a7,
    hoursAgo: 42,
    likeCount: 84,
    content: '같이 일하는 알바가 폰만 하고 일은 미룸. 내가 다 커버 중인데 말해도 되나',
    poll: {
      question: '무책임한 동료, 어떻게 하세요?',
      options: [
        { id: 'opt_0', text: '직접 말함', voteCount: 47 },
        { id: 'opt_1', text: '매니저에게', voteCount: 68 },
        { id: 'opt_2', text: '참고 혼자 함', voteCount: 53 },
      ],
    },
    comments: [
      {
        id: 'screenshot_cmt_018_1',
        author: AUTHORS.a3,
        minutesAgo: 900,
        likeCount: 15,
        content: '팩트만 짧게 매니저한테 말하는 게 덜 피곤하더라고요.',
      },
      {
        id: 'screenshot_cmt_018_2',
        author: AUTHORS.a2,
        minutesAgo: 300,
        likeCount: 6,
        content: '직접 말하면 싸움 나는 타입도 있어서…',
      },
    ],
  },

  // ── 오픈 추가 ──
  {
    id: 'screenshot_post_019',
    topicId: 'screenshot_topic_open',
    topicName: '오픈',
    author: AUTHORS.a8,
    hoursAgo: 46,
    likeCount: 152,
    content:
      '오픈인데 출근 30분 전에 나와서 준비하래.\n그 시간은 근무로 안 친대요. 준비 시간도 근로시간 아닌가요?',
    comments: [
      {
        id: 'screenshot_cmt_019_1',
        author: AUTHORS.a4,
        minutesAgo: 1300,
        likeCount: 48,
        content: '준비 시간도 근로입니다. 기록 남기세요.',
      },
      {
        id: 'screenshot_cmt_019_2',
        author: AUTHORS.a6,
        minutesAgo: 800,
        likeCount: 20,
        content: '저도 소급해서 받았어요.',
      },
      {
        id: 'screenshot_cmt_019_3',
        author: AUTHORS.a3,
        minutesAgo: 200,
        likeCount: 7,
        content: '출퇴근 메모 앱으로라도 남겨두세요.',
      },
    ],
  },
  {
    id: 'screenshot_post_020',
    topicId: 'screenshot_topic_open',
    topicName: '오픈',
    author: AUTHORS.a3,
    hoursAgo: 50,
    likeCount: 61,
    content: '오픈 직후 단체 손님이 몰려오면 멘탈 나감… 오픈 알바 체력 소모 실화',
    comments: [
      {
        id: 'screenshot_cmt_020_1',
        author: AUTHORS.a5,
        minutesAgo: 1000,
        likeCount: 8,
        content: '오픈 직후 피크면 진짜 지옥이에요.',
      },
      {
        id: 'screenshot_cmt_020_2',
        author: AUTHORS.a1,
        minutesAgo: 400,
        likeCount: 3,
        content: '물 미리 채워두는 습관이 도움이 됐어요.',
      },
    ],
  },

  // ── 퇴사 추가 ──
  {
    id: 'screenshot_post_021',
    topicId: 'screenshot_topic_quit',
    topicName: '퇴사',
    author: AUTHORS.a5,
    hoursAgo: 54,
    likeCount: 101,
    content: '퇴사 통보하고 나서 남은 기간 근무표가 갑자기 엉망… 보복인가요',
    comments: [
      {
        id: 'screenshot_cmt_021_1',
        author: AUTHORS.a2,
        minutesAgo: 1400,
        likeCount: 18,
        content: '증거 남기고 마지막까지 프로로 버티세요.',
      },
      {
        id: 'screenshot_cmt_021_2',
        author: AUTHORS.a4,
        minutesAgo: 600,
        likeCount: 9,
        content: '스케줄 캡처 꼭 해두세요.',
      },
    ],
  },
  {
    id: 'screenshot_post_022',
    topicId: 'screenshot_topic_quit',
    topicName: '퇴사',
    author: AUTHORS.a6,
    hoursAgo: 60,
    likeCount: 79,
    content: '이직 면접에서 “왜 그만두냐” 물어보면 솔직히 어디까지 말해야 해요?',
    comments: [
      {
        id: 'screenshot_cmt_022_1',
        author: AUTHORS.a1,
        minutesAgo: 1500,
        likeCount: 12,
        content: '전 직장 욕은 안 하고 “성장” 쪽으로만 말했어요.',
      },
      {
        id: 'screenshot_cmt_022_2',
        author: AUTHORS.a7,
        minutesAgo: 700,
        likeCount: 5,
        content: '근무환경 이야기는 조심스레…',
      },
    ],
  },

  // ── 카페꿀팁 추가 ──
  {
    id: 'screenshot_post_023',
    topicId: 'screenshot_topic_tips',
    topicName: '카페꿀팁',
    author: AUTHORS.a3,
    hoursAgo: 66,
    likeCount: 55,
    content: '첫 카페 알바 용어 정리… 샷/리츄/디카페인 메모장 필수인가요?',
    comments: [
      {
        id: 'screenshot_cmt_023_1',
        author: AUTHORS.a8,
        minutesAgo: 1600,
        likeCount: 11,
        content: '첫 주는 메모 필수예요. 금방 입에 붙어요.',
      },
      {
        id: 'screenshot_cmt_023_2',
        author: AUTHORS.a6,
        minutesAgo: 900,
        likeCount: 7,
        content: '핸드폰 메모에 레시피만 정리해도 살아요.',
      },
    ],
  },
  {
    id: 'screenshot_post_024',
    topicId: 'screenshot_topic_tips',
    topicName: '카페꿀팁',
    author: AUTHORS.a6,
    hoursAgo: 72,
    likeCount: 91,
    content:
      '괜찮았던 매장 포인트 공유하면\n휴게 보장 + 식대 + 스케줄 미리 나오기 + 인수인계 문서요.\n더 있으면 알려주세요.',
    comments: [
      {
        id: 'screenshot_cmt_024_1',
        author: AUTHORS.a2,
        minutesAgo: 1700,
        likeCount: 15,
        content: '야간수당 제대로 주는 곳도 진짜 중요해요.',
      },
      {
        id: 'screenshot_cmt_024_2',
        author: AUTHORS.a5,
        minutesAgo: 1000,
        likeCount: 8,
        content: '마감 인원 2명 이상인 곳…',
      },
      {
        id: 'screenshot_cmt_024_3',
        author: AUTHORS.a4,
        minutesAgo: 400,
        likeCount: 4,
        content: '교육 기간 시급 주는지도요.',
      },
    ],
  },
];

function topicNameKey(name) {
  return String(name).trim().replace(/\s+/g, ' ').toLowerCase();
}

function buildManifest() {
  const commentIds = [];
  for (const post of POSTS) {
    for (const c of post.comments || []) {
      commentIds.push({ postId: post.id, commentId: c.id });
    }
  }
  return {
    seedTag: SEED_TAG,
    topics: TOPICS.map((t) => t.id),
    topicNames: TOPICS.map((t) => topicNameKey(t.name)),
    posts: POSTS.map((p) => p.id),
    comments: commentIds,
    pollPostIds: POSTS.filter((p) => p.poll).map((p) => p.id),
  };
}

module.exports = {
  SEED_TAG,
  AUTHORS,
  TOPICS,
  POSTS,
  topicNameKey,
  buildManifest,
};
