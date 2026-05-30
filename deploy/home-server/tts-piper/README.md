# OpsHub Piper TTS Sidecar

Lightweight payment-notification TTS service for the home-server deployment. It
keeps the existing OpsHub TTS contract (`POST /synthesize`) while replacing the
VieNeu runtime with Piper `vi-vais1000`.

## Runtime Contract

- `POST /synthesize` accepts the existing backend payload: `text`, `format`,
  `voice_id`, `speed`, `pitch`, and `voice_index`.
- The service always returns `audio/wav`; the Windows app already detects and
  plays WAV files.
- `speed` maps to Piper `length_scale = 1 / speed`.
- `pitch` is accepted for compatibility but ignored in v1.
- Supported voice ids are `piper:vi-vais1000`, `custom:suong-vo`, and
  `builtin:0`; unknown values fall back to the default voice.

## VPS Install

Run on `hoang-n8n` after copying this folder to `/opt/opshub-piper-tts`:

```bash
sudo install -d -o ubuntu -g ubuntu /opt/opshub-piper-tts/models/vi-vais1000
cd /opt/opshub-piper-tts
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
curl -fL --retry 3 -o models/vi-vais1000/model.onnx \
  https://huggingface.co/nrl-ai/edgevox-models/resolve/main/piper/vi-vais1000/model.onnx
curl -fL --retry 3 -o models/vi-vais1000/config.json \
  https://huggingface.co/nrl-ai/edgevox-models/resolve/main/piper/vi-vais1000/config.json
cp models/vi-vais1000/config.json models/vi-vais1000/model.onnx.json
sudo cp opshub-piper-tts.service /etc/systemd/system/opshub-piper-tts.service
sudo systemctl daemon-reload
sudo systemctl enable --now opshub-piper-tts.service
sudo ufw allow from 172.20.0.0/16 to 172.20.0.1 port 18081 proto tcp \
  comment 'OpsHub Piper TTS from docker'
```

Smoke test without touching VieNeu:

```bash
curl -fsS http://172.20.0.1:18081/health
curl -fsS -X POST http://172.20.0.1:18081/synthesize \
  -H 'Content-Type: application/json' \
  --data '{"text":"Phong Vu da nhan: mot trieu dong.","format":"mp3","voice_id":"custom:suong-vo","speed":0.90,"pitch":1.0}' \
  -D /tmp/piper.headers -o /tmp/piper-payment.wav
file /tmp/piper-payment.wav
```

Switch OpsHub after the smoke test passes:

```bash
# In /srv/opshub/env
TTS_SERVICE_URL=http://172.20.0.1:18081
TTS_VOICE_ID=piper:vi-vais1000
TTS_SPEED=0.90

cd /home/ubuntu/phongvu-opshub/current
OPSHUB_ENV_FILE=/srv/opshub/env docker compose --env-file /srv/opshub/env \
  -f deploy/home-server/docker-compose.home.yml up -d --force-recreate api
```

Keep `opshub-vieneu-tts.service` running until payment audio is verified through
OpsHub. Rollback is changing `TTS_SERVICE_URL` back to `http://172.20.0.1:18080`
and recreating the API container.
