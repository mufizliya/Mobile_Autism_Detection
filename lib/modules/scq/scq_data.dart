class ScqData {
  static const int threshold = 15;

  static const List<String> questions = [
    "Is she/he now able to talk using short phrases or sentences?",
    "Can you have a to-and-fro \"conversation\" with her/him that involves taking turns or building on what she/he has said?",
    "Does she/he ever use gestures to indicate interest in something?",
    "Does she/he ever point to express interest in something?",
    "Does she/he ever bring objects over to show you something?",
    "Does she/he look you in the eye when talking to you?",
    "Does she/he ever seem overly sensitive to noise?",
    "Does she/he respond when you call her/his name?",
    "Does she/he smile back when someone smiles at her/him?",
    "Does she/he ever show interest in other children her/his age?",
    "Does she/he ever engage in \"pretend\" or \"make-believe\" play?",
    "Does she/he ever use her/his index finger to point, to ask for something?",
    "Does she/he ever use her/his index finger to point, to indicate interest in something?",
    "Can she/he play appropriately with small toys (cars, dolls, building blocks) without just mouthing, fiddling, or dropping them?",
    "Does she/he ever pretend objects are something else? (e.g., cup as a telephone)",
    "Does she/he ever imitate you?",
    "Does she/he ever imitate other children?",
    "Does she/he respond positively when others approach her/him?",
    "Does she/he try to comfort someone who is hurt or upset?",
    "Does she/he enjoy being held or cuddled?",
    "Does she/he get affected by unusual or unexpected noises?",
    "Does she/he have any unusual preoccupations?",
    "Does she/he have any compulsive or repetitive behaviors?",
    "Does she/he ever injure herself deliberately (e.g., biting, banging head)?",
    "Does she/he have any unusual sensory interests (e.g., sniffing objects)?",
    "Does she/he display complex body movements (e.g., hand flapping)?",
    "Does she/he ever repeat things that you or others have said (echolalia)?",
    "Does she/he ever use stereotyped or repetitive speech?",
    "Does she/he have difficulty with changes in routine or surroundings?",
    "Does she/he have any special interests or hobbies?",
    "Does she/he ever seem to be in a world of her/his own?",
    "Does she/he ever become excessively distressed for no apparent reason?",
    "Does she/he have difficulty understanding other people's feelings?",
    "Does she/he ever laugh or giggle inappropriately?",
    "Does she/he ever make unusual facial expressions?",
    "Does she/he ever look at things from unusual angles?",
    "Does she/he ever have any strange or unusual interests?",
    "Has she/he ever seemed uninterested in interacting with you?",
    "Does she/he tend to walk on her/his toes?",
    "Does she/he have any unusual fears or anxieties?",
  ];

  static const List<String> autismResponses = [
    "No", "No", "No", "No", "No", "No",
    "Yes", "No", "No", "No",
    "No", "No", "No", "No", "No",
    "No", "No", "No", "No", "No",
    "Yes", "Yes", "Yes", "Yes", "Yes",
    "Yes", "Yes", "Yes", "Yes",
    "Yes", "Yes", "Yes", "Yes", "Yes",
    "Yes", "Yes", "Yes", "Yes",
    "Yes", "Yes",
  ];

  static const Map<String, List<int>> phenotypeMap = {
    "social_communication": [
      1, 2, 3, 4, 5, 6, 8, 9, 10,
      11, 12, 13, 15, 16, 17, 18,
      19, 33, 38,
    ],
    "sensory_sensitivity": [
      7, 21, 25, 36,
    ],
    "repetitive_behavior": [
      22, 23, 24, 26, 27, 28,
      29, 30, 39,
    ],
    "emotional_regulation": [
      31, 32, 34, 40,
    ],
    "motor_behavior": [
      26, 39,
    ],
  };

  static int calculateScore(
    Map<String, String> answers,
  ) {
    int score = 0;

    for (int i = 0; i < questions.length; i++) {
      final String questionKey = 'Q${i + 1}';
      final String? response = answers[questionKey];

      if (response == autismResponses[i]) {
        score += 1;
      }
    }

    return score;
  }

  static Map<String, dynamic> calculatePhenotypes(
    Map<String, String> answers,
  ) {
    final Map<String, dynamic> phenotypeScores = {};

    for (final MapEntry<String, List<int>> entry in phenotypeMap.entries) {
      int rawScore = 0;

      for (final int questionIndex in entry.value) {
        final String questionKey = 'Q$questionIndex';
        final String? response = answers[questionKey];
        final String autismResponse = autismResponses[questionIndex - 1];

        if (response == autismResponse) {
          rawScore += 1;
        }
      }

      final int maxScore = entry.value.length;
      final double severity = double.parse(
        (rawScore / maxScore).toStringAsFixed(2),
      );

      phenotypeScores[entry.key] = {
        "raw_score": rawScore,
        "max_score": maxScore,
        "severity": severity,
      };
    }

    return phenotypeScores;
  }
}