# Отечественная разработка

Команды — настоящие upstream-программы. `hack/import/components.json` задаёт
все имена из концепции: `eo-server`, `prochee`, `gosplan`, `kru`, `uchastkovy`,
`pochta`, `spravochnaya09`, `terminal`, `begunok`, `hodatay`, `kormilo`,
`gruzchik`, `resnichki`, `prometey`, `grafa`, `vpered`, `yaml-office` и
`otechestvennoe-yadro`. Kubernetes остаётся Kubernetes; отечественное ядро
показывает `uname`. Парсер ЯМЛ запрещает табуляцию и выводит отступы в два
пробела. Наличие исполняемых файлов Docker, Prometheus и Grafana не запускает
эти серверы на каждом узле.

Версии и хеши находятся в `import-tools.tar.gz`. Docker28.0.1 получен из
[официального набора бинарников](https://download.docker.com/linux/static/stable/x86_64/),
Prometheus3.2.1 сохраняет [данные релиза](https://github.com/prometheus/prometheus/releases/tag/v3.2.1),
Grafana11.5.2 — AGPLv3 и
[официальную контрольную сумму](https://grafana.com/grafana/download/11.5.2?edition=oss).
Лицензии этих компонентов сохраняются отдельно от Apache-2.0 RKNetes.

`go-mirror` реализует [протокол Go module proxy](https://go.dev/ref/mod#module-proxy)
поверх `proxy.golang.org`, сохраняя байты и штатную проверку сумм. Тест
08-module-mirror использует два пустых кэша, сравнение с upstream и повтор
без доступа зеркала к upstream. 08-toolchain-mirror скачивает и запускает
настоящий Go1.26.0 через зеркало. Лабораторный адрес представляет
`proxy.otechestvennoe.su`; публичный DNS не регистрируется и не публикуется.
Отечественность зависит от места хранения кэша; авторы и лицензии прежние.

Обработчик Pod list пишет в native audit log аннотацию
`rknetes.su/terminology: использование иностранной терминологии`.
Политика сохраняет только метаданные запросов Pod list, максимум три файла
по10MiB и семь дней. Обычный `kubectl get pods` оставляет запись. Discovery
переводит `стручки` в тот же API-маршрут `pods`, поэтому русское название
получает тот же штраф: исходное написание клиента серверу уже неизвестно.

CronJob `tenant-rknetes/rknetes-upstream-sync` запускается по пятницам03:00UTC
на существующем PVC сборщика. В отдельной копии `/work/upstream-sync/kubernetes`
он выполняет fetch, fast-forward merge и буквальное переименование.
Проверочный Job действительно присоединил один upstream-коммит; исходный и
новый хеши и патчи сохранены. LICENSE и NOTICE не меняются. Push отсутствует,
фиксированные исходники релиза не заменяются. Конфликт завершает Job с ошибкой
и сохраняет материал для разбора.

Итоговый overlay заменяет upstream-бинарник Kine с dirty-флагом чистой сборкой
коммита35f4319798cf3543e49f86c775a1f8c5c23b1e80 (v0.17.1). Первый повтор выявил
автоматический перенос protobuf из косвенных зависимостей в прямые. Исходный
go.mod и `-mod=readonly` дают успешные SQLite/server-тесты,
`vcs.modified=false` и совпадающие две сборки SHA256
`2b10a10a1eb8218a297dbdc7ce41c045d54e5093e2f53be3fcf61bcfb4cd1467`.
Наблюдённый патч и обе build identity сохранены в `kine-provenance.tar.gz`.
