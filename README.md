<p align="center"><b>Pock v3</b></p>
<p align="center">Fork maintenu de <a href="https://github.com/konstantintuev/PockV2">PockV2</a> (widgets Touch Bar pour macOS), avec des améliorations pour les versions récentes de macOS.</p>

---

## 🇫🇷 Français

### Ce qui change par rapport à PockV2

1. **La batterie passe en jaune en mode économie d'énergie**, comme dans la barre des menus de macOS.
   L'état est lu via `pmset` (toujours frais, contrairement au snapshot IOKit du système qui peut avoir jusqu'à ~30 secondes de retard) : le passage au jaune — et le retour au blanc — se fait en ~5 secondes au maximum, qu'il s'agisse du mode économie d'énergie ou du branchement/débranchement du câble.
2. **Icône batterie en charge** : câble branché, la batterie affiche son niveau de remplissage réel avec l'éclair.
3. **Appuyez sur l'icône batterie pour basculer le mode économie d'énergie** on/off.
4. **Le widget Now Playing fonctionne à nouveau sur les macOS récents** : le framework privé `MediaRemote` d'Apple ne répond plus aux apps tierces sur les versions récentes de macOS, donc Pock v3 lit les métadonnées d'Apple Music et Spotify via AppleScript (titre, artiste, pochette, et les contrôles lecture/pause/musique suivante-précédente).

### Nouveautés de la v3.1

1. **Éclair de charge violet** : visible sur tous les fonds — le noir de la Touch Bar quand la batterie est moins qu'à moitié remplie, comme sur le remplissage vert ou jaune.
2. **Le dessin du niveau de charge suit la batterie en continu** : le pourcentage est lu directement dans le registre IOKit (toujours frais), donc le dessin monte et descend pourcentage par pourcentage, sans plus avoir à brancher/débrancher le câble ou basculer le mode économie d'énergie pour rafraîchir l'affichage.
3. **Couleurs de remplissage comme la barre des menus en mode normal** : blanc pendant la charge, **vert dès 100 %** (même pendant la phase de « finishing charge », où l'icône de la barre des menus de macOS 27 reste blanche), **rouge à 10 % ou moins** sur batterie. En mode économie d'énergie, le remplissage reste jaune en permanence (inchangé).
4. **Souris dans la Touch Bar** : quand la souris touche le bord bas de l'écran, un curseur apparaît sur la Touch Bar. Clic gauche = lancer l'app sous le curseur, molette/défilement = faire défiler le Dock, glisser-déposer = déposer un fichier sur une icône. Un **clic droit sur une icône du Dock** (ou un **appui long ~1,5 s avec le doigt**) affiche le **vrai menu contextuel du Dock de macOS**, au-dessus de l'icône en question. Tout cela se règle dans les préférences de Pock (onglet Général : activation de la souris, visualisation de la zone de détection, menu contextuel).
5. **Numéro de version corrigé** : 0.8.4 (jamais mis à jour depuis le projet d'origine) → 3.1.0.
6. **Heure avec les secondes (option)** : une case « Show seconds » dans les réglages du widget Status fait défiler l'horloge en HH:mm:ss.

### Compatibilité

- ✅ Testé sur **macOS 27.0** sur un **MacBook Pro M2** (13 pouces, avec Touch Bar) — souris, tactile et appui long inclus.
- Les versions antérieures à macOS 27 **n'ont pas pu être validées** (l'appareil de test est déjà sous macOS 27). macOS 27 a modifié des fonctions internes de la Touch Bar ; le code conserve le chemin d'accès historique pour les versions antérieures, mais sans garantie.
- macOS 27.0 est sorti il y a une semaine seulement : pas encore testé sur une version plus récente (27.0.1 / 27.1 à venir).

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

- **Le menu contextuel du Dock (clic droit / appui long) ne fonctionne pas** — en particulier après une mise à jour de Pock alors que la case « PockV3.app » semble déjà cochée dans les réglages : l'autorisation Accessibilité est périmée. Réinitialisez-la puis re-accordez-la :
  ```bash
  sudo tccutil reset Accessibility ch.quadlife.pockv3
  ```
  puis relancez Pock et acceptez à nouveau la permission quand elle est demandée.
- Si certains widgets du Control Center (ex. volume +/−) ne fonctionnent pas, retirez l'app des autorisations Accessibilité et Enregistrement d'écran dans Réglages Système, puis ajoutez-la à nouveau. Si ça ne suffit pas : `sudo tccutil reset All` dans le Terminal, redémarrez, puis accordez à nouveau les permissions nécessaires.

---

## 🇬🇧 English

### What changed vs. PockV2

1. **The battery turns yellow in Low Power Mode**, like the macOS menu bar.
   The state is read through `pmset` (always fresh, unlike the
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

### What's new in v3.1

1. **Purple charging bolt**: visible on every background — the black of the Touch Bar
   when the battery is less than half full, as well as on the green or yellow fill.
2. **The fill level drawing now tracks the battery continuously**: the percentage is
   read straight from the IOKit registry (always fresh), so the drawing climbs and
   falls percentage by percentage — no more plugging/unplugging the charger or
   toggling Low Power Mode just to refresh the display.
3. **Fill colors like the menu bar in normal mode**: white while charging, **green as
   soon as it reaches 100%** (even during the "finishing charge" phase, where the
   macOS 27 menu bar icon stays white), **red at 10% or less** on battery power. In
   Low Power Mode the fill stays yellow all the time (unchanged).
4. **Mouse support in the Touch Bar**: when the mouse reaches the bottom edge of the
   screen, a cursor appears on the Touch Bar. Left click = launch the app under the
   cursor, scroll = browse the Dock, drag & drop = drop a file onto an icon. A
   **right-click on a Dock icon** (or a **long press of ~1.5 s with a finger**) shows
   the **authentic macOS Dock context menu**, above the icon in question. All of this
   is configurable in Pock's preferences (General tab: mouse support on/off, show the
   tracking area, context menu on/off).
5. **Version number fixed**: 0.8.4 (never updated since the original project) → 3.1.0.
6. **Clock with seconds (optional)**: a "Show seconds" checkbox in the Status widget preferences ticks the clock to HH:mm:ss.

### Compatibility

- ✅ Tested on **macOS 27.0** on a **MacBook Pro M2** (13-inch, with Touch Bar) —
  including mouse support, touch and long press.
- Versions older than macOS 27 **could not be validated** (the test device is already
  on macOS 27). macOS 27 changed Touch Bar internals; the code keeps the legacy path
  for older versions, but without guarantee.
- macOS 27.0 was released only a week ago: not yet tested on a newer version
  (27.0.1 / 27.1 to come).

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

- **The Dock context menu (right-click / long press) doesn't work** — especially after
  updating Pock while the "PockV3.app" checkbox already appears enabled in System
  Settings: the Accessibility authorization is stale. Reset it, then grant it again:
  ```bash
  sudo tccutil reset Accessibility ch.quadlife.pockv3
  ```
  then relaunch Pock and accept the permission when asked again.
- If some Control Center widgets (e.g. volume up/down) don't work, remove the app from
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