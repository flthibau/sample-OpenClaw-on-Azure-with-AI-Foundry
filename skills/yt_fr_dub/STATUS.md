# STATUS — yt_fr_dub

## Résumé

Skill OpenClaw : **URL YouTube → MP4 doublé en français**.

## État actuel

- Pipeline global OK : download/entrée MP4 → transcribe → translate → TTS → remux
- TTS : **Azure Speech via APIM** (`/speech/cognitiveservices/v1`, SSML)
- Ajouts CLI :
  - `--input <mp4>` pour utiliser un fichier local (skip yt-dlp)
  - `--blobUpload` (+ options) pour uploader le MP4 final sur Azure Blob et renvoyer une **URL SAS**
- Outils VM : `ffmpeg` / `ffprobe`, `yt-dlp`, `curl`, `az`
- Garde-fou : vidéos **< 20 min** recommandées pour les tests

## Blocage principal (résolu / contourné)

- YouTube anti-bot/JS challenge (`n challenge solving failed`) → contourné avec EJS (`--remote-components ejs:github`) + runtime JS
- Cookies YouTube nécessaires selon les vidéos

## Vidéo de test

- https://youtu.be/-os0lxDX0bU?si=rixXxr5PZFDa9-Hf

## Dernier test E2E

- OK : génération MP4 doublé + upload Azure Blob + URL SAS renvoyée dans stdout

## Next steps

1) Ajouter au download YouTube du script `run.js` les flags EJS + support cookies (configurable) pour que l’E2E marche “juste avec une URL”
2) Décider la stratégie de distribution par défaut :
   - retourner une URL SAS (Blob) vs conserver fichier local
3) Améliorer la synchro : aujourd’hui on fait `-shortest` (pas de time-stretch / align)
4) Option : garder audio original en piste 2
