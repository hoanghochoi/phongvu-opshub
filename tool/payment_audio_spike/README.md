# OPS-11 Piper payment-number assets

This build-time tool generates the immutable Windows payment-number pack with
the same Piper `vi-vais1000` model and `piper-tts==1.4.2` version used by the
OpsHub production TTS sidecar. Piper and the model are not shipped in the
client; only the generated WAV files are packaged in the Windows installer.

Use Python 3.12 and an isolated virtual environment:

```powershell
python -m venv artifacts/ops-11-piper-local/venv
artifacts/ops-11-piper-local/venv/Scripts/python.exe -m pip install `
  -r tool/payment_audio_spike/requirements.txt
```

Copy `model.onnx` and `config.json` from the configured production model
directory into an ignored local artifact directory. The generator refuses to
run unless both SHA-256 checksums match the production pins recorded in source.

Generate to a new, empty ignored directory first:

```powershell
artifacts/ops-11-piper-local/venv/Scripts/python.exe `
  tool/payment_audio_spike/generate_piper_assets.py `
  --model artifacts/ops-11-piper-local/model/model.onnx `
  --config artifacts/ops-11-piper-local/model/config.json `
  --output artifacts/ops-11-piper-local/generated/piper_vi_vais1000_chunk_v1 `
  --speed 0.90
```

The output is exactly 1,103 PCM16 mono 24 kHz WAV files plus a manifest and
third-party notice. Every WAV has 300 ms leading silence and 200 ms trailing
silence. Run the fail-closed verifier before copying the generated directory to
`windows/assets/payment_audio/piper_vi_vais1000_chunk_v1/`.

The existing runtime cue `data/payment-cue-prefix.wav` is deliberately outside
this generator and must not be replaced by the OPS-11 number-pack workflow.
