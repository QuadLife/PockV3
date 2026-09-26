<p align="center"><b>Pock v3</b></p>
<p align="center">Fork maintenu de <a href="https://github.com/konstantintuev/PockV2">PockV2</a> (widgets Touch Bar pour macOS), avec des améliorations pour les versions récentes de macOS.</p>

---

## 🇫🇷 Français

### Ce qui change par rapport à PockV2

1. **La batterie passe en jaune en mode économie d'énergie**, comme dans la barre des menus de macOS.
   PockV2 ne le faisait pas. L'état est lu via `pmset` (toujours frais, contrairement au snapshot IOKit du système qui peut avoir jusqu'à ~30 secondes de retard) : le passage au jaune — et le retour au blanc — se fait en ~5 secondes au maximum, qu'il s'agisse du mode économie d'énergie ou du branchement/débranchement du câble.
2. **Icône batterie en charge** : câble branché, la batterie affiche son niveau de remplissage réel avec l'éclair.
3. **Appuyez sur l'icône batterie pour basculer le mode économie d'énergie** on/off.
4. **Le widget Now Playing fonctionne à nouveau sur les macOS récents** : le framework privé `MediaRemote` d'Apple ne répond plus aux apps tierces sur les versions récentes de macOS, donc Pock v3 lit les métadonnées d'Apple Music et Spotify via AppleScript (titre, artiste, pochette, et les contrôles lecture/pause/musique suivante-précédente).

### Compatibilité

- ✅ Testé sur **macOS 27.0** sur un **MacBook Pro M2** (13 pouces, avec Touch Bar).
- macOS 27.0 est sorti il y a une semaine seulement : pas encore testé sur une version plus récente, ni sur une version antérieure à macOS 27.0 (ça devrait fonctionner, mais sans garantie).

### Installation

1. Téléchargez la dernière version, placez `PockV3.app` dans votre dossier `Applications` et ouvrez-la.
2. L'app n'étant pas notarisée, macOS peut afficher « Apple n'a pas pu vérifier que PockV3.app ne contient pas de logiciel malveillant » au premier lancement. Sur macOS récent, le clic droit → Ouvrir ne suffit plus ; deux solutions :
   - **Réglages Système → Confidentialité et sécurité → section Sécurité → « Ouvrir quand même »**, ou
   - dans le Terminal : `xattr -d com.apple.quarantine /Applications/PockV3.app` (avant le premier lancement).
3. Si Pock n'apparaît pas dans la Touch Bar : **Réglages Système → Clavier**, réglez « La Touch Bar affiche : Commandes d'app ».
4. Accordez la permission **Automatisation** pour Musique/Spotify quand elle est demandée (widget Now Playing).

### Helper du mode économie d'énergie (clic pour basculer)

Basculer le mode économie d'énergie exige les droits root ; au **premier** appui sur l'icône batterie, macOS demande **une seule fois** votre mot de passe admin pour installer deux mini-daemons launchd :

- `/Library/LaunchDaemons/ch.pock.lpm.on.plist`
- `/Library/LaunchDaemons/ch.pock.lpm.off.plist`

Chaque daemon surveille un petit fichier témoin (`/private/var/tmp/pock.lpm.on` / `.off`). Quand Pock y écrit, le daemon lance `pmset -a lowpowermode 1` (ou `0`) en root. Après cette installation unique, la bascule est instantanée et ne redemande jamais de mot de passe.

Pour désinstaller le helper :

```bash
sudo launchctl bootout system/ch.pock.lpm.on
sudo launchctl bootout system/ch.pock.lpm.off
sudo rm /Library/LaunchDaemons/ch.pock.lpm.on.plist /Library/LaunchDaemons/ch.pock.lpm.off.plist
sudo rm /private/var/tmp/pock.lpm.on /private/var/tmp/pock.lpm.off
```

### Compiler depuis les sources

```bash
git clone https://github.com/QuadLife/PockV3.git
cd PockV3
pod install
open PockV3.xcworkspace
```

Puis compilez le schéma `PockV3` (cible de déploiement : macOS 10.13+).

### Résolution de problèmes

