# Organisation Multi-Agents — OpenClaw

> **Version** : 1.0 — 12 février 2026
> **Plateforme** : OpenClaw 2026.2.1 sur Azure VM (`vm-openclaw`)
> **APIM** : `apim-openclaw-0974.azure-api.net`

---

## Vue d'ensemble

```
                         ┌──────────────────┐
                         │    FLORENT       │
                         │    CEO / CFO     │
                         │    (Humain)      │
                         └────────┬─────────┘
                                  │ Telegram / Web UI
                         ┌────────▼─────────┐
                         │   🎩 JULES       │
                         │   Chief of Staff │
                         │   Agent #0       │
                         │   gpt-5.2        │
                         └────────┬─────────┘
                                  │ sessions_spawn
            ┌──────────┬──────────┼──────────┬──────────┐
            ▼          ▼          ▼          ▼          ▼
     ┌────────────┐┌────────┐┌────────┐┌─────────┐┌─────────┐
     │ 🔎 SCOUT  ││ ✍️ QUILL││ 🎬 STUDIO│ 🧠 CORINNE│
     │ Veille    ││ Rédac. ││ Créatif ││ Perso   │
     │ techno    ││        ││         ││         │
     │ gpt-5.2   ││gpt-5.2 ││gpt-5.2  ││gpt-5.2  │
     │ +web      ││        ││+sora-2  ││         │
     └────────────┘└────────┘└────────┘└─────────┘└─────────┘
```

---

## Agents — Fiches détaillées

### 🎩 Jules — Chief of Staff (Agent par défaut)

| Propriété | Valeur |
|-----------|--------|
| **ID** | `main` (agent par défaut) |
| **Identité** | Jules |
| **Rôle** | Orchestrateur principal. Reçoit toutes les requêtes, analyse, délègue aux agents spécialisés via `sessions_spawn`, synthétise les résultats. |
| **Modèle** | `azure-apim-gpt5/gpt-5.2` (256K contexte, 64K output) |
| **Workspace** | `~/.openclaw/workspace/` |
| **Skills** | twitter-reader, yt-dlp-downloader-skill, yt_fr_dub |
| **Spawn autorisés** | scout, corinne, quill, studio |
| **Cron** | veille-genai (hérité, tourne sur isolated session Scout) |
| **Canal** | Telegram (DM par défaut), Web UI |

**Thème (system prompt)** :
> Tu es Jules, Chief of Staff. Tu orchestres l'équipe d'agents, tu délègues les tâches aux spécialistes (Scout pour la veille, Quill pour la rédaction, Studio pour le créatif, Dev pour le code). Tu synthétises les résultats et tu communiques avec clarté.

---

### 🔎 Scout — Veille Technologique

| Propriété | Valeur |
|-----------|--------|
| **ID** | `scout` |
| **Identité** | Scout |
| **Rôle** | Agent de veille technologique. Spécialité principale : Generative AI. Peut couvrir tout sujet tech sur demande. |
| **Modèle** | `azure-apim-gpt5/gpt-5.2` |
| **Workspace** | `~/.openclaw/workspace-scout/` |
| **Skills** | veille-genai, veille-techno, twitter-reader |
| **Outils** | Web Search (Bing via azure-responses) |
| **Cron** | `0 7,13,19 * * *` Europe/Paris → veille GenAI automatique 3x/jour |
| **Delivery** | Telegram vers `8489986766` (Florent) |

**Skills détaillés** :

| Skill | Type | Description |
|-------|------|-------------|
| `veille-genai` | Cron + demande | Veille GenAI structurée. Sources Twitter Tier 1-3 + recherches web Bing. Résumé en français avec sections (Annonces, Recherche, Entreprises, Régulation). |
| `veille-techno` | Demande uniquement | Template de veille généraliste. Accepte un sujet libre (edge computing, quantum, cybersécurité, etc.). Même format de sortie que veille-genai. |
| `twitter-reader` | Outil | Lecture de profils, tweets et timelines Twitter/X via API publique (Syndication + FxTwitter). |

**Fonctionnement dual** :
- **Automatique (cron)** : 3x/jour à 7h, 13h, 19h — veille GenAI uniquement, livrée sur Telegram
- **À la demande** : Jules peut spawner Scout pour n'importe quel sujet tech via le skill `veille-techno`

