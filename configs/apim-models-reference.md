# OpenClaw Azure APIM - Modèles Disponibles

## Configuration APIM

| Paramètre | Valeur |
|-----------|--------|
| **APIM Endpoint** | `https://apim-openclaw-0974.azure-api.net` |
| **Subscription Key** | `f912e4b174d645aabe927e80f9992ff6` |
| **API Version** | `2024-10-21` |
| **Backend AI Foundry** | `admin-0508-resource` (rg-admin-0508) |

---

## Modèles Chat/Completions

### GPT-5.2
| Paramètre | Valeur |
|-----------|--------|
| **Provider OpenClaw** | `azure-apim-gpt5` |
| **Model ID** | `gpt-5.2` |
| **Nom complet** | `azure-apim-gpt5/gpt-5.2` |
| **URL APIM** | `https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-5.2` |
| **Endpoint** | `/chat/completions` |
| **Context Window** | 256,000 tokens |
| **Max Output** | 64,000 tokens |
| **Input** | text, image |

```bash
# Test curl
curl -s "https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-5.2/chat/completions?api-version=2024-10-21" \
  -H "api-key: f912e4b174d645aabe927e80f9992ff6" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"max_completion_tokens":50}'
```

---

### GPT-5.2-Codex
| Paramètre | Valeur |
|-----------|--------|
| **Provider OpenClaw** | `azure-apim-gpt5-codex` |
| **Model ID** | `gpt-5.2-codex` |
| **Nom complet** | `azure-apim-gpt5-codex/gpt-5.2-codex` |
| **URL APIM** | `https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-5.2-codex` |
| **Endpoint** | `/chat/completions` |
| **Context Window** | 256,000 tokens |
| **Max Output** | 64,000 tokens |
| **Input** | text |
| **Use Case** | Code generation, refactoring |

```bash
# Test curl
curl -s "https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-5.2-codex/chat/completions?api-version=2024-10-21" \
  -H "api-key: f912e4b174d645aabe927e80f9992ff6" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Write a Python hello world"}],"max_completion_tokens":100}'
```

---

## Modèles Embeddings

### Text-Embedding-3-Small
| Paramètre | Valeur |
|-----------|--------|
| **Provider OpenClaw** | `azure-apim-embeddings` |
| **Model ID** | `text-embedding-3-small` |
| **Nom complet** | `azure-apim-embeddings/text-embedding-3-small` |
| **URL APIM** | `https://apim-openclaw-0974.azure-api.net/openai/deployments/text-embedding-3-small` |
| **Endpoint** | `/embeddings` |
| **Dimensions** | 1536 |
| **Use Case** | Mémoire OpenClaw, recherche sémantique |

```bash
# Test curl
curl -s "https://apim-openclaw-0974.azure-api.net/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-10-21" \
  -H "api-key: f912e4b174d645aabe927e80f9992ff6" \
  -H "Content-Type: application/json" \
  -d '{"input":"Test embedding for memory"}'
```

---

## Modèles Audio

### GPT-4o-Transcribe
| Paramètre | Valeur |
|-----------|--------|
| **Provider OpenClaw** | `azure-apim-transcribe` |
| **Model ID** | `gpt-4o-transcribe` |
| **Nom complet** | `azure-apim-transcribe/gpt-4o-transcribe` |
| **URL APIM** | `https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-4o-transcribe` |
| **Endpoint** | `/audio/transcriptions` |
| **Input** | audio (mp3, wav, m4a, etc.) |
| **Use Case** | Transcription audio/vidéo, traduction vidéo |

```bash
# Test curl (avec fichier audio)
curl -s "https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-4o-transcribe/audio/transcriptions?api-version=2024-10-21" \
  -H "api-key: f912e4b174d645aabe927e80f9992ff6" \
  -F "file=@audio.mp3" \
  -F "model=gpt-4o-transcribe"
```

---

### GPT-4o-Audio-Preview
| Paramètre | Valeur |
|-----------|--------|
| **Provider OpenClaw** | `azure-apim-audio` |
| **Model ID** | `gpt-4o-audio-preview` |
| **Nom complet** | `azure-apim-audio/gpt-4o-audio-preview` |
| **URL APIM** | `https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-4o-audio-preview` |
| **Input** | audio, text |
| **Output** | audio, text |
| **Use Case** | Conversation audio, TTS |

