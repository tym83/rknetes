# RKNetes

[English](README.md)

RKNetes — дистрибутив Kubernetes на kuberoot и Cilium. Его лабораторные ведомства превращают [концепцию](docs/concept.ru.md) о регулировании российского интернета в измеримые отказы Kubernetes. Здесь используются настоящие пакеты, admission-запросы, watch-соединения, финализаторы и taint узлов.

Нативная сборка запускает `eo-server`, `gosplan` и `uchastkovy`. Обычный upstream-клиент понимает `kubectl get стручки`; `hodatay` меняет текстовое представление, сохраняя настоящую структурированную версию. Проект остаётся модификацией Kubernetes с сохранёнными авторством и лицензиями.

Стенд занимает один Tenant `tenant-root/rknetes`: builder и три VM с kuberoot. Компиляция выполняется в builder. Эксперименты действуют только в явно помеченных лабораторных namespace вложенного кластера. Управляющий кластер workshop и остальные tenants в эксперимент не входят.

Начните с [эксплуатации стенда](docs/stand.ru.md), [архитектуры](docs/design.ru.md), [результатов измерений](docs/evidence.ru.md) и [приёмки требований](BACKLOG.ru.md). [Шаблоны для реестра](docs/registry/README.ru.md) честно описывают происхождение продукта и оставляют данные правообладателя незаполненными. Ничего не подано и не опубликовано.

```bash
# Из репозитория. Существующий стенд не переустанавливается.
hack/workshop/up.sh

# Внешний и вложенный kubectl всегда явно выбирают admin@workshop.
hack/workshop/kc.sh get nodes
hack/workshop/kc.sh get стручки -n rknet-system

# Сборка и проверки Go-компонентов выполняются в builder tenant.
hack/dev/build.sh
```

`hack/demo.sh` запускает воспроизводимый лабораторный показ внутри builder. Он требует свободных тестовых namespace и отдельно записывает каждую проверку. Настоящий upstream conformance запускает `hack/conformance/run.sh`; сатирический [отечественный conformance](docs/domestic-conformance.ru.md) хранится отдельно. Точный результат upstream находится в отчёте об измерениях, а не в константе или выдуманном дашборде.

Код RKNetes распространяется по Apache-2.0. Kubernetes, Linux, Cilium и остальные компоненты сохраняют собственные лицензии. Игнорируемый `SESSION_LOG.md` служит журналом передачи работ; ключи и kubeconfig находятся вне репозитория.

Выпуск — образ native11, установленный на все три узла, и подписанный пакет `kuberoot-rknetes` 0.1.0 build 7. На этой сборке `hack/demo.sh` проходит все **53 проверки** полного показа, а upstream conformance — **462/462**. [Отчёт об измерениях](docs/evidence.ru.md) связывает оба результата с хэшем bundle и архивами; [опыты](docs/experiments.ru.md) описывают каждый механизм, а все пункты [BACKLOG](BACKLOG.ru.md) закрыты.