---

### ✍️ Quill — Rédaction & Contenu

| Propriété | Valeur |
|-----------|--------|
| **ID** | `quill` |
| **Identité** | Quill |
| **Rôle** | Agent de rédaction. Produit des posts LinkedIn, articles, synthèses, comptes-rendus, documentation. |
| **Modèle** | `azure-apim-gpt5/gpt-5.2` |
| **Workspace** | `~/.openclaw/workspace-quill/` |
| **Skills** | redaction |
| **Cron** | Aucun |

**Skill détaillé** :

| Skill | Description |
|-------|-------------|
| `redaction` | Rédaction professionnelle multi-format. Supporte : post LinkedIn, article de blog, synthèse executive, compte-rendu de réunion, documentation technique. Ton professionnel, structuré, en français. |

---

### 🎬 Studio — Création Média

| Propriété | Valeur |
|-----------|--------|
| **ID** | `studio` |
| **Identité** | Studio |
| **Rôle** | Agent créatif. Génération vidéo (Sora 2), doublage/traduction vidéo (yt_fr_dub), production multimédia. |
| **Modèle** | `azure-apim-gpt5/gpt-5.2` |
| **Workspace** | `~/.openclaw/workspace-studio/` |
| **Skills** | studio-video, yt_fr_dub |
| **Accès APIM** | Sora 2 (`azure-apim-sora/sora-2`) via `/videos/generations` |
| **Cron** | Aucun |

**Skills détaillés** :

| Skill | Description |
|-------|-------------|
| `studio-video` | Génération de vidéos via Sora 2 (API Azure APIM). Prompt texte ou image → vidéo. |
| `yt_fr_dub` | Doublage français de vidéos YouTube. Pipeline : download → transcription (GPT-4o-Transcribe) → traduction → TTS → mixage → upload Azure Blob. |

**Modèles utilisés** :

| Modèle | Provider OpenClaw | Usage |
|--------|-------------------|-------|
| Sora 2 | `azure-apim-sora/sora-2` | Génération vidéo |
| GPT-4o-Transcribe | `azure-apim-transcribe/gpt-4o-transcribe` | Transcription audio |
| GPT-4o-Audio-Preview | `azure-apim-audio/gpt-4o-audio-preview` | TTS / conversation audio |

---

### 🧠 Corinne — Assistante Personnelle

| Propriété | Valeur |
|-----------|--------|
| **ID** | `corinne` |
| **Identité** | Mnemo |
| **Rôle** | Assistante personnelle de Corinne. Canal Telegram dédié, conversations privées. |
| **Modèle** | `azure-apim-gpt5/gpt-5.2` (défaut) |
| **Workspace** | `~/.openclaw/workspace-corinne/` |
| **Skills** | yt_fr_dub, yt_fr_dub_postupload |
| **Binding** | Telegram DM `8494122135` → routage automatique vers cet agent |
| **Cron** | Aucun |

**Particularité** : Corinne est liée par un **binding** Telegram. Tout message DM du numéro `8494122135` est automatiquement routé vers cet agent, sans passer par Jules.

---

## Infrastructure

### Modèles APIM disponibles

| Modèle | Provider | Endpoint | Usage principal |
|--------|----------|----------|-----------------|
| GPT-5.2 | `azure-apim-gpt5` | `/chat/completions` | Tous agents (par défaut) |
| GPT-5.2-Codex | `azure-apim-gpt5-codex` | `/chat/completions` | Dev (code generation) |
| Text-Embedding-3-Small | `azure-apim-embeddings` | `/embeddings` | Mémoire, semantic search |
| GPT-4o-Transcribe | `azure-apim-transcribe` | `/audio/transcriptions` | Studio (transcription) |
| GPT-4o-Audio-Preview | `azure-apim-audio` | `/chat/completions` | Studio (TTS) |
| Sora 2 | `azure-apim-sora` | `/videos/generations` | Studio (vidéo) |
| GPT-4.1 | `azure-responses` | Web Search (Bing grounding) | Scout, Jules (recherche web) |

### Services système

