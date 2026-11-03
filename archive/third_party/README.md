# Third-party material

| What | Where | Source | Version | Licence |
|---|---|---|---|---|
| FrogLord configuration files (build addresses and name lists) | `third_party/froglord_cfg/` | https://github.com/Kneesnap/FrogLord | commit `5416ae4f0a1e2fd322527e67f01172563b6086e1` | MIT (`third_party/froglord_cfg/LICENSE.md`) |
| GUT, the Godot Unit Test framework | `addons/gut/` (Godot requires add-ons under `addons/`) | https://github.com/bitwes/Gut | tag `v9.5.0`, commit `8255c6305761754748f9fd641da5fd8f51c1708a` (the GUT release for Godot 4.5) | MIT (`addons/gut/LICENSE.md`); its bundled fonts are under the SIL Open Font Licence (`addons/gut/fonts/OFL.txt`) |

Both are included unmodified. GUT is used only to run the tests; the game
does not load it, and packaged builds leave it out. Packaged builds carry
FrogLord's `.cfg` files with their `LICENSE.md`, and the setup screen's
**Credits and licences** window shows FrogLord's credit and licence with
Godot's ([packaging](../../docs/reference/setup.md#packaging)).

No part of the Frogger game itself (executable, archives, videos, music) is
included anywhere in this repository.
