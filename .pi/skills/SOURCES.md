# Vendored skill sources

Pinned on 2026-08-18.

| Local skill | Upstream | Pinned commit | License |
| --- | --- | --- | --- |
| `android-cli` | https://github.com/android/skills/tree/6685cac2923e3ccc7e5c385019464374699cda95/devtools/android-cli | `6685cac2923e3ccc7e5c385019464374699cda95` | Apache-2.0; complete terms vendored by upstream in the skill references |
| `android-testing-setup` | https://github.com/android/skills/tree/6685cac2923e3ccc7e5c385019464374699cda95/testing/testing-setup | `6685cac2923e3ccc7e5c385019464374699cda95` | Apache-2.0; complete terms vendored by upstream in the skill references |
| `compose-expert` | https://github.com/aldefy/compose-skill/tree/954ef54ea32288fbc90745f012d09d7b791f0d8a/skills/compose-expert | `954ef54ea32288fbc90745f012d09d7b791f0d8a` | MIT |
| `winui-app` | https://github.com/openai/skills/tree/49f948faa9258a0c61caceaf225e179651397431/skills/.curated/winui-app | `49f948faa9258a0c61caceaf225e179651397431` | See vendored `LICENSE.txt` |
| `appkit-modern-input` | https://github.com/markmals/mac-dev-skills/tree/9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5/plugins/appkit/skills/appkit-modern-input | `9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5` | MIT |
| `appkit-packaging` | https://github.com/markmals/mac-dev-skills/tree/9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5/plugins/appkit/skills/appkit-packaging | `9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5` | MIT |
| `appkit-code-review` | https://github.com/markmals/mac-dev-skills/tree/9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5/plugins/appkit/skills/appkit-code-review | `9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5` | MIT |
| `appkit-dev-workflow` | https://github.com/markmals/mac-dev-skills/tree/9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5/plugins/appkit/skills/appkit-dev-workflow | `9bfc1cf6cedf63ff301d8d73a268a1aae03b2ed5` | MIT |
| `md4a-linux-native` | This repository | project-owned | MIT |

Update procedure:

1. inspect upstream history and the complete skill/reference diff;
2. audit scripts and remote-command instructions;
3. copy only the selected skill directory and license;
4. update this table;
5. run project build/test gates before committing.
