# Gloom Bastion

Tower defense 2D vue du dessus, gothique et sombre, en pixel art haute qualité.

## Développement

Le projet utilise **Godot 4**. Ouvrir le dossier dans VS Code avec l'extension Godot ou lancer `project.godot` depuis Godot.

### Prototype actuel

- carte vue du dessus avec chemin de monstres
- placement de tours au clic (`50` gold)
- lancement des vagues avec `Espace`
- compteur d'or et de vagues
- ambiance visuelle sombre, rouge carmin et ivoire
- planche de concepts dans `assets/art/concept_sheet.png`

## Structure

- `scenes/` : scènes Godot
- `scripts/` : logique de jeu
- `assets/art/` : direction artistique et sprites
- `data/` : données de tours, monstres et vagues à venir

## Convention Git

- `develop` : intégration
- `feature/<fonctionnalite>` : nouvelles fonctionnalités
- `fix/<probleme>` : corrections
- Pull Request obligatoire vers `develop`
