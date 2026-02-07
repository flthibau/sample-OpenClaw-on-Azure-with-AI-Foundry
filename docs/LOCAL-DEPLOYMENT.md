# Déploiement Local Sécurisé (WSL + Docker)

Ce guide explique comment déployer OpenClaw localement sur Windows via WSL de manière sécurisée.

## 🔒 Caractéristiques de sécurité

| Fonctionnalité | Description |
|----------------|-------------|
| **Isolation fichiers** | Aucun accès à `/mnt/c` (fichiers Windows) |
| **Volume dédié** | Stockage dans `~/.openclaw-secure` uniquement |
| **Filesystem read-only** | Container en lecture seule (sauf /tmp et volumes) |
| **Pas d'escalade de privilèges** | `no-new-privileges` activé |
| **Limites ressources** | Max 2 CPU, 2 GB RAM |
| **Réseau restreint** | HTTP/HTTPS uniquement |

## 📋 Prérequis

1. **Windows 10/11** avec WSL2 installé
2. **Docker Desktop** avec intégration WSL activée
3. **Clé API OpenAI** (ou Azure OpenAI)

## 🚀 Installation

### 1. Ouvrir WSL

```powershell
wsl
```

### 2. Lancer le script de déploiement

```bash
cd /mnt/c/Users/flthibau/OneDrive\ -\ Microsoft/Desktop/FY26/OpenClaw/sample-OpenClaw-on-Azure-with-AI-Foundry/scripts

chmod +x deploy-local-secure.sh
./deploy-local-secure.sh --openai-key "sk-votre-clé"
```

### 3. C'est prêt !

OpenClaw est accessible sur : http://localhost:18789

## 📂 Structure des fichiers

```
~/.openclaw-secure/
├── docker-compose.yml    # Configuration Docker
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

🐳 Container:
NAME              STATUS          PORTS
openclaw-secure   Up 2 minutes    127.0.0.1:18789->18789/tcp

🔒 Security Check:
   ✅ No Windows filesystem access
   ✅ Read-only filesystem
   ✅ Network restricted to HTTP/HTTPS
```

## 🆚 Comparaison : Local vs Azure

| Aspect | Local (WSL + Docker) | Azure VM |
|--------|---------------------|----------|
| **Coût** | ✅ Gratuit | ⚠️ ~$70/mois |
| **Isolation** | ⚠️ Bonne (Docker) | ✅ Totale |
| **Accès Windows** | ❌ Bloqué | ✅ Impossible |
| **Performance** | Dépend de ton PC | Consistante |
| **Disponibilité** | Quand PC allumé | 24/7 |
| **Réseau** | HTTP/HTTPS | VNet isolé |

## ⚠️ Limitations

1. **Pas d'isolation réseau totale** : Le container peut accéder à Internet (HTTP/HTTPS)
2. **Dépend de Docker** : Si Docker a une faille, l'isolation est compromise
3. **Même machine** : Un exploit kernel pourrait théoriquement s'échapper

Pour une sécurité maximale, préférez le déploiement Azure.

## 🔧 Dépannage

### Docker non accessible dans WSL

```bash
# Vérifier que Docker Desktop est démarré
# Activer l'intégration WSL dans Docker Desktop > Settings > Resources > WSL Integration
```

### Erreur de permission

```bash
sudo chown -R $USER:$USER ~/.openclaw-secure
chmod 700 ~/.openclaw-secure
```

### Container ne démarre pas

```bash
cd ~/.openclaw-secure
docker compose logs
```
