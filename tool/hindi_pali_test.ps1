# Speaks Pali in Devanagari with the Windows Hindi voice, the way the app
# does, in several spellings, to hear which reads it best.
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
  @('1 plain', 'मञ्ञति। पञ्ञा। धम्मं। सम्मा। अत्तनो। भगवा।'),
  @('2 as the app does now', 'म्अञ्ञ्अति। प्अञ्ञा। ध्अम्म्अं। स्अम्मा। अत्त्अनो। भ्अग्अवा।'),
  @('3 no separate a before a double consonant', 'मञ्ञ्अति। पञ्ञा। धम्म्अं। सम्मा। अत्त्अनो। भ्अग्अवा।')
)
foreach ($t in $tests) {
  Write-Host ''
  Write-Host $t[0]
  Write-Host $t[1]
  Say $t[1]
  Start-Sleep -Milliseconds 700
}
