<!doctype html>
<!-- Managed by 3x-ui-setup -->
<html lang="ru">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#eee7d9" />
        <title>Блокнот · {{DOMAIN}}</title>
        <style>
            :root {
                color-scheme: light;
                font-family:
                    Inter,
                    system-ui,
                    -apple-system,
                    "Segoe UI",
                    sans-serif;
            }
            * {
                box-sizing: border-box;
            }
            body {
                margin: 0;
                min-height: 100vh;
                color: #26312c;
                background:
                    radial-gradient(
                        circle at 80% 10%,
                        #fff9ed 0,
                        transparent 30%
                    ),
                    #eee7d9;
            }
            button,
            input,
            textarea {
                font: inherit;
            }
            button {
                cursor: pointer;
            }
            button:focus-visible,
            input:focus-visible,
            textarea:focus-visible {
                outline: 3px solid #a8a053;
                outline-offset: 3px;
            }
            .shell {
                width: min(1120px, calc(100% - 40px));
                margin: 0 auto;
            }
            header {
                border-bottom: 1px solid #c9c2ae;
                background: #f6f0e4ba;
            }
            header .shell {
                min-height: 77px;
                display: flex;
                align-items: center;
                justify-content: space-between;
                gap: 20px;
            }
            .brand {
                display: flex;
                align-items: center;
                gap: 12px;
                min-width: 0;
            }
            .mark {
                width: 40px;
                height: 40px;
                display: grid;
                place-items: center;
                border: 1px solid #b7a981;
                border-radius: 10px;
                color: #486651;
                font-size: 22px;
            }
            .brand strong {
                display: block;
                overflow-wrap: anywhere;
            }
            .brand small,
            .header-note {
                color: #757c6d;
                font-size: 12px;
                letter-spacing: 0.12em;
                text-transform: uppercase;
            }
            main {
                padding: 52px 0 72px;
            }
            .eyebrow {
                margin: 0 0 12px;
                color: #557560;
                font-size: 12px;
                font-weight: 800;
                letter-spacing: 0.2em;
                text-transform: uppercase;
            }
            h1 {
                margin: 0;
                font-size: clamp(40px, 6vw, 70px);
                line-height: 1.02;
                letter-spacing: -0.055em;
            }
            .intro {
                max-width: 680px;
                margin: 16px 0 31px;
                color: #657066;
                line-height: 1.6;
            }
            .workspace {
                display: grid;
                grid-template-columns: minmax(0, 1fr) 265px;
                gap: 20px;
                align-items: start;
            }
            .paper {
                min-height: 540px;
                padding: clamp(22px, 4vw, 38px);
                border: 1px solid #d5cab0;
                border-radius: 20px;
                background: #fffdf6;
                box-shadow: 0 20px 55px #51422c1d;
            }
            .paper-top {
                display: flex;
                align-items: center;
                justify-content: space-between;
                gap: 12px;
                padding-bottom: 19px;
                border-bottom: 1px solid #e2dac6;
            }
            .paper-tag {
                color: #657568;
                font-size: 12px;
                font-weight: 750;
                letter-spacing: 0.13em;
                text-transform: uppercase;
            }
            .status {
                color: #657568;
                font-size: 12px;
                text-align: right;
            }
            #note-title {
                display: block;
                width: 100%;
                margin: 27px 0 17px;
                padding: 0;
                border: 0;
                color: #2a352d;
                background: transparent;
                font-size: clamp(25px, 4vw, 38px);
                font-weight: 760;
                letter-spacing: -0.035em;
            }
            #note-title::placeholder {
                color: #adb4a8;
            }
            #note-body {
                display: block;
                width: 100%;
                min-height: 375px;
                padding: 0;
                resize: vertical;
                border: 0;
                color: #3d473d;
                background: repeating-linear-gradient(
                    transparent,
                    transparent 31px,
                    #e7e4d9 32px
                );
                font-size: 16px;
                line-height: 32px;
            }
            #note-body::placeholder {
                color: #a6afa3;
            }
            .paper-bottom {
                display: flex;
                flex-wrap: wrap;
                gap: 18px;
                padding-top: 18px;
                border-top: 1px solid #e2dac6;
                color: #899082;
                font-size: 12px;
            }
            .tools {
                padding: 23px;
                border: 1px solid #d1c5ae;
                border-radius: 20px;
                background: #e8dfce;
            }
            .tools h2 {
                margin: 0 0 7px;
                font-size: 20px;
            }
            .tools p {
                margin: 0 0 22px;
                color: #657066;
                font-size: 13px;
                line-height: 1.55;
            }
            .tool {
                display: block;
                width: 100%;
                margin-top: 10px;
                padding: 12px 15px;
                border: 1px solid #aab5a5;
                border-radius: 10px;
                color: #284a3a;
                background: #f7f4e9;
                text-align: left;
                font-weight: 700;
            }
            .tool:hover {
                background: #fffdf5;
            }
            .tool.danger {
                border-color: #d0b7aa;
                color: #925a48;
                background: transparent;
            }
            .tool.danger:hover {
                background: #f6e8df;
            }
            .privacy {
                margin-top: 23px;
                padding: 16px;
                border-radius: 11px;
                color: #44624e;
                background: #dbe8d4;
                font-size: 13px;
                line-height: 1.55;
            }
            .privacy strong {
                display: block;
                margin-bottom: 4px;
            }
            .fine {
                margin-top: 24px;
                color: #787e70;
                font-size: 12px;
                line-height: 1.6;
            }
            @media (max-width: 800px) {
                .workspace {
                    grid-template-columns: 1fr;
                }
                .tools {
                    display: grid;
                    grid-template-columns: repeat(3, 1fr);
                    column-gap: 10px;
                }
                .tools h2,
                .tools p,
                .privacy {
                    grid-column: 1 / -1;
                }
            }
            @media (max-width: 560px) {
                main {
                    padding-top: 38px;
                }
                .tools {
                    display: block;
                }
                .header-note {
                    display: none;
                }
                .paper-top {
                    align-items: start;
                }
            }
        </style>
    </head>
    <body>
        <header>
            <div class="shell">
                <div class="brand">
                    <div class="mark" aria-hidden="true">✎</div>
                    <div>
                        <small>Ваш домен</small><strong>{{DOMAIN}}</strong>
                    </div>
                </div>
                <div class="header-note">Тихое место для мыслей</div>
            </div>
        </header>
        <main class="shell">
            <p class="eyebrow">Ваше пространство</p>
            <h1>Запишите, чтобы не забыть.</h1>
            <p class="intro">
                Простой блокнот для идей, планов и заметок. Пишите свободно:
                текст автоматически остаётся в этом браузере.
            </p>
            <div class="workspace">
                <section class="paper" aria-label="Заметка">
                    <div class="paper-top">
                        <span class="paper-tag">Личная заметка</span
                        ><span
                            class="status"
                            id="save-status"
                            role="status"
                            aria-live="polite"
                            >Готово к записи</span
                        >
                    </div>
                    <label
                        for="note-title"
                        class="paper-tag"
                        style="
                            position: absolute;
                            width: 1px;
                            height: 1px;
                            overflow: hidden;
                            clip-path: inset(50%);
                        "
                        >Заголовок заметки</label
                    >
                    <input
                        id="note-title"
                        type="text"
                        maxlength="120"
                        autocomplete="off"
                        placeholder="Заголовок заметки"
                    />
                    <label
                        for="note-body"
                        class="paper-tag"
                        style="
                            position: absolute;
                            width: 1px;
                            height: 1px;
                            overflow: hidden;
                            clip-path: inset(50%);
                        "
                        >Текст заметки</label
                    >
                    <textarea
                        id="note-body"
                        maxlength="500000"
                        spellcheck="true"
                        placeholder="Начните писать здесь..."
                    ></textarea>
                    <div class="paper-bottom">
                        <span id="count">0 слов · 0 символов</span
                        ><span id="last-saved">Пока не сохранялось</span>
                    </div>
                </section>
                <aside class="tools" aria-labelledby="tools-title">
                    <h2 id="tools-title">С заметкой</h2>
                    <p>
                        Можно сохранить копию в файл, открыть текстовый файл или
                        начать заново.
                    </p>
                    <button class="tool" id="export" type="button">
                        ↓ Скачать .txt
                    </button>
                    <button class="tool" id="import-button" type="button">
                        ↑ Открыть .txt
                    </button>
                    <input
                        id="import-file"
                        type="file"
                        accept=".txt,text/plain"
                        hidden
                    />
                    <button class="tool danger" id="clear" type="button">
                        Очистить заметку
                    </button>
                    <div class="privacy">
                        <strong>Только в вашем браузере</strong>Этот шаблон не
                        отправляет заметку на сервер. Для резервной копии
                        скачайте файл. Не храните здесь пароли.
                    </div>
                </aside>
            </div>
            <p class="fine">
                Если очистить данные браузера или открыть сайт на другом
                устройстве, заметка там не появится. Экспортируйте её перед
                очисткой браузера.
            </p>
        </main>
        <script>
            (() => {
                "use strict";
                const key = "3x-ui-setup-notepad-v1";
                const byId = (id) => document.getElementById(id);
                const title = byId("note-title");
                const body = byId("note-body");
                const status = byId("save-status");
                const exportPrefix = "Заголовок заметки: ";
                let timer;
                let dirty = false;
                function updateCount() {
                    const words = body.value.trim()
                        ? body.value.trim().split(/\s+/u).length
                        : 0;
                    byId("count").textContent =
                        `${words} слов · ${body.value.length} символов`;
                }
                function save() {
                    clearTimeout(timer);
                    const savedAt = Date.now();
                    try {
                        localStorage.setItem(
                            key,
                            JSON.stringify({
                                title: title.value,
                                body: body.value,
                                savedAt,
                            }),
                        );
                        dirty = false;
                        status.textContent = "Сохранено в браузере";
                        byId("last-saved").textContent = new Date(
                            savedAt,
                        ).toLocaleString("ru-RU");
                    } catch (_) {
                        status.textContent = "Браузер не сохранил заметку";
                        byId("last-saved").textContent =
                            "Скачайте копию через меню";
                    }
                }
                function scheduleSave() {
                    dirty = true;
                    updateCount();
                    status.textContent = "Сохраняем…";
                    clearTimeout(timer);
                    timer = setTimeout(save, 300);
                }
                try {
                    const saved = JSON.parse(localStorage.getItem(key));
                    if (saved && typeof saved === "object") {
                        title.value =
                            typeof saved.title === "string"
                                ? saved.title.slice(0, 120)
                                : "";
                        body.value =
                            typeof saved.body === "string"
                                ? saved.body.slice(0, 500000)
                                : "";
                        if (
                            Number.isSafeInteger(saved.savedAt) &&
                            saved.savedAt > 0
                        ) {
                            byId("last-saved").textContent = new Date(
                                saved.savedAt,
                            ).toLocaleString("ru-RU");
                        }
                        status.textContent = "Заметка восстановлена";
                    }
                } catch (_) {
                    status.textContent = "Локальное хранилище недоступно";
                }
                title.addEventListener("input", scheduleSave);
                body.addEventListener("input", scheduleSave);
                window.addEventListener("pagehide", () => {
                    if (dirty) save();
                });
                byId("export").addEventListener("click", () => {
                    const file = new Blob(
                        [
                            title.value
                                ? `${exportPrefix}${title.value}\n\n${body.value}`
                                : body.value,
                        ],
                        { type: "text/plain;charset=utf-8" },
                    );
                    const url = URL.createObjectURL(file);
                    const link = document.createElement("a");
                    link.href = url;
                    link.download = "notes-{{DOMAIN}}.txt";
                    link.click();
                    setTimeout(() => URL.revokeObjectURL(url), 1000);
                    status.textContent = "Копия скачана";
                });
                byId("import-button").addEventListener("click", () =>
                    byId("import-file").click(),
                );
                byId("import-file").addEventListener(
                    "change",
                    async (event) => {
                        const file =
                            event.target.files && event.target.files[0];
                        if (!file) return;
                        if (file.size > 2000000) {
                            status.textContent =
                                "Файл слишком большой (до 2 МБ).";
                            event.target.value = "";
                            return;
                        }
                        try {
                            const text = await file.text();
                            const divider = text.indexOf("\n\n");
                            const hasTitle =
                                text.startsWith(exportPrefix) &&
                                divider > exportPrefix.length &&
                                divider <= exportPrefix.length + 120;
                            const importedTitle = hasTitle
                                ? text.slice(exportPrefix.length, divider)
                                : file.name
                                      .replace(/\.txt$/iu, "")
                                      .slice(0, 120);
                            const importedBody = hasTitle
                                ? text.slice(divider + 2)
                                : text;
                            if (importedBody.length > 500000) {
                                status.textContent =
                                    "Текст слишком длинный (до 500 000 символов).";
                                return;
                            }
                            if (
                                (title.value || body.value) &&
                                !window.confirm(
                                    "Заменить текущую заметку текстом из файла? Скачайте копию, если она нужна.",
                                )
                            )
                                return;
                            title.value = importedTitle;
                            body.value = importedBody;
                            scheduleSave();
                            status.textContent = "Файл открыт";
                        } catch (_) {
                            status.textContent = "Не удалось открыть файл";
                        } finally {
                            event.target.value = "";
                        }
                    },
                );
                byId("clear").addEventListener("click", () => {
                    if (
                        !window.confirm(
                            "Удалить заметку из этого браузера? Сначала скачайте копию, если она нужна.",
                        )
                    )
                        return;
                    clearTimeout(timer);
                    dirty = false;
                    title.value = "";
                    body.value = "";
                    try {
                        localStorage.removeItem(key);
                        status.textContent = "Заметка удалена";
                    } catch (_) {
                        status.textContent =
                            "Не удалось очистить локальное хранилище";
                    }
                    byId("last-saved").textContent = "Пока не сохранялось";
                    updateCount();
                });
                updateCount();
            })();
        </script>
    </body>
</html>
