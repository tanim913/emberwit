/// Language a reply should be written in.
///
/// Small models often ignore "reply in the user's language", so the language
/// of each new message is detected here and stated plainly in the prompt.
enum ReplyLanguage {
  /// English.
  english('The user wrote in English. Reply in English only.'),

  /// Bengali, typed in Bengali script or in Latin letters ("kemon acho").
  /// The reply is always in Bengali script.
  bengali(
    'The user wrote in Bengali. Reply in Bengali only, written in Bengali '
    'script (বাংলা).',
  );

  new(this.instruction);

  /// Sentence added to the system prompt.
  final String instruction;

  /// The language of [text], or `null` when it has no words to go by
  /// (numbers, emoji, a formula).
  ///
  /// Bengali script wins when it is at least a third of the letters, so a
  /// Bengali sentence with an English term is Bengali, while an English
  /// question quoting a few Bengali words stays English. Latin text is
  /// Bengali when common romanized Bengali words outnumber common English
  /// ones; anything else in Latin letters is English.
  static ReplyLanguage? detect(String text) {
    var bengaliLetters = 0;
    var latinLetters = 0;
    for (final rune in text.runes) {
      if (rune >= 0x0980 && rune <= 0x09FF) {
        bengaliLetters++;
      } else if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A)) {
        latinLetters++;
      }
    }
    if (bengaliLetters == 0 && latinLetters == 0) return null;
    if (bengaliLetters * 2 >= latinLetters) return ReplyLanguage.bengali;

    final words = _word
        .allMatches(text.toLowerCase())
        .map((m) => m[0]!)
        .toList();
    final bengaliWords = words.where(_romanizedBengali.contains).length;
    final englishWords = words.where(_english.contains).length;
    return bengaliWords > englishWords
        ? ReplyLanguage.bengali
        : ReplyLanguage.english;
  }

  /// The language to reply in after [userMessages] (oldest first): that of
  /// the newest message with words, or `null` when none has any.
  static ReplyLanguage? forConversation(Iterable<String> userMessages) {
    for (final message in userMessages.toList().reversed) {
      final language = detect(message);
      if (language != null) return language;
    }
    return null;
  }

  /// [system] with this language's instruction added at the end.
  String appendTo(String system) {
    final base = system.trim();
    return base.isEmpty ? instruction : '$base\n\n$instruction';
  }
}

final RegExp _word = RegExp('[a-z]+');

/// Frequent romanized Bengali words that are rare as English words.
final Set<String> _romanizedBengali = _words(
  'ami amra amar amader amake tumi tomar tomake tomra tomader apni apnar '
  'apnake apnara apnader er se tar tara tader ora oder ke kar ki keno kno '
  'kemon kmn kivabe kibhabe kemne kothay kothai kobe kokhon koto kon '
  'kichu kisu keu naki acho achen achi ache achhe ase asen asi achho '
  'chilo chhilo silo nai nei na hobe hoy hoye hoyeche hoise hoyse holo '
  'hoilo kori koro koren korbo korte korchi korsi korecho korlam kore '
  'korun bolo bolen bolte bolchi bolun jani janina jante janen janao '
  'janan jabo jao jaben khabo khai khete valo bhalo bhalobasi bhalobashi '
  'valobasi onek khub kintu tahole tahle jodi ekta ekti ektu shob sob '
  'shobai sobai dhonnobad dhonyobad accha acha thik bhai vai apu lagbe '
  'lage chai chao chan diye dite dao niye theke ekhon akhon ajke aj kalke '
  'ei oi eta ota sheta seta eita oita mane shathe sathe jonno jnno bhabe '
  'vabe porte pori likho likhte likhun bujhi bujhlam bujhte bujhao '
  'bujhiye shekhao shikhte golpo kobita proshno prosno uttor abar aro '
  'arekta pari parbo paro paren parben dekhao dekhte dekhi shune shuni '
  'hae haa kholo khulo jalao nivao nevao bondho bondo dio tay',
);

/// Frequent English words, so "I want chai" stays English.
final Set<String> _english = _words(
  'the a an is are am was were be been what how why who when where which '
  'you your i me my we our they he she it its to of and or in on at for '
  'with this that these those can could do does did please tell explain '
  'write give make about have has will would should there from not no yes '
  'hi hello hey thanks thank want need like know help some any all more '
  'if but so than then just also very good into by as show',
);

Set<String> _words(String spaced) => spaced.split(' ').toSet();
