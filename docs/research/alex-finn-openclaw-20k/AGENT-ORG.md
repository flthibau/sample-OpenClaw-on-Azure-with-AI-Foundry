# Modélisation — Organisation d'agents IA (Alex Finn)

## Comment reproduire cela avec OpenClaw

Ce document modélise l'organisation d'agents d'Alex Finn et propose comment
la reproduire avec notre setup OpenClaw existant.

---

## 1. Architecture générale

```
┌─────────────────────────────────────────────────────────┐
│                    COUCHE VISUALISATION                  │
│         Interface visuelle (origine incertaine)          │
│     Agents animés, bureau virtuel, interactions          │
│     Possiblement : natif OpenClaw, AI Town, ou custom    │
│     Agents marchent, se réunissent, water cooler         │
└──────────────────────┬──────────────────────────────────┘
                       │ Events / API
┌──────────────────────▼──────────────────────────────────┐
│                   COUCHE ORCHESTRATION                   │
│                      OpenClaw                            │
│  • Gateway (routage des messages entre agents)           │
│  • Skills (actions exécutables)                          │
│  • Canaux (Telegram, Slack, Discord, etc.)               │
│  • Mémoire (context, memories, relationships)            │
│  • Scheduling (cron-like pour tâches 24/7)               │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
┌───────────┐  ┌───────────┐  ┌───────────┐
│  CLOUD    │  │  LOCAL     │  │  LOCAL     │
│  MODELS   │  │  LLM       │  │  IMAGE     │
│           │  │            │  │            │
│ GPT-5.2   │  │ Kimi K2.5  │  │ Flux 2     │
│ Opus 4.5  │  │ GLM 4.7    │  │ SDXL       │
│           │  │ Llama      │  │            │
│ via APIM  │  │ via Ollama │  │ via ComfyUI│
└───────────┘  └───────────┘  └───────────┘
```

---

## 2. Organisation des agents d'Alex Finn

### Organigramme détaillé

```
                         ┌──────────────┐
                         │  ALEX FINN   │
                         │     CEO      │
                         │  (Humain)    │
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │   HENRY      │
                         │ Chief of     │
                         │ Staff        │
                         ├──────────────┤
                         │ Opus 4.5 ☁️  │
                         │ Rôle: Décide │
                         │ ~5 prompts/j │
                         └──────┬───────┘
                                │
           ┌────────────────────┼────────────────────┐
           │                    │                    │
    ┌──────▼───────┐    ┌──────▼───────┐    ┌──────▼───────┐
    │   SCOUT      │    │   QUILL      │    │  DEV AGENT   │
    │  Analyste    │    │  Créatif     │    │  Ingénieur   │
    ├──────────────┤    ├──────────────┤    ├──────────────┤
    │ GLM 4.7 🖥️   │    │ Local LLM 🖥️ │    │ Local LLM 🖥️ │
    │ 24/7 Reddit  │    │ Tweets,      │    │ Code apps    │
    │ 24/7 Twitter │    │ scripts,     │    │ Ship Vercel  │
    │ Détecte      │    │ contenu      │    │ Bug fixes    │
    │ problèmes    │    │              │    │              │
    └──────────────┘    └──────────────┘    └──────────────┘
           │
    ┌──────▼───────┐
    │ CREATIVE     │
    │ Agent Image  │
    ├──────────────┤
    │ Flux 2 🖥️    │
    │ Thumbnails   │
    │ Images social│
    └──────────────┘
```

### Interactions entre agents

```
Scout ──"challenge trouvé"──→ Henry ──"approuvé"──→ Dev Agent ──"app live"──→ Scout ──"DM poster"
  ↑                                                                              │
  └──────────────────────── boucle continue 24/7 ◄────────────────────────────────┘

Quill ←──"ton tweet a bien marché"──── Scout (feedback Twitter analytics)
  │
  └──→ mémorise le style qui fonctionne → écrit mieux la prochaine fois

Tous ──→ Roundtable (réunion périodique) ──→ brainstorm features ──→ Henry décide
```

---

## 3. Notre setup actuel vs Alex Finn

| Aspect | Alex Finn | Notre OpenClaw | Gap |
|---|---|---|---|
| **Orchestration** | OpenClaw | OpenClaw ✅ | Aucun |
| **Agent principal** | Henry (Opus 4.5) | Mnemo (GPT-5.2 via APIM) | ≈ Équivalent ✅ |
| **Multi-agent** | main + corinne + agents locaux | main + corinne | Ajouter des agents spécialisés |
| **Modèles locaux** | Kimi K2.5, GLM 4.7, Flux 2 | Aucun | **Gap majeur** — besoin Ollama |
| **24/7 autonome** | Oui (local = gratuit) | Non (cloud = coûteux) | Besoin modèles locaux |
| **Visualisation** | Interface visuelle (origine inconnue) | Dashboard OpenClaw | À investiguer |
| **Skills** | Reddit scraper, Vercel deploy, YouTube, etc. | yt_fr_dub, yt-dlp | Ajouter des skills |
| **Mémoire agents** | Personnalités, relations, insights | Mémoire OpenClaw standard | Enrichir |
| **Hardware** | 2x Mac Studio M3 Ultra (1 To) | 1x VM Azure | Ajout hardware local possible |

