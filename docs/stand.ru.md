# Стенд и воспроизведение

[English](stand.md)

Контекст workshop всегда `admin@workshop`, kubeconfig — `~/workshop.txt`. Внешние ресурсы проекта ограничены Tenant `tenant-root/rknetes` и namespace `tenant-rknetes`. Квота — 40 CPU / 64 ГиБ. У builder постоянный том 60 ГиБ; у каждой из трёх вложенных VM — 4 CPU / 8 ГиБ. Внешние адреса VM не запрашиваются.

| Ресурс | Адрес / идентификатор |
|---|---|
| Builder | `tenant-rknetes/builder`, `10.244.8.11` |
| Control plane | `rk-cp`, `10.244.8.31`, узел `kuberoot-eb636b` |
| Worker 1 | `rk-worker1`, `10.244.8.29`, узел `kuberoot-00d000` |
| Worker 2 | `rk-worker2`, `10.244.8.28`, узел `kuberoot-531721` |
| Вложенные Pod / Service CIDR | `10.42.0.0/16` / `10.96.0.0/12` |
| Kubeconfig кластера | `/work/kube/rknetes.conf` внутри builder |
| Kubeconfig API узлов | `/work/kube/node.conf` внутри builder |

Адреса приведены по наблюдению; скрипт создания получает их заново. Вложенный Pod CIDR не должен пересекаться с внешним. Внешний DNS попадает во вложенный Service CIDR, поэтому гостевая ОС явно использует внешние recursive DNS для обычной загрузки образов. Реальный внешний трафик не фильтруется.

Новый стенд создаёт `hack/workshop/up.sh`; существующую VM control plane скрипт переустанавливать отказывается. Сборка Go-компонентов, производных kubectl/apiserver, ядра, rootfs и установочного носителя идёт в tenant. Скрипт устанавливает систему на пустой второй диск VM, выбирает его загрузочным, присоединяет workers, ставит Cilium и ведомства. Текущий стенд собран поэтапно и проверен после обновления; повтор полного provisioning с нуля находится в B27.

Для существующего стенда из репозитория:

```bash
hack/dev/build.sh
hack/workshop/kc.sh get nodes
bash -c 'source hack/workshop/common.sh; builder bash /work/src/rknetes/hack/demo.sh demo-unique-name'
```

Демо отказывается использовать существующие тестовые namespace. Для удаления одноразовых объектов передайте явные имена в `hack/e2e/cleanup.sh` внутри builder. Скрипт проверяет лабораторную метку, отсутствие оставшихся IPAM-резервов, останавливает reconciliation, снимает только намеренный финализатор `forever` и удаляет указанные namespace. Файлы пакетов и сессий на узлах сохраняются. Внешние namespace workshop этой очисткой не затрагиваются.

Перед conformance очистите лабораторные namespace и проверьте Ready узлов. Отсоединённый запуск переживает разрыв соединения ноутбука:

```bash
bash -c 'source hack/workshop/common.sh; builder sh -c "nohup bash /work/src/rknetes/hack/conformance/run.sh unique-name </dev/null >/work/conformance-driver.log 2>&1 &"'
```

Hydrophone v0.5.0 предпочитает in-cluster credentials явно указанному kubeconfig. Runner удаляет только `KUBERNETES_SERVICE_HOST` и `KUBERNETES_SERVICE_PORT` для этого процесса. `build-runner.sh` также меняет переменную запуска параллельности на `E2E_EXTRA_GINKGO_ARGS=--procs=8`: Go runner v1.37.1 не понимает числовой `E2E_PARALLEL`. Pod запускателя имеет toleration для NoExecute, которые ставит сам набор тестов: иначе тест taint выселяет запускатель и уничтожает незавершённые результаты. Официальный образ conformance и тестовый бинарный файл не меняются. Собственного skip-выражения, исключающего conformance-тесты, нет.

Доказательства находятся в `/work/evidence/<run>` и копируются в `docs/evidence/`. Закрытые данные хранятся в `/work/kube`, `/work/keys`, `/work/trust`, `/work/tls`; они не обслуживаются HTTP builder и не попадают в git. В `/work/out` находятся только артефакты сборки. Временные serving-сертификаты действуют 30 дней и требуют обновления до истечения срока.

Нативное обновление: `hack/kuberoot.sh build amd64`, затем `hack/kuberoot.sh bundle amd64`, затем `hack/stand/upgrade.sh` в builder с URL подписанного bundle, SHA256 и тремя гостевыми адресами. Проверяются загрузочный слот, смена boot ID, затем Ready узла. Предыдущий слот и ключи подписи сохраняются для восстановления. Бинарные файлы дополнений скачиваются из неизменяемых снимков частного builder и проверяются по SHA256. В B27/B29 остаются создание стенда с нуля и полный учёт происхождения релиза.

`hack/package/build.sh` собирает настоящий `kuberoot-rknetes` в builder, сохраняет charts только в его частном OCI registry и подписывает индекс ключом за пределами `/work/out`. Пакет содержит 17 CRD и рабочие controller, admission, MAX, watch-office. Образы закреплены по digest; каждый init-контейнер проверяет бинарный файл перед запуском. TLS-ключи создаются при установке либо сохраняются из существующих Secret и не входят в пакет.

`hack/package/install.sh` переносит в управление kubepkg только объекты этого репозитория. Проверенная установка — версия 0.1.0 build 2, Ready revision 6. Начальные конфликты server-side apply Helm 4 исправлены без удаления CRD и их данных. `hack/package/check.sh` проверяет готовность, rollout и закрепление артефактов. Отдельный chart — `/work/out/packages/rknetes-0.1.0.tgz`, рядом индекс и подпись. Публичный registry не использовался.

Cilium использует `kubeProxyReplacement=false` и `cni.chainingMode=portmap`. После включения этого штатного CNI-пути первоначально упавший HostPort прошёл отдельный upstream-тест. Он выбрал и успешно выполнил один тест; служебные hooks набора считаются отдельно и не прибавляются к 462.
