import '../companion/companion_response.dart';
import '../companion/companion_response_builder.dart';
import 'voice_command.dart';
import 'voice_command_parser.dart';
import 'voice_result.dart';

class VoiceInteraction {
  const VoiceInteraction({
    required this.result,
    required this.command,
    required this.response,
  });

  final VoiceRecognitionResult result;
  final VoiceCommand command;
  final CompanionResponse response;

  bool get shouldRunAction => command.isActionable;
}

class VoiceInteractionController {
  const VoiceInteractionController({
    this.parser = const VoiceCommandParser(),
    this.responseBuilder = const CompanionResponseBuilder(),
  });

  final VoiceCommandParser parser;
  final CompanionResponseBuilder responseBuilder;

  VoiceInteraction handle(VoiceRecognitionResult result) {
    final command = parser.parse(result);
    final response = responseBuilder.fromVoiceCommand(command);

    return VoiceInteraction(
      result: result,
      command: command,
      response: response,
    );
  }
}