---

## 4. Plan pour reproduire — Par phases

### Phase 1 : Multi-agents spécialisés (faisable maintenant, cloud only)

Créer des agents OpenClaw spécialisés via `openclaw agents add` :

```
openclaw agents add --id researcher --name "Scout"
openclaw agents add --id creative --name "Quill"
openclaw agents add --id developer --name "Dev"
```

Chaque agent a son propre workspace, son IDENTITY.md, ses skills.

### Phase 2 : Ajout Ollama pour modèles locaux

Installer Ollama sur la VM Azure ou sur un Mac local :

```bash
# Sur la VM ou un Mac
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.3:70b     # Gros modèle de travail
ollama pull qwen2.5:32b      # Alternative
ollama pull gemma2:27b        # Léger mais capable
```

Configurer dans OpenClaw :
```json
{
  "providers": {
    "ollama-local": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "models": [{"id": "llama3.3:70b", "name": "Llama 3.3 70B Local"}]
    }
  }
}
```

### Phase 3 : Scheduling 24/7

Utiliser des tâches cron ou le système d'events OpenClaw pour déclencher les agents périodiquement :

```
# Toutes les 30 min : Scout lit Reddit
*/30 * * * * openclaw agent --agent researcher --message "Lis les derniers posts sur r/SaaS et r/buildinpublic. Cherche des problèmes à résoudre."

# Toutes les 2h : Quill écrit du contenu
0 */2 * * * openclaw agent --agent creative --message "Écris un tweet basé sur les dernières trouvailles de Scout."

# Quotidien : Roundtable
0 9 * * * openclaw agent --agent main --message "Roundtable : résume les activités de tous les agents, décide des priorités du jour."
```

### Phase 4 : Visualisation des agents

L'interface visuelle d'Alex Finn (agents qui marchent, water cooler,
tables de réunion) pourrait être :
- **Native OpenClaw** — à vérifier dans la doc officielle
- **AI Town (a16z)** — projet open-source similaire : github.com/a16z-infra/ai-town
- **Custom** — développée spécifiquement par Alex Finn

À investiguer avant d'investir du temps sur cette partie.
La visualisation est un nice-to-have, pas un bloqueur pour le workflow.

---

## 5. Estimation des coûts — Cloud vs Local vs Hybride

### Scénario : 5 agents tournant ~12h/jour

| Mode | Coût mensuel estimé | Qualité |
|---|---|---|
| **Full cloud** (GPT-5.2 / Opus) | ~3 000-10 000 $/mois | Excellente |
| **Hybride** (cloud décision + local travail) | ~50-200 $/mois | Bonne |
| **Full local** (Mac Studio) | ~20 $/mois (électricité) | Correcte (dépend du modèle) |

Le modèle hybride est le sweet spot : payer le cloud uniquement pour les décisions critiques (quelques $/jour), et tout le travail intensif en local.

---

## 6. Modèle de données — Agents avec personnalité

```javascript
// Exemple de configuration d'agent OpenClaw enrichie
{
  "id": "scout",
  "name": "Scout",
  "role": "Analyste & Researcher",
  "model": "ollama-local/llama3.3:70b",  // local
  "personality": {
    "soul": "Curieux, méthodique, obsédé par les données",
    "speakingStyle": "Direct, factuel, utilise des bullet points",
    "signature": "Toujours commence par 'J'ai trouvé quelque chose d'intéressant...'",
  },
  "schedule": "*/30 * * * *",  // toutes les 30 min
  "tasks": [
    "Lire r/SaaS, r/buildinpublic, r/Entrepreneur",
    "Détecter des problèmes récurrents",
    "Remonter les meilleures opportunités à Henry"
  ],
  "relationships": {
    "henry": { "trust": 0.9, "rapport": "Respectueux, écoute ses décisions" },
    "quill": { "trust": 0.7, "rapport": "Collabore sur le contenu, donne du feedback" }
  },
  "memories": []  // s'accumulent au fil du temps
}
```

---

## 7. Prochaines étapes recommandées

1. **Court terme** : Ajouter un 3e agent spécialisé (ex: researcher)
2. **Moyen terme** : Installer Ollama + un modèle local (même sur la VM Azure)
3. **Long terme** : Hardware dédié (Mac Mini M4 ou Mac Studio) pour modèles locaux 24/7
4. **Optionnel** : Investiguer l'interface visuelle d'Alex Finn (native OpenClaw ? AI Town ? custom ?)
