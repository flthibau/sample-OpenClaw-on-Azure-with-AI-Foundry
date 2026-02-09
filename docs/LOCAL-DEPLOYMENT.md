# Déploiement Local Sécurisé (WSL)

Ce guide explique comment déployer OpenClaw localement sur Windows via WSL de manière sécurisée.

## 🔒 Caractéristiques de sécurité

| Fonctionnalité | Description |
|----------------|-------------|
| **Isolation fichiers** | Aucun accès à `/mnt/c` (fichiers Windows) |
| **Volume dédié** | Stockage dans `~/.openclaw-secure` uniquement |
| **Limites ressources** | Configurable via systemd |
| **Réseau restreint** | HTTP/HTTPS uniquement |

## 📋 Prérequis

1. **Windows 10/11** avec WSL2 installé
2. **Node.js 20+** installé dans WSL
3. **Clé API OpenAI** (ou Azure OpenAI)

## 🚀 Installation

### 1. Ouvrir WSL

```powershell
wsl
```

### 2. Lancer le script de déploiement

```bash
cd /path/to/sample-OpenClaw-on-Azure-with-AI-Foundry/scripts

chmod +x deploy-local-secure.sh
./deploy-local-secure.sh --openai-key "sk-votre-clé"
```

### 3. C'est prêt !

OpenClaw est accessible sur : http://localhost:18789

## 📂 Structure des fichiers

```
~/.openclaw-secure/
├── config/
│   └── .env              # Configuration OpenClaw (clés API, etc.)
├── data/                 # Données persistantes (mémoire)
├── logs/                 # Logs de l'application
├── start.sh              # Démarrer OpenClaw
├── stop.sh               # Arrêter OpenClaw
├── status.sh             # Vérifier le statut + sécurité
├── logs.sh               # Voir les logs
└── edit-config.sh        # Modifier la configuration
```

## 🛠️ Commandes

```bash
cd ~/.openclaw-secure

# Démarrer
./start.sh

# Arrêter
./stop.sh

# Vérifier le statut et la sécurité
./status.sh

# Voir les logs
./logs.sh

# Modifier la configuration
./edit-config.sh
```

## ⚙️ Configuration

### OpenAI API

Éditez `~/.openclaw-secure/config/.env` :

```env
OPENAI_API_KEY=sk-votre-clé-openai
```

### WhatsApp (via Twilio)

```env
WHATSAPP_ENABLED=true
TWILIO_ACCOUNT_SID=votre-sid
TWILIO_AUTH_TOKEN=votre-token
TWILIO_WHATSAPP_NUMBER=+14155238886
```

### Telegram

```env
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
```

Après modification, redémarrez :
```bash
./stop.sh && ./start.sh
```

## 🔒 Vérification de la sécurité

```bash
./status.sh
```

Sortie attendue :
```
📊 OpenClaw Secure Status
=========================

🔧 Service:
● openclaw.service - OpenClaw Gateway Service
     Active: active (running)

🔒 Security Check:
   ✅ No Windows filesystem access
   ✅ Network restricted to HTTP/HTTPS
```

## 🆚 Comparaison : Local vs Azure

| Aspect | Local (WSL) | Azure VM |
|--------|-------------|----------|
| **Coût** | ✅ Gratuit | ⚠️ ~$70/mois |
| **Isolation** | ⚠️ Bonne (WSL) | ✅ Totale |
| **Accès Windows** | ❌ Bloqué | ✅ Impossible |
| **Performance** | Dépend de ton PC | Consistante |
| **Disponibilité** | Quand PC allumé | 24/7 |
| **Réseau** | HTTP/HTTPS | VNet isolé |

## ⚠️ Limitations

1. **Pas d'isolation réseau totale** : Le process peut accéder à Internet (HTTP/HTTPS)
2. **Même machine** : Un exploit kernel pourrait théoriquement s'échapper

Pour une sécurité maximale, préférez le déploiement Azure.

## 🔧 Dépannage

### Erreur de permission

```bash
sudo chown -R $USER:$USER ~/.openclaw-secure
chmod 700 ~/.openclaw-secure
```

### Service ne démarre pas

```bash
journalctl -u openclaw -f
# Ou vérifier directement les logs
cat ~/.openclaw-secure/logs/*.log
```