| Service | Type | Fichier | Port |
|---------|------|---------|------|
| OpenClaw Gateway | systemd user | `~/.config/systemd/user/openclaw-gateway.service` | 18789 |

**Commandes de gestion** :
```bash
# Status
systemctl --user status openclaw-gateway.service

# Restart (recharge la config)
systemctl --user restart openclaw-gateway.service

# Logs
journalctl --user -u openclaw-gateway.service -f

# Stop
systemctl --user stop openclaw-gateway.service
```

> **Note** : Le service system `/etc/systemd/system/openclaw.service` a été **désactivé** pour éviter un conflit de double démarrage. Seul le user service est actif.

### Canaux de communication

| Canal | Configuration |
|-------|--------------|
| **Telegram** | Bot `@ChanelMnemoBot` — token `8355153614:AAH...` |
| **Web UI** | `http://localhost:18789` (auth token) |

### Mécanismes inter-agents

| Mécanisme | Description | Utilisé par |
|-----------|-------------|-------------|
| `sessions_spawn` | Délégation asynchrone. Jules crée une session isolée pour un agent spécialisé avec un prompt et attend le résultat. | Jules → Scout, Quill, Studio |
| `sessions_send` | Ping-pong synchrone entre agents. Messages bidirectionnels dans une session partagée. | Jules ↔ Corinne |
| `bindings` | Routage statique. Les messages Telegram de Corinne sont automatiquement dirigés vers l'agent Corinne. | Telegram → Corinne |
| `cron` | Tâches planifiées. Sessions isolées déclenchées par un scheduler avec delivery Telegram. | Scout (veille 3x/jour) |

---

## Flux de travail

### Veille automatique (3x/jour)
```
Cron 7h/13h/19h
    → Session isolée (Scout)
    → Lit Twitter Tier 1-3
    → Recherche web Bing
    → Synthèse structurée FR
    → Delivery Telegram (Florent)
```

### Rédaction LinkedIn (à la demande)
```
Florent → Jules : "écris un post LinkedIn sur [sujet]"
    → Jules spawn Quill
    → Quill rédige (skill redaction)
    → Résultat retourné à Jules
    → Jules transmet à Florent
```

### Traduction vidéo (à la demande)
```
Florent → Jules : "traduis cette vidéo YouTube en FR"
    → Jules spawn Studio (ou Corinne si DM)
    → Studio exécute yt_fr_dub
    → Vidéo uploadée Azure Blob
    → Lien SAS retourné
```

### Génération vidéo (à la demande)
```
Florent → Jules : "génère une vidéo de [description]"
    → Jules spawn Studio
    → Studio appelle Sora 2 via APIM
    → Vidéo générée et retournée
```

---

## Arborescence des workspaces

```
~/.openclaw/
├── openclaw.json                    ← Configuration principale
├── cron/
│   └── jobs.json                    ← Jobs cron (veille-genai)
├── workspace/                       ← Jules (main)
│   └── skills/
│       ├── twitter-reader/          → symlink
│       ├── yt-dlp-downloader-skill/
│       └── yt_fr_dub/
├── workspace-scout/                 ← Scout
│   └── skills/
│       ├── twitter-reader/          → symlink
│       ├── veille-genai/
│       └── veille-techno/
├── workspace-quill/                 ← Quill
│   └── skills/
│       └── redaction/
├── workspace-studio/                ← Studio
│   └── skills/
│       ├── studio-video/
│       └── yt_fr_dub/               → symlink
└── workspace-corinne/               ← Corinne
    └── skills/
        ├── yt_fr_dub/               → symlink
        └── yt_fr_dub_postupload/
```

---

## Évolutions prévues

| Agent | Évolution | Priorité |
|-------|-----------|----------|
| **Dev** | Agent engineering avec GPT-5.2-Codex (code, debug, architecture) | Prochaine |
| **Scout** | Ajout de sources RSS, newsletters, ArXiv | Moyenne |
| **Studio** | Intégration DALL-E / Flux pour images | Basse |
| **Quill** | Templates Twitter/X, newsletter | Moyenne |
| **Jules** | Memory long-terme, résumés de sessions | Haute |

---

*Document généré le 12 février 2026*
