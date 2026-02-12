# Synthèse — "I just spent $20,000 on OpenClaw"

**Auteur** : Alex Finn (@AlexFinnOfficial)
**Vidéo** : https://youtu.be/2KWhHY0KTMk
**Durée** : ~19 minutes
**Date d'analyse** : 11 février 2026

---

## Résumé exécutif

Alex Finn a dépensé **20 000 $** en deux **Mac Studio M3 Ultra** (512 Go de mémoire unifiée chacun) pour faire tourner des modèles IA locaux 24h/24, 7j/7. Il prévoit d'investir **100 000 $** d'ici fin d'année dans du hardware supplémentaire. Son objectif : créer une **entreprise digitale autonome** composée d'agents IA qui travaillent en permanence sans intervention humaine.

---

## 1. Le hardware

| Élément | Détail |
|---|---|
| **Investissement actuel** | 20 000 $ |
| **Hardware** | 2x Mac Studio M3 Ultra, 512 Go mémoire unifiée chacun |
| **Mémoire totale** | 1 To (2x 512 Go) |
| **Modèle principal** | **Kimi K 2.5** — 600 Go de poids → nécessite ~600 Go de RAM |
| **Équivalent NVIDIA** | >100 000 $ en GPU NVIDIA pour la même capacité |
| **Achats prévus** | Mac Studio M5 Ultra, DGX Spark NVIDIA |

### Pourquoi la mémoire unifiée Apple ?

Les Mac Studio ont une mémoire unifiée CPU+GPU qui permet de charger des modèles gigantesques beaucoup moins cher que des GPU discrètes NVIDIA. 512 Go de mémoire unifiée Apple ≈ 10 000 $ vs 50 000 $+ pour 512 Go de VRAM NVIDIA (H100).

---

## 2. Les 5 raisons de faire tourner des modèles locaux

### 2.1 Gratuit à l'usage
Pas de coûts API. Une fois le hardware acheté, chaque token est gratuit. Faire la même chose avec Claude Opus ou ChatGPT coûterait **≥10 000 $/mois** en API.

### 2.2 Fonctionnement 24/7/365
Les agents travaillent non-stop : minuit à minuit, week-end compris. Pas de repos, pas de salaire, pas de plaintes. C'est le facteur différenciant clé — même si les modèles locaux sont « plus bêtes » que Opus, le fait qu'ils tournent en permanence compense largement.

### 2.3 Confidentialité totale
Tout reste sur la machine. Aucune donnée ne part vers le cloud. Fonctionne même sans internet.

### 2.4 Éducatif
Apprendre comment l'IA fonctionne de l'intérieur en faisant tourner ses propres modèles.

### 2.5 Fun
Pur plaisir de voir des agents travailler pour soi.

---

## 3. L'entreprise digitale — "One-Person AI Agent Company"

Alex a construit une **société digitale entière** composée d'agents IA avec une interface visuelle (voir section 5).

### 3.1 Organigramme

```
                    Alex Finn (CEO)
                         │
                  ┌──────┴──────┐
                  │   Henry     │
                  │ Chief of    │
                  │ Staff       │
                  │ (Opus 4.5)  │
                  └──────┬──────┘
           ┌─────────────┼─────────────┐
     ┌─────┴─────┐ ┌─────┴─────┐ ┌────┴─────┐
     │ Creative  │ │ Research  │ │Engineering│
     │ Team      │ │ Team      │ │ Team      │
     │           │ │           │ │           │
     │ Quill     │ │ Scout     │ │ Dev Agent │
     │ (Flux 2)  │ │ (GLM 4.7) │ │ (Local)   │
     │ LOCAL     │ │ LOCAL     │ │ LOCAL     │
     └───────────┘ └───────────┘ └───────────┘
```

### 3.2 Agents identifiés

| Agent | Rôle | Modèle | Local/Cloud | Tâches |
|---|---|---|---|---|
| **Henry** | Chief of Staff / Stratégie | **Claude Opus 4.5** | Cloud ☁️ | Approuver/rejeter les idées, décisions stratégiques. Quelques prompts/jour seulement. |
| **Scout** | Analyste / Researcher | **GLM 4.7** | Local 🖥️ | Lecture continue de Twitter/Reddit, détection de problèmes, remontée à Henry |
| **Quill** | Créatif / Writer | Local model | Local 🖥️ | Rédaction de tweets, contenu, scripts |
| **Creative Agent** | Design | **Flux 2** | Local 🖥️ | Génération d'images, thumbnails YouTube, images Twitter |
| **Dev Agent** | Engineering | Local model | Local 🖥️ | Coding d'apps, shipping sur Vercel |

### 3.3 Caractéristiques des agents

- **Personnalité propre** : chaque agent a son âme, sa façon de parler, ses phrases signature
- **Mémoires individuelles** : les agents accumulent des insights et stratégies
- **Relations inter-agents** : les agents développent des relations (amis, rivaux) qui évoluent dans le temps
- **Conversations spontanées** : discussions au « water cooler », standups, brainstormings autonomes
- **Apprentissage mutuel** : les agents apprennent les uns des autres (ex: Scout dit à Quill qu'un tweet a bien marché → Quill mémorise le style)

---

## 4. Workflows autonomes concrets

### Workflow 1 : Reddit Challenge → App → DM

```
Scout (local) ──lecture Reddit 24/7──→ trouve un problème
         │
         ▼
Henry (Opus) ──évalue──→ approuve si bon challenge
         │
         ▼
Dev Agent (local) ──code l'app──→ ship sur Vercel
         │
         ▼
Scout (local) ──DM l'auteur Reddit──→ "voici la solution"
         │
         ▼
   ↻ Boucle continue 24/7
```

### Workflow 2 : Vidéo YouTube → Publication → Analyse

```
Alex enregistre vidéo brute
         │
         ▼
Agent local ──coupe les blancs / édite──→ vidéo montée
         │
         ▼
Flux 2 (local) ──génère thumbnail──→ image
         │
         ▼
Agent navigateur ──upload YouTube + chapitres──→ publiée
         │
         ▼ (J+1)
Tous les agents ──roundtable meeting──→ analyse performance
         │
         ▼
Agents ──écrivent nouveau script──→ basé sur learnings
```

---

## 5. L'interface visuelle — AI Town (pas OpenClaw natif)

> **Important** : L'interface visuelle avec les agents qui se déplacent dans un bureau, vont aux tables de réunion, aux water coolers, etc. n'est **PAS** native d'OpenClaw.

Il s'agit très probablement d'une personnalisation de **AI Town** (par a16z) :

| Détail | Info |
|---|---|
| **Projet** | AI Town |
| **Repo GitHub** | https://github.com/a16z-infra/ai-town (~9k stars) |
| **Inspiration** | Paper Stanford : *"Generative Agents: Interactive Simulacra of Human Behavior"* |
| **Stack** | Convex (backend/DB), PixiJS (rendu visuel), Ollama/OpenAI (LLM) |
| **Fonctionnalités** | Agents pixel-art sur une tilemap, conversations autonomes, mémoires, pathfinding, relations |
| **Personnalisation** | Tilemap custom (bureau, tables de réunion, water cooler) + agents custom (Henry, Scout, Quill…) |

**OpenClaw** fournit le **backend** (orchestration d'agents, exécution de skills, messaging Telegram/Slack/etc.), mais n'a pas d'UI de visualisation d'agents en mode « bureau virtuel ». Alex a probablement branché AI Town comme couche de visualisation par-dessus OpenClaw.

---

## 6. Architecture économique : Cloud vs Local

Le point clé de la stratégie d'Alex est de **minimiser les appels cloud** :

| Couche | Modèle | Coût | Volume |
|---|---|---|---|
| **Décision stratégique** | Opus 4.5 (cloud) | ~quelques $/jour | Quelques prompts/jour |
| **Travail intensif** | Kimi K 2.5, GLM 4.7, Flux 2 (local) | 0 $/token | 24/7 non-stop |

> *"Opus Henry, the chief of strategy, is only doing decision-making. He isn't doing the dirty work. Everyone else is doing the hard work. All the tokens are being burnt by the local models."*

C'est exactement **notre architecture OpenClaw avec APIM** : un modèle cloud (GPT-5.2) pour les décisions, et on pourrait ajouter des modèles locaux pour le travail intensif.

---

## 7. Guide des budgets — Modèles locaux par palier

| Budget | Hardware | Modèles possibles | Use cases |
|---|---|---|---|
| **~100 $** | Raspberry Pi | Gemma, TinyLlama | Chat simple, smart home |
| **~500-800 $** | Mac Mini M4 (base) | Llama, Mistral, Qwen (petits) | Assistant personnel, petit coding |
| **~1 500-2 000 $** | Mac Mini M4 Pro (top) | Llama 70B, Mistral Medium | Coding sérieux, début recherche |
| **~5 000-8 000 $** | Mac Studio M2 Ultra (occasion) | Modèles plus gros, multi-agents | Workflows pro, multi-agents |
| **~10 000-20 000 $** | Mac Studio M3 Ultra (512 Go) x2 | **Kimi K 2.5 (600 Go)**, GLM 4.7 | Organisation autonome 24/7 complète |
| **Futur** | Mac Studio M5 Ultra, DGX Spark | Modèles futurs encore meilleurs | Entraînement custom, fleet d'agents |

---

## 8. Modèles mentionnés dans la vidéo

| Modèle | Type | Taille | Usage | Local/Cloud |
|---|---|---|---|---|
| **Kimi K 2.5** | LLM text | **600 Go** | Modèle principal le plus smart disponible en local | Local |
| **Claude Opus 4.5** | LLM text | N/A (API) | Chief of staff (Henry) — décisions uniquement | Cloud |
| **ChatGPT 5.3** | LLM text | N/A (API) | Mentionné comme référence de comparaison | Cloud |
| **GLM 4.7** | LLM text | Gros (non précisé) | Scout — recherche/analyse continue | Local |
| **Flux 2** | Image gen | Non précisé | Génération d'images, thumbnails | Local |
| **Llama** | LLM text | Varié (7B-70B) | Budget moyen, coding/assistant | Local |
| **Mistral** | LLM text | Varié | Budget moyen | Local |
| **Qwen** | LLM text | Varié | Budget moyen | Local |
| **Gemma** | LLM text | Petit (2B-7B) | Budget minimal (Raspberry Pi) | Local |
| **TinyLlama** | LLM text | ~1B | Budget minimal | Local |

---

## 9. Points clés pour nous (OpenClaw)

1. **On a déjà la base** : notre setup OpenClaw + APIM fait exactement ce qu'Alex décrit côté backend
2. **Manque le local** : on utilise exclusivement le cloud (GPT-5.2 via APIM). Pour du 24/7 économique, il faudrait ajouter des modèles locaux (Ollama)
3. **Manque la visualisation** : AI Town serait un ajout intéressant pour visualiser nos agents
4. **Le multi-agent est la clé** : pas un seul agent polyvalent, mais une équipe spécialisée avec des rôles
5. **Le modèle hybride cloud+local** est la bonne stratégie : cloud pour la stratégie, local pour le volume

---

## Fichiers dans ce répertoire

| Fichier | Description |
|---|---|
| [SYNTHESE.md](SYNTHESE.md) | Ce document |
| [AGENT-ORG.md](AGENT-ORG.md) | Modélisation de l'organisation d'agents |
| [transcript_en.txt](transcript_en.txt) | Transcript brut anglais |
| [transcript_fr.txt](transcript_fr.txt) | Traduction française |
| [segments_en.json](segments_en.json) | Segments anglais (JSON) |
| [segments_fr.json](segments_fr.json) | Segments français (JSON) |