Si certains widgets du Control Center (ex. volume +/−) ne fonctionnent pas, retirez l'app des autorisations Accessibilité et Enregistrement d'écran dans Réglages Système, puis ajoutez-la à nouveau. Si ça ne suffit pas : `sudo tccutil reset All` dans le Terminal, redémarrez, puis accordez à nouveau les permissions nécessaires.

---

## 🇬🇧 English

### What changed vs. PockV2

1. **The battery turns yellow in Low Power Mode**, like the macOS menu bar.
   PockV2 didn't do that. The state is read through `pmset` (always fresh, unlike the
   system's IOKit snapshot which can lag up to ~30 seconds): switching to yellow — and
   back to white — takes at most ~5 seconds, whether Low Power Mode is toggled or the
   charger is plugged/unplugged.
2. **Charging icon**: while plugged in, the battery shows its real fill level with a
   lightning bolt.
3. **Tap the battery icon to toggle Low Power Mode** on/off.
4. **Now Playing widget works again on recent macOS**: Apple's private `MediaRemote`
   framework no longer answers third-party apps on recent macOS versions, so Pock v3
   reads Apple Music and Spotify metadata through AppleScript instead (title, artist,
   artwork, and play/pause/next/previous controls included).

### Compatibility

- ✅ Tested on **macOS 27.0** on a **MacBook Pro M2** (13-inch, with Touch Bar).
- macOS 27.0 was released only a week ago: not yet tested on a newer version, nor on a
  version older than macOS 27.0 (it should work, but no guarantee).

### Installation

1. Download the latest build, move `PockV3.app` to your `Applications` folder and open it.
2. The app is not notarized, so macOS may show "Apple could not verify that PockV3.app
   is free of malware" on first launch. On recent macOS, right-click → Open is no longer
   enough; two options:
   - **System Settings → Privacy & Security → Security section → "Open Anyway"**, or
   - in the Terminal, before the first launch: `xattr -d com.apple.quarantine /Applications/PockV3.app`.
3. If you don't see Pock in the Touch Bar, go to **System Settings → Keyboard** and set
   "Touch Bar shows: App Controls".
4. Grant the **Automation** permission for Music/Spotify when asked (Now Playing widget).

### Low Power Mode helper (tap to toggle)

Toggling Low Power Mode requires root privileges, so the first time you tap the battery
icon, macOS asks **once** for your admin password to install two tiny LaunchDaemons:

- `/Library/LaunchDaemons/ch.pock.lpm.on.plist`
- `/Library/LaunchDaemons/ch.pock.lpm.off.plist`

Each daemon watches a small marker file (`/private/var/tmp/pock.lpm.on` / `.off`). When
Pock writes to it, the daemon runs `pmset -a lowpowermode 1` (or `0`) as root. After that
one-time installation, toggling is instant and never asks for a password again.

To uninstall the helper:

```bash
sudo launchctl bootout system/ch.pock.lpm.on
sudo launchctl bootout system/ch.pock.lpm.off
sudo rm /Library/LaunchDaemons/ch.pock.lpm.on.plist /Library/LaunchDaemons/ch.pock.lpm.off.plist
sudo rm /private/var/tmp/pock.lpm.on /private/var/tmp/pock.lpm.off
```

### Build from source

```bash
git clone https://github.com/QuadLife/PockV3.git
cd PockV3
pod install
open PockV3.xcworkspace
```

Then build the `PockV3` scheme (deployment target: macOS 10.13+).

### Issue resolving

If some Control Center widgets (e.g. volume up/down) don't work, remove the app from
Accessibility and Screen Recording in System Settings and add it again. If it still
doesn't work, run `sudo tccutil reset All` in the Terminal, restart, then grant the
needed permissions again.

---

## Credits & license

Pock v3 is built on the work of many projects, all under the MIT license — see `LICENSE`:

- [Pock](https://github.com/pigigaldi/Pock) by Pierluigi Galdi (original project)
- [PockV2](https://github.com/konstantintuev/PockV2) by Konstantin Touev (direct ancestor)
- [Apple Juice](https://github.com/raphaelhanneken/apple-juice) by Raphael Hanneken (battery tools)
- [Music Bar](https://github.com/musa11971/Music-Bar) by Musa (iTunes Search API artwork)
- [Kawa](https://github.com/herrkaefer/kawa) by Hyunje Jun