---

## Modèles Vidéo

### Sora-2
| Paramètre | Valeur |
|-----------|--------|
| **Provider OpenClaw** | `azure-apim-sora` |
| **Model ID** | `sora-2` |
| **Nom complet** | `azure-apim-sora/sora-2` |
| **URL APIM** | `https://apim-openclaw-0974.azure-api.net/openai/deployments/sora-2` |
| **Endpoint** | `/videos/generations` |
| **Input** | text, image |
| **Output** | video |
| **Use Case** | Génération vidéo à partir de prompts |

---

## Configuration OpenClaw Complète

Fichier `~/.openclaw/settings.json` :

```json
{
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "openclaw-azure-2026"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": {
        "primary": "azure-apim-gpt5/gpt-5.2"
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "azure-apim-gpt5": {
        "baseUrl": "https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-5.2",
        "apiKey": "f912e4b174d645aabe927e80f9992ff6",
        "api": "openai-completions",
        "models": [{"id": "gpt-5.2", "name": "GPT 5.2", "contextWindow": 256000, "maxTokens": 64000}]
      },
      "azure-apim-gpt5-codex": {
        "baseUrl": "https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-5.2-codex",
        "apiKey": "f912e4b174d645aabe927e80f9992ff6",
        "api": "openai-completions",
        "models": [{"id": "gpt-5.2-codex", "name": "GPT 5.2 Codex", "contextWindow": 256000, "maxTokens": 64000}]
      },
      "azure-apim-embeddings": {
        "baseUrl": "https://apim-openclaw-0974.azure-api.net/openai/deployments/text-embedding-3-small",
        "apiKey": "f912e4b174d645aabe927e80f9992ff6",
        "api": "openai-embeddings",
        "models": [{"id": "text-embedding-3-small", "name": "Text Embedding 3 Small", "dimensions": 1536}]
      },
      "azure-apim-transcribe": {
        "baseUrl": "https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-4o-transcribe",
        "apiKey": "f912e4b174d645aabe927e80f9992ff6",
        "api": "openai-audio",
        "models": [{"id": "gpt-4o-transcribe", "name": "GPT-4o Transcribe"}]
      },
      "azure-apim-audio": {
        "baseUrl": "https://apim-openclaw-0974.azure-api.net/openai/deployments/gpt-4o-audio-preview",
        "apiKey": "f912e4b174d645aabe927e80f9992ff6",
        "api": "openai-audio",
        "models": [{"id": "gpt-4o-audio-preview", "name": "GPT-4o Audio Preview"}]
      },
      "azure-apim-sora": {
        "baseUrl": "https://apim-openclaw-0974.azure-api.net/openai/deployments/sora-2",
        "apiKey": "f912e4b174d645aabe927e80f9992ff6",
        "api": "openai-video",
        "models": [{"id": "sora-2", "name": "Sora 2"}]
      }
    }
  },
  "memory": {
    "enabled": true,
    "provider": "azure-apim-embeddings",
    "model": "text-embedding-3-small"
  }
}
```

---

## Résumé Rapide

| Modèle | Provider | Nom Complet | Use Case |
|--------|----------|-------------|----------|
| gpt-5.2 | azure-apim-gpt5 | `azure-apim-gpt5/gpt-5.2` | Chat principal |
| gpt-5.2-codex | azure-apim-gpt5-codex | `azure-apim-gpt5-codex/gpt-5.2-codex` | Code |
| text-embedding-3-small | azure-apim-embeddings | `azure-apim-embeddings/text-embedding-3-small` | Mémoire |
| gpt-4o-transcribe | azure-apim-transcribe | `azure-apim-transcribe/gpt-4o-transcribe` | Transcription |
| gpt-4o-audio-preview | azure-apim-audio | `azure-apim-audio/gpt-4o-audio-preview` | Audio |
| sora-2 | azure-apim-sora | `azure-apim-sora/sora-2` | Vidéo |

---

*Généré le 2026-02-04*
