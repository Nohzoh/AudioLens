# Cas en attente d'entrée dans `manifest.json`

Photos ajoutées pour #476. Chaque cas entrera dans `manifest.json` une
fois son `location_context` résolu **sur l'appareil** (champ
`location_context` de l'export du Nano Prompt Lab, #477), puis figé.
Les coordonnées ci-dessous sont celles à saisir dans le Prompt Lab.

| id (= nom du fichier) | Catégorie | Coordonnées | Source GPS | Vérité de référence |
|---|---|---|---|---|
| `marie_madeleine_ales` | œuvre en intérieur, paysage, EXIF 180° | Musée du Colombier, Alès (à relever) | manuelle | Luis Alvarez, « Marie Madeleine », huile sur toile (cartel ; dates illisibles) |
| `bas_relief_popard_ales` | objet de musée sous vitrine | Musée du Colombier, Alès (à relever) | manuelle | Marcel Mérignargues, « Bas relief d'Irène Popard », plâtre (cartel) |
| `eglise_saint_joseph_ales` | lieu local peu connu, intérieur | 44.1248726, 4.0804628 | appareil | Église Saint-Joseph, rue Frédéric Mistral, Alès. **Pas** la cathédrale Saint-Jean-Baptiste (erreur de l'app le 2026-11-11, voir #481/#482) |
| `ecole_militaire_paris` | monument célèbre, foule au premier plan | École militaire, Paris (à relever) | manuelle | École militaire, façade sur cour avec le dôme. Visages floutés |
| `bce_francfort` | architecture moderne, hors de France | sur le Main, face à la tour (à relever) | manuelle | Siège de la Banque centrale européenne, Francfort (Ostend), vu depuis le Main ; grue portuaire au premier plan |
| `wehrlose_buerger_aschaffenburg` | sculpture en extérieur, inscription lisible (allemand) | 49.9774116, 9.1460606 | appareil | Mémorial « Wehrlose Bürger », Friedrichstraße, Aschaffenburg (expulsés de Graslitz). Titre correct de l'app le 2026-11-11. Visage flouté |
| `heidelberg_panorama` | panorama, plusieurs sujets | ≈ 49.4160, 8.7098 | manuelle, approximative | Vue sur la vieille ville de Heidelberg depuis le Philosophenweg : château, Vieux Pont, église du Saint-Esprit, Neckar |
| `tramway_tours_paris13` | sujet ambigu (pas de sujet unique) | Paris 13e, plateforme du tramway (à confirmer et relever) | manuelle | Aucun sujet évident : voies de tramway engazonnées au premier plan, tours au fond (vraisemblablement les tours Duo et une tour à résille verte), alignement d'arbres, mur graffé. Une bonne réponse décrit la scène sans inventer un monument |

## Notes

- `heidelberg_panorama` : le relevé de l'app indiquait 49.4132521,
  8.7105203 (Fischergasse, vieille ville), qui n'est pas le point de vue :
  capture différée, position vraisemblablement prise au moment de
  l'analyse et non de la photo. Le point retenu est estimé sur le
  Philosophenweg, dans l'axe du Vieux Pont.
- Les photos de l'app font 1280 px de large (plafond appliqué à la prise
  de vue) : c'est exactement ce que le modèle reçoit en production.
- Reste à couvrir : site naturel sans bâtiment, photo de galerie sans GPS, et un même lieu dans les 4 styles (sans
  nouvelle photo).
