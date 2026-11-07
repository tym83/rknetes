# Архивы доказательств

[English](README.md)

Начните с [отчёта об измерениях](../evidence.ru.md): он связывает принятый образ, пакет и итоговый прогон. Старые архивы сохраняют отказы и промежуточное поведение; их результаты не переносятся на новый образ. Здесь находятся открытые логи, хеши исходников и результаты. Закрытые ключи, kubeconfig и содержимое сессий остаются на стенде.

[manifest.json](manifest.json) содержит SHA256, размер и верхние каталоги каждого архива. Таблица показывает точные имена сохранённых каталогов, а не заново трактует результаты тестов.

| Архив | Сохранённые каталоги |
|---|---|
| [byte-boundaries.tar.gz](byte-boundaries.tar.gz) | `byte-boundaries-1` |
| [byte-policy.tar.gz](byte-policy.tar.gz) | `byte-policy-1` |
| [calls-streams.tar.gz](calls-streams.tar.gz) | `calls-final-preflight` |
| [cleanroom.tar.gz](cleanroom.tar.gz) | `cleanroom-package`, `cleanroom-provision`, `demo-cleanroom-1`, `demo-cleanroom-2` |
| [composed-first-attempts.tar.gz](composed-first-attempts.tar.gz) | `composed-shop-1`, `composed-shop-2`, `composed-shop-3`, `composed-shop-4`, `composed-shop-5`, `composed-shop-6`, `composed-shop-7`, `composed-shop-8`, `composed-shop-9` |
| [composed-shop.tar.gz](composed-shop.tar.gz) | `composed-shop-10` |
| [conformance-final3.tar.gz](conformance-final3.tar.gz) | `conformance-final3` |
| [conformance-run4.tar.gz](conformance-run4.tar.gz) | `conformance-run4` |
| [conformance-run5.tar.gz](conformance-run5.tar.gz) | `conformance-run5` |
| [demo-final-1.tar.gz](demo-final-1.tar.gz) | `demo-final-1`, `demo-final-1-preparation` |
| [demo-final-3.tar.gz](demo-final-3.tar.gz) | `demo-final-3`, `demo-final-3-bytes`, `demo-final-3-calls`, `demo-final-3-composed`, `demo-final-3-escalation-soak`, `demo-final-3-import`, `demo-final-3-measurements`, `demo-final-3-preparation`, `demo-final-3-registry`, `demo-final-3-regulation`, `demo-final-3-storage`, `demo-final-3-tunnels`, `demo-final-3-watch-scale`, `demo-final-3-whitelist` |
| [demo-native-1.tar.gz](demo-native-1.tar.gz) | `demo-native-1` |
| [demo-native-2.tar.gz](demo-native-2.tar.gz) | `demo-native-2` |
| [demo-native-3.tar.gz](demo-native-3.tar.gz) | `demo-native-3` |
| [dependency-graph.tar.gz](dependency-graph.tar.gz) | `dependency-graph-1` |
| [escalation-soak-rerun.tar.gz](escalation-soak-rerun.tar.gz) | `demo-final-3-escalation-soak-rerun` |
| [final-attempts-native10.tar.gz](final-attempts-native10.tar.gz) | `demo-final-2`, `demo-final-2-bytes`, `demo-final-2-calls`, `demo-final-2-composed`, `demo-final-2-escalation-soak`, `demo-final-2-import`, `demo-final-2-measurements`, `demo-final-2-preparation`, `demo-final-2-registry`, `demo-final-2-regulation`, `demo-final-2-storage`, `demo-final-2-tunnels`, `demo-final-2-watch-scale`, `demo-final-2-whitelist`, `native10-install` |
| [final-validation.tar.gz](final-validation.tar.gz) | `agency-timeout-1`, `escalation-soak-1`, `final-state` |
| [generic-watches.tar.gz](generic-watches.tar.gz) | `watch-resources-1`, `watch-resources-2` |
| [goshran-country.tar.gz](goshran-country.tar.gz) | `jokes-eo-strings`, `jokes-goshran-country` |
| [import-tools.tar.gz](import-tools.tar.gz) | `import-tools`, `module-mirror-1`, `toolchain-mirror-1` |
| [inventory-final.tar.gz](inventory-final.tar.gz) | `provenance`, `sbom` |
| [inventory-native11.tar.gz](inventory-native11.tar.gz) | `provenance`, `sbom` |
| [inventory-native6.tar.gz](inventory-native6.tar.gz) | `provenance`, `sbom` |
| [inventory-native7.tar.gz](inventory-native7.tar.gz) | `provenance`, `sbom` |
| [inventory-native8.tar.gz](inventory-native8.tar.gz) | `provenance`, `sbom` |
| [key-refusal.tar.gz](key-refusal.tar.gz) | `key-refusal-1` |
| [kine-provenance.tar.gz](kine-provenance.tar.gz) | `kine-first`, `kine-source` |
| [licences-final.tar.gz](licences-final.tar.gz) | `licences-native9` |
| [licences-native11.tar.gz](licences-native11.tar.gz) | `licences-native11` |
| [licences-native6.tar.gz](licences-native6.tar.gz) | `licences-native6` |
| [licences-native7.tar.gz](licences-native7.tar.gz) | `licences-final` |
| [licences-native8.tar.gz](licences-native8.tar.gz) | `licences-native8` |
| [max-and-api-streams.tar.gz](max-and-api-streams.tar.gz) | `api-streams-1`, `max-enrollment-2`, `max-priority-1` |
| [national-dns.tar.gz](national-dns.tar.gz) | `national-dns-1` |
| [native-goshran-pulls.tar.gz](native-goshran-pulls.tar.gz) | `native-pulls-4` |
| [native-image-execution.tar.gz](native-image-execution.tar.gz) | `artifact-execution-1` |
| [native11-install.tar.gz](native11-install.tar.gz) | `final-profile-3`, `native11-aliases`, `native11-install`, `native11-package7` |
| [native7-install.tar.gz](native7-install.tar.gz) | `final-install`, `final-native-aliases`, `final-package4` |
| [native8-install.tar.gz](native8-install.tar.gz) | `native8-aliases`, `native8-install`, `native8-package4`, `pre-final-cleanup` |
| [nov6-optional.tar.gz](nov6-optional.tar.gz) | `artifact-chain-2`, `avian-interface-2`, `measurement-soak-1`, `native-pulls-1` |
| [optional-experiments.tar.gz](optional-experiments.tar.gz) | `first-write-1`, `presentation-1`, `presentation-details`, `reinvocation-1`, `sovereign-api`, `telegram-cycle-1` |
| [origin-first-attempt.tar.gz](origin-first-attempt.tar.gz) | `origin-resolution-1` |
| [origin-resolution.tar.gz](origin-resolution.tar.gz) | `origin-resolution-2` |
| [package-build3.tar.gz](package-build3.tar.gz) | `package`, `packages` |
| [package-build4.tar.gz](package-build4.tar.gz) | `binaries.sha256`, `index.pub`, `index.yaml`, `index.yaml.sig`, `rknetes-0.1.0-4.tgz` |
| [package.tar.gz](package.tar.gz) | `binaries.sha256`, `index.pub`, `index.yaml`, `index.yaml.sig`, `installed.yaml`, `rknetes-0.1.0.tgz`, `sha256.txt` |
| [payload-archive.tar.gz](payload-archive.tar.gz) | `payload-archive-1`, `payload-archive-2`, `payload-archive-3`, `payload-archive-4`, `payload-archive-5`, `payload-archive-6` |
| [prepared-first-attempts.tar.gz](prepared-first-attempts.tar.gz) | `artifact-chain-1`, `avian-interface-1` |
| [protocol-first-attempts.tar.gz](protocol-first-attempts.tar.gz) | `native-pulls-2`, `native-pulls-3`, `tunnel-ladder-1` |
| [protocol-ladder.tar.gz](protocol-ladder.tar.gz) | `compliant-3`, `tunnel-ladder-3` |
| [release-inventory.tar.gz](release-inventory.tar.gz) | `provenance`, `sbom` |
| [repeat-build-native11.tar.gz](repeat-build-native11.tar.gz) | `repeat-build-native11` |
| [repeat-build-native8.tar.gz](repeat-build-native8.tar.gz) | `repeat-build` |
| [repeat-build.tar.gz](repeat-build.tar.gz) | `repeat-build` |
| [roaming-and-max-first.tar.gz](roaming-and-max-first.tar.gz) | `max-enrollment-1`, `roaming-2` |
| [runtime-inventory.tar.gz](runtime-inventory.tar.gz) | `sbom-images` |
| [scale-and-build.tar.gz](scale-and-build.tar.gz) | `blogger-scale-1`, `optional-build` |
| [tunnel-cleanup-failure.tar.gz](tunnel-cleanup-failure.tar.gz) | `tunnel-ladder-2` |
| [tunnel-ladder-and-recovery-attempt.tar.gz](tunnel-ladder-and-recovery-attempt.tar.gz) | `compliant-2`, `tunnel-ladder-3` |
| [watch-reconnect.tar.gz](watch-reconnect.tar.gz) | `watch-reconnect` |
| [weekly-upstream.tar.gz](weekly-upstream.tar.gz) | `weekly-sync` |
| [whitelist-control.tar.gz](whitelist-control.tar.gz) | `capacity-1`, `capacity-2`, `schedule-1` |
