# 4.3. HTTP-клиент без HttpClient

**Язык:** F#  
**Тема:** Клиент-серверное взаимодействие  
**Видео с демонстрацией:** [Ссылка на видео](https://drive.google.com/file/d/1x9_YziRHVh2AoF2eilyOwn-6AjCogFkU/view?usp=sharing)

## Описание задачи

Программа реализует HTTP-клиент на F# без использования высокоуровневого `HttpClient` и специализированных HTTP-библиотек.

Реализованы:
- Формирование HTTP/1.1-запросов методами GET, HEAD и POST.
- Установка TCP-соединения с сервером.
- Поддержка HTTPS через `SslStream`.
- Чтение HTTP-статусов и заголовков ответа.
- Обработка тела ответа через `Content-Length`, `Transfer-Encoding: chunked` или закрытие соединения.
- Обработка ошибок и некорректных запросов.

Для демонстрации предусмотрен локальный HTTP-сервер.

## Запуск

**Среда:** F#, .NET SDK 10, Windows PowerShell.

F# входит в .NET SDK. Проверка установки:

```powershell
dotnet --version
dotnet fsi --help
```

Открыть PowerShell в папке проекта и перейти в `src`:

```powershell
cd src
```

**Запуск автоматических тестов:**

```powershell
dotnet fsi .\tests.fsx
```

**Запуск сервера (первое окно PowerShell):**

```powershell
dotnet fsi .\server.fsx
```

Сервер работает по адресу `127.0.0.1:8085`.

**Запуск клиента (второе окно PowerShell):**

GET-запрос:

```powershell
dotnet fsi .\client.fsx GET http://127.0.0.1:8085/hello
```

POST-запрос:

```powershell
dotnet fsi .\client.fsx POST http://127.0.0.1:8085/echo "Hello F#"
```

Получение chunked-ответа:

```powershell
dotnet fsi .\client.fsx GET http://127.0.0.1:8085/chunked
```

Проверка HTTP-статуса 404:

```powershell
dotnet fsi .\client.fsx GET http://127.0.0.1:8085/unknown
```

Для остановки сервера используется `Ctrl+C`.

## Реализация

Основные компоненты:

- `HttpCore.fsx` — формирование HTTP-запросов, TCP/TLS-соединения и разбор ответов.
- `client.fsx` — обработка аргументов командной строки и вывод результатов.
- `DemoServer.fsx` — локальный тестовый HTTP-сервер.
- `server.fsx` — запуск сервера.
- `tests.fsx` — автоматическое тестирование.

Основные функции:

- `request` — формирование и отправка HTTP-запроса.
- `readLine`, `readHeaders` — чтение статусной строки и заголовков.
- `readExactly` — чтение заданного количества байтов.
- `readChunked` — обработка ответа, передаваемого блоками.
- `readUntilClose` — чтение данных до закрытия соединения.
- `serveClient` — обработка запросов на тестовом сервере.

## Тестирование

Предусмотрено 16 автоматических тестов, проверяющих:

- GET, HEAD и POST-запросы.
- Корректность HTTP-заголовков и статусов.
- Получение JSON и UTF-8.
- Обработку `Content-Length` и chunked-ответов.
- Пустое тело ответа и чтение до закрытия соединения.
- Статус 404.
- Некорректные методы и неподдерживаемые URL.

Ожидаемый итог успешного тестирования:

```text
Passed: 16/16
```

## Структура проекта

```text
4.3/
├── src/
│   ├── HttpCore.fsx
│   ├── DemoServer.fsx
│   ├── client.fsx
│   ├── server.fsx
│   └── tests.fsx
└── README.md
```

Программа поддерживает HTTP/1.1. Редиректы, gzip-сжатие и HTTP/2 не реализованы. Максимальный размер тела ответа — 2 МБ.
