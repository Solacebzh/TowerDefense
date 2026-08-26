# Gloom Bastion

**Tower defense roguelite** en pixel art de haute qualité, dans un univers gothique
sombre, carmin et sanglant. Défends ton donjon, bâtis ta cité maudite, et deviens
plus fort à chaque descente.

> *La nuit se souvient.*

---

## 🎮 La boucle de jeu

```
        ┌─────────────────────────────────────────────┐
        │  PHASE DE CONSTRUCTION                        │
        │  • place des TOURS sur la carte (défense)     │
        │  • bâtis / améliore ta VILLE (buffs permanents)│
        └───────────────────────┬─────────────────────┘
                                 │  ▶ Invoquer la vague (Espace)
                                 ▼
        ┌─────────────────────────────────────────────┐
        │  COMBAT                                        │
        │  • les vagues d'ennemis marchent vers le donjon│
        │  • tue-les pour gagner de l'OR                 │
        │  • s'ils atteignent le donjon → dégâts de base │
        └───────────────────────┬─────────────────────┘
                                 │  vague survécue → +or
                                 ▼
            vague suivante, plus dure … jusqu'à la chute
                                 │
                                 ▼
        ┌─────────────────────────────────────────────┐
        │  LE DONJON TOMBE → gagne des ÉCLATS DE SANG   │
        │  → dépense-les au Sanctuaire (méta permanente) │
        │  → recommence, plus fort                       │
        └─────────────────────────────────────────────┘
```

Le cœur roguelite : **le choix**. À chaque phase de construction tu arbitres entre
dépenser ton or en **défenses immédiates** (tours) ou en **puissance permanente**
(bâtiments de la ville). Puis les Éclats de Sang rendent chaque partie suivante plus
forte, même après la mort.

## ⚔️ Contenu de cette tranche jouable

- **3 tours** : Cristal de Sang (équilibrée), Baliste d'Os (perce-armure lourd),
  Chaudron de Peste (dégâts de zone + ralentissement).
- **3 ennemis** : Rampant, Spectre (rapide), Charnier (colosse) + mini-boss toutes
  les 5 vagues.
- **4 bâtiments de ville** évolutifs : Forge (dégâts), Trésorerie (or), Sanctuaire
  (PV du donjon + régénération), Autel de Guerre (cadence de tir).
- **4 améliorations méta** persistantes (Sanctuaire du Sang) achetées avec les
  Éclats de Sang.
- **Vagues procédurales** : difficulté qui monte à l'infini.
- **Gore** : démembrement, gerbes de sang et éclaboussures persistantes au sol,
  tremblement d'écran quand le donjon est touché.
- Sauvegarde automatique de la méta-progression (`user://gloom_bastion.save`).

## 🕹️ Contrôles

| Action | Touche |
|---|---|
| Sélectionner une tour | `1` `2` `3` ou clic sur la carte de tour |
| Placer une tour | Clic gauche sur une case libre |
| Bâtir / améliorer un bâtiment | Clic gauche sur un socle près du donjon |
| Invoquer la vague suivante | `Espace` ou le bouton en haut à droite |

Tu peux placer des tours **même pendant le combat** (si tu as l'or).

## 🚀 Lancer le jeu

Le projet utilise **Godot 4.3**.

1. Installe [Godot 4.3](https://godotengine.org/download) (gratuit).
2. Ouvre Godot → *Importer* → sélectionne le fichier `project.godot` de ce dossier.
3. Appuie sur **F5** (ou le bouton ▶) pour jouer.

> ⚠️ Le jeu ne peut pas être prévisualisé dans l'environnement Arena (Godot n'y est
> pas exécutable) : lance-le depuis ton Godot local.

## 🗂️ Structure du projet

```
project.godot            Configuration Godot (autoload Save, écran 1280×720)
scenes/main/main.tscn    Scène principale (un seul Node2D → main.gd)
scripts/
  main.gd                Boucle de jeu complète (état, combat, gore, rendu, UI)
  game_data.gd           TOUTES les données réglables (tours, ennemis, ville, méta)
  save_system.gd         Autoload « Save » : Éclats de Sang + méta persistante
assets/art/              Sprites pixel art (donjon, tours, monstres, concepts)
tools/                   Scripts Python d'assistance (nettoyage d'assets, hors jeu)
```

### Où régler l'équilibrage ?

Presque tout est dans **`scripts/game_data.gd`** : coûts, dégâts, portée, PV des
ennemis, courbe de difficulté (`build_wave`), effets et coûts des bâtiments, méta.
C'est volontairement centralisé pour itérer le game design sans toucher au moteur.

## 🎨 Direction artistique

Pixel art gothique, palette noir / carmin / ivoire, lueurs rouge sang. Les sprites
sont générés puis détourés en transparence. Voir `assets/art/concept_sheet.png` pour
la planche de références.

## 🗺️ Suite prévue (non incluse dans cette tranche)

- **Expéditions** : envoyer des unités explorer la grande carte pour ramener
  ressources et reliques (avec risques).
- Ville étendue en vraie carte constructible (plus de bâtiments, adjacences).
- Plus de tours, d'ennemis, de boss et d'effets d'état.
- Sprites **animés** (marche, attaque, mort) via `AnimatedSprite2D`.
- Audio : ambiance, impacts, cris.

## 🌿 Convention Git

- `develop` : intégration
- `arena/*` : branches de travail de l'agent
- Pull Request vers `develop`
