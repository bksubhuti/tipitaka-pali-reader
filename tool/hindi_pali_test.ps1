# Speaks Pali in Devanagari with the Windows Hindi voice, the way the app
# does, in several spellings, to hear which keeps the short a.
# Run in PowerShell:  powershell -ExecutionPolicy Bypass -File hindi_pali_test.ps1
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await($op, [Type]$type) {
  $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
  $task.Wait(-1) | Out-Null
  $task.Result
}
[Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime] | Out-Null
$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices |
  Where-Object { $_.Language -eq 'hi-IN' } | Select-Object -First 1
if (-not $voice) { Write-Host 'No Hindi voice found.'; exit 1 }
$synth.Voice = $voice
Write-Host "Voice: $($voice.DisplayName)"
$wav = Join-Path $env:TEMP 'hindi_pali_test.wav'
function Say([string]$text) {
  $stream = Await ($synth.SynthesizeTextToStreamAsync($text)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
  $in = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
  $out = [System.IO.File]::Create($wav)
  $in.CopyTo($out); $out.Close(); $in.Close()
  (New-Object System.Media.SoundPlayer $wav).PlaySync()
}
$tests = @(
  @('Line 1, 1 as now', 'एवं मे सुतं – एकं समयं भगवा सावत्थियं विहरति जेतवने अनाथपिण्डिकस्स आरामे।'),
  @('Line 1, 2 word ends spelled out', 'एवं मे सुतं – एकं समयं भगवा सावत्थियं विहरति जेतवने अनाथपिण्डिकस्स्अ आरामे।'),
  @('Line 1, 3 every short a spelled out', 'एव्अं मे सुत्अं – एक्अं स्अम्अय्अं भ्अग्अवा साव्अत्थिय्अं विह्अर्अति जेत्अव्अने अनाथ्अपिण्डिक्अस्स्अ आरामे।'),
  @('Line 1, 4 avagraha at word ends', 'एवं मे सुतं – एकं समयं भगवा सावत्थियं विहरति जेतवने अनाथपिण्डिकस्सऽ आरामे।'),
  @('Line 1, 5 only where Hindi drops it', 'एवं मे सुतं – एकं सम्अयं भग्अवा साव्अत्थियं विह्अर्अति जेत्अव्अने अनाथ्अपिण्डिक्अस्स्अ आरामे।'),
  @('Line 2, 1 as now', 'नमो तस्स भगवतो अरहतो सम्मासम्बुद्धस्स।'),
  @('Line 2, 2 word ends spelled out', 'नमो तस्स्अ भगवतो अरहतो सम्मासम्बुद्धस्स।'),
  @('Line 2, 3 every short a spelled out', 'न्अमो त्अस्स्अ भ्अग्अव्अतो अर्अह्अतो स्अम्मास्अम्बुद्ध्अस्स्अ।'),
  @('Line 2, 4 avagraha at word ends', 'नमो तस्सऽ भगवतो अरहतो सम्मासम्बुद्धस्स।'),
  @('Line 2, 5 only where Hindi drops it', 'नमो तस्स्अ भग्अव्अतो अर्अह्अतो सम्मास्अम्बुद्ध्अस्स्अ।'),
  @('Line 3, 1 as now', 'बुद्धं सरणं गच्छामि। धम्मं सरणं गच्छामि। सङ्घं सरणं गच्छामि।'),
  @('Line 3, 2 word ends spelled out', 'बुद्धं सरणं गच्छामि। धम्मं सरणं गच्छामि। सङ्घं सरणं गच्छामि।'),
  @('Line 3, 3 every short a spelled out', 'बुद्ध्अं स्अर्अण्अं ग्अच्छामि। ध्अम्म्अं स्अर्अण्अं ग्अच्छामि। स्अङ्घ्अं स्अर्अण्अं ग्अच्छामि।'),
  @('Line 3, 4 avagraha at word ends', 'बुद्धं सरणं गच्छामि। धम्मं सरणं गच्छामि। सङ्घं सरणं गच्छामि।'),
  @('Line 3, 5 only where Hindi drops it', 'बुद्धं सर्अणं गच्छामि। धम्मं सर्अणं गच्छामि। सङ्घं सर्अणं गच्छामि।')
)
foreach ($t in $tests) {
  Write-Host ''
  Write-Host $t[0]
  Write-Host $t[1]
  Say $t[1]
  Start-Sleep -Milliseconds 700
}
