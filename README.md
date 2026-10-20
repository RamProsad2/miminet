⚠️ **РЕПОЗИТОРИЙ ПЕРЕНЕСЕН**
 
Этот репозиторий находится в архиве и больше не развивается. Основная разработка переехала:
 
**Новый репозиторий:** https://sourcecraft.dev/miminet/miminet — там же открывайте issues и присылайте pull request'ы.

**Новости и вопросы:** https://pubble.ru/p/miminet — сообщество Miminet, там публикуются обновления проекта и можно задавать вопросы.

Здесь issues и pull request'ы закрыты. Спасибо всем, кто контрибьютил сюда!

# Miminet

**Miminet** — эмулятор компьютерных сетей на базе ОС Linux, предназначенный для образовательных целей.

---

## 📖 Содержание

- [Требования](#requirements)
- [Локальное развёртывание](#deployment)
  - [Установка](#installation)
  - [Database migrations](#migration)
  - [Vagrant (не обязательно)](#vagrant)
- [Архитектура](#arch)
  - [Общая информация](#arch-info)
  - [Frontend](#frontend)
  - [Backend](#backend)
- [Тестирование](#testing)
  - [Frontend](#frontend-test)
  - [Backend](#backend-test)

---


## 💡 <a name="requirements"></a>Требования

Перед началом работы убедитесь, что у вас установлены:
- [Docker](https://www.docker.com/get-started/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Vagrant](https://www.vagrantup.com/) (не обязательно)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html) (не обязательно)

> Если только начинаете знакомство с проектом, не забудьте прочитать [раздел](#arch) посвященный архитектуре приложения.
---

## 🛠️ <a name="deployment"></a>Локальное развёртывание

Работает на Linux и Windows (WSL 2.5+); на macOS — см. оговорки в [docs/LOCAL_SETUP.md](./docs/LOCAL_SETUP.md).
Нужен только Docker Engine (или Docker Desktop) с плагином compose.

### <a name="installation"></a>Установка:
```bash
git clone https://github.com/mimi-net/miminet.git
cd miminet
./miminet.sh up        # Windows без WSL-терминала: .\miminet.ps1 up
```
Открываем http://localhost и входим под `admin@local` / `admin` (есть доступ к админке).

- `./miminet.sh up` проверяет окружение (`scripts/doctor.sh`), при первом запуске создаёт `.env` из `.env.example` со случайными паролями, собирает образы, поднимает стек ([compose.yaml](./compose.yaml)) и ждёт, пока все сервисы станут healthy.
- `./miminet.sh smoke` — сквозная проверка: вход, создание сети, эмуляция, сверка пакетов с эталоном.
- `./miminet.sh help` — остальные команды (`down`, `logs`, `doctor --fix`, `reset`, `test`).
- VK/Яндекс OAuth и файлы `vk_auth.json` / `miminet_secret.conf` для локальной разработки не нужны.

Подробности по платформам и решение проблем: [docs/LOCAL_SETUP.md](./docs/LOCAL_SETUP.md).

### Prod
[start_all_containers.sh](./start_all_containers.sh), `front/docker-compose-prod.yml`, `back/docker-compose.yml` и `front/.env`, `back/.env` используются для prod и Ansible, для локальной разработки они не нужны.

## <a name="migration"></a>Database migrations
> Следующие действия необходимо выполнять в случае, если вы обновили модель базы данных ([SQLAlchemy](https://www.sqlalchemy.org/)) и теперь хотите, чтобы изменения появились в реальной базе данных.
```
./miminet.sh shell     # или docker exec -it miminet bash для prod-стека
flask db init
flask db migrate
flask db upgrade
```

### <a name="vagrant"></a>Vagrant (не обязательно)
NFS(для полной автоматизации vagrant up):
```
# /etc/sudoers.d/vagrant-syncedfolders
Cmnd_Alias VAGRANT_EXPORTS_CHOWN = /bin/chown 0\:0 /tmp/vagrant-exports
Cmnd_Alias VAGRANT_EXPORTS_MV = /bin/mv -f /tmp/vagrant-exports /etc/exports
Cmnd_Alias VAGRANT_NFSD_CHECK = /etc/init.d/nfs-kernel-server status
Cmnd_Alias VAGRANT_NFSD_START = /etc/init.d/nfs-kernel-server start
Cmnd_Alias VAGRANT_NFSD_APPLY = /usr/sbin/exportfs -ar
%sudo ALL=(root) NOPASSWD: VAGRANT_EXPORTS_CHOWN, VAGRANT_EXPORTS_MV, VAGRANT_NFSD_CHECK, VAGRANT_NFSD_START, VAGRANT_NFSD_APPLY
```

```
cd back
export numberOfBoxes=N
export provider=vbox/vmware
. vagrant_vms.sh
```
---

## ☁️ <a name="arch">Архитектура</a>

### <a name="arch-info"></a>Общая информация
- Miminet использует контейнеризацию для управления своими компонентами.
- RabbitMQ: Система обмена сообщениями, обеспечивающая взаимодействие между фронтендом и бэкендом.

### <a name="frontend"></a> Frontend (фронтенд, front)
- Клиентская часть, предоставляющая веб-интерфейс для взаимодействия пользователей с системой (авторизация, настройка сетей и так далее).
- Файлы, относящиеся к этой части приложения, находятся в каталоге ```front```.
- За эту часть приложения ответственны три контейнера: miminet (основной веб-сервис), [nginx](https://nginx.org/ru/) (HTTP-сервер для балансировки нагрузки) и rabbitmq.
- В Miminet есть [тесты](https://github.com/mimi-net/miminet/tree/main/front/tests) на фронтенд, позволяющие имитировать действия реального пользователя при конфигурации сетей. Реализовано это с помощью [Selenium](https://www.selenium.dev/).

### <a name="backend"></a> Backend (бэкенд, back) 

- Серверная часть приложения, реализующая логику эмуляции сети.
- Файлы, относящиеся к этой части приложения, находятся в каталоге ```back```.
- За эту часть приложения ответственнен контейнер celery, принимающий задачи от фронтенда и обрабатывающий их.
- В Miminet есть [тесты](https://github.com/mimi-net/miminet/blob/main/back/tests) для бэкенда, проверяющие качество эмуляции заданной сети. Конфигурация тестов происходит через [JSON-файлы](https://github.com/mimi-net/miminet/tree/main/back/tests/test_json).
  
---

## ☑️ <a name="testing"></a> Тестирование

### <a name="frontend-test"></a> Frontend
Тестирование фронтенда работает путем имитации действий пользователя (кликов, ввода текста, навигации) с помощью автоматизированного управления браузером. Браузер(ы) находятся в специальном докер-контейнере(ах), ими управляет другой докер-контейнер (*selenium-hub*).

#### Основное:
- Всё, что связано с тестированием фронтенда, находится в каталоге ```front/tests```.
- Каталог ```docker``` хранит файлы, необходимые для запуска докер-контейнеров, которые позволяют имитировать действия пользователя на сайте.
- В каталоге ```utils``` находятся файлы, необходимые для написания тестов:
    - *checkers.py* — содержит класс, сравнивающий построенную сеть с образцом по заданным параметрам.
    - *locators.py* — содержит специальную структуру, в которой находятся все используемые в тесах имена веб-элементов Miminet. Если хотите добавить тест на новую функцию, не забудьте обновить этот файл.
    - *networks.py* — содержит классы, позволяющие быстро конфигурировать сети Miminet. С примерами использования этих классов можно ознакомиться в основном каталоге ```front/tests```.
- Самый важный файл во всей тестирующей системе — ```conftest.py```, в нём определены ключевые [фикстуры](https://docs.pytest.org/en/stable/explanation/fixtures.html), позволяющие писать тесты. Также функции из этого файла позволяют писать тесты быстрее и безопаснее.

#### Запуск:
1. В ```front/.env``` файле должно быть выставлено: ```MODE=dev```.
2. Запуск контейнеров: ```sh front/tests/docker/run.sh```
3. Запуск тестов: ```pytest front/tests```.

Запуск без Docker (rootless podman): [DEVELOPMENT.md](docs/DEVELOPMENT.md).

#### Набор на Playwright

В ```front/tests/playwright``` лежит тот же набор E2E-тестов, переписанный на [Playwright](https://playwright.dev/python/). Он работает параллельно с основным: Selenium-тесты остаются на месте, оба набора проверяют одно и то же.

Отличия: браузер запускается как обычный процесс, поэтому ```selenium-hub``` и контейнер с Chrome не нужны, а весь набор проходит примерно за минуту вместо пяти.

Первоначальная установка (один раз):
```bash
uv sync                              # поставит pytest-playwright
uv run playwright install chromium   # ~658 МБ на диске
```

Запуск — из корня репозитория:
```bash
sh front/tests/playwright/run.sh                 # весь набор в 4 процесса
sh front/tests/playwright/run.sh test_vlan.py    # один файл
sh front/tests/playwright/run.sh . --headed      # с видимым браузером
```

Скрипт сам подставляет адрес и число воркеров; переопределяются переменными ```TEST_TARGET_HOST``` и ```WORKERS```. То же самое вручную:
```bash
cd front/tests/playwright
TEST_TARGET_HOST=127.0.0.1 uv run pytest . -n 4
```

- ```-n 4``` — тесты в четыре параллельных процесса. Больше брать не стоит: на восьми воркерах тесты начинают падать из-за конкуренции за одну учётную запись.
- ```TEST_TARGET_HOST=127.0.0.1``` нужен при запуске с хоста: адрес по умолчанию (```172.18.0.2```) — это nginx внутри docker-сети, снаружи он отдаёт 502.
- ```--headed``` показывает браузер, ```--slowmo 500``` замедляет действия — удобно при отладке падающего теста.

Подробности — в [docs/FUNCTIONAL_TESTS.md](docs/FUNCTIONAL_TESTS.md): что покрывает каждый тест, чем порт отличается от оригинала и с какими особенностями пришлось столкнуться.

### <a name="backend-test"></a> Backend
1. Установка необходимых пакетов (требуется [uv](https://docs.astral.sh/uv/)):
```bash
uv sync --project back
source .venv/bin/activate
```
2. Запуск тестов:
```bash
sudo bash
source .venv/bin/activate
cd back/tests
export PYTHONPATH=$PYTHONPATH:../src
pytest .
```
> Для mininet обязательно нужен root!

Что покрывают тесты бэкенда, какие из них требуют root, а какие запускаются за секунду без Mininet — в [docs/BACKEND_TESTS.md](docs/BACKEND_TESTS.md).

