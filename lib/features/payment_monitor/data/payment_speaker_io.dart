import 'dart:io';

class PaymentSpeaker {
  Future<void> speakAmount(int amount) async {
    if (!Platform.isWindows) return;
    final script = r'''
& {
param($amount)
Add-Type -AssemblyName System.Speech
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speaker.Rate = 0
$speaker.Volume = 100
$speaker.Speak("Đã nhận $amount đồng")
}
''';
    await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
      amount.toString(),
    ], runInShell: false);
  }
}
