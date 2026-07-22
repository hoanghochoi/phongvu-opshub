# OPS-11 VieNeu asset spike

This is build-time tooling. VieNeu and its model are not Flutter runtime
dependencies, and generated audio belongs under the ignored
`artifacts/ops-11-vieneu-spike/` directory until a reviewed pack is selected
for application packaging.

## Reproduce

Use Python 3.10 on Windows and install `requirements.txt` into an isolated
virtual environment. Download the exact model and codec revisions recorded in
`generate_vieneu_assets.py`, then run:

```powershell
python tool/payment_audio_spike/generate_vieneu_assets.py `
  --model-dir <v3-turbo-onnx-int8-directory> `
  --codec-dir <moss-codec-onnx-directory> `
  --output artifacts/ops-11-vieneu-spike/corpus-v3 `
  --scheme all --workers 4 --threads 2 --regenerate
```

To preserve the accepted v3 speech while changing only the standalone corpus
guards to 300 ms leading and 200 ms trailing, build a versioned v4 corpus:

```powershell
python tool/payment_audio_spike/generate_vieneu_assets.py `
  --migrate-from artifacts/ops-11-vieneu-spike/corpus-v3 `
  --output artifacts/ops-11-vieneu-spike/corpus-v4 `
  --scheme all
```

The migration does not run TTS or modify `corpus-v3`. Composition still keeps
30 ms at each asset edge with a 45 ms join gap, so A/B audio timing stays
unchanged. Voice samples remain on their existing 120 ms symmetric guards.

Generation writes source 48 kHz and package-candidate 24 kHz WAV files, a
hash/format manifest, compressed-size measurements, composition timing, QC
outliers, and a blind 15-amount A/B pack. To rebuild only reports from an
existing full corpus:

```powershell
python tool/payment_audio_spike/generate_vieneu_assets.py `
  --output artifacts/ops-11-vieneu-spike/corpus-v3 `
  --scheme all --postprocess-only
```

Generate current preset-voice candidates with:

```powershell
python tool/payment_audio_spike/generate_voice_samples.py `
  --model-dir <v3-turbo-onnx-int8-directory> `
  --codec-dir <moss-codec-onnx-directory> `
  --output artifacts/ops-11-vieneu-spike/corpus-v3-voice-samples
```

Generation is fail-closed: a rejected asset prevents the manifest and A/B pack
from being published. The 48 kHz and 24 kHz outputs contain exact zero boundary
guards; speech is resampled before the package guard is added, so resampler
ringing cannot contaminate the guard.

Validate the full generated deliverable with:

```powershell
python tool/payment_audio_spike/validate_vieneu_assets.py `
  --root artifacts/ops-11-vieneu-spike `
  --corpus-name corpus-v4 `
  --baseline-corpus-name corpus-v3 `
  --voice-corpus-name corpus-v3
```
