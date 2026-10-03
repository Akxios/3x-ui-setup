<!doctype html>
<!-- Managed by 3x-ui-setup -->
<html lang="ru">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#0b1220" />
        <title>Генератор чисел · {{DOMAIN}}</title>
        <style>
            :root {
                color-scheme: dark;
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
                color: #edf3ff;
                background:
                    radial-gradient(
                        circle at 15% 5%,
                        #253c5f 0,
                        transparent 34%
                    ),
                    radial-gradient(
                        circle at 90% 90%,
                        #182e48 0,
                        transparent 33%
                    ),
                    #0b1220;
            }
            button,
            input {
                font: inherit;
            }
            button {
                cursor: pointer;
            }
            button:focus-visible,
            input:focus-visible {
                outline: 3px solid #70d9d3;
                outline-offset: 3px;
            }
            .shell {
                width: min(1120px, calc(100% - 40px));
                margin: 0 auto;
            }
            header {
                border-bottom: 1px solid #ffffff1c;
                background: #0b1220a8;
            }
            header .shell {
                min-height: 76px;
                display: flex;
                align-items: center;
                justify-content: space-between;
                gap: 18px;
            }
            .brand {
                display: flex;
                align-items: center;
                gap: 13px;
                min-width: 0;
            }
            .mark {
                width: 41px;
                height: 41px;
                display: grid;
                place-items: center;
                border: 1px solid #5c8aa6;
                border-radius: 12px;
                color: #70d9d3;
                font-weight: 800;
                font-size: 22px;
            }
            .brand strong {
                display: block;
                overflow-wrap: anywhere;
            }
            .brand small,
            .header-note {
                color: #92a9bd;
                font-size: 12px;
                letter-spacing: 0.12em;
                text-transform: uppercase;
            }
            main {
                padding: 56px 0 72px;
            }
            .eyebrow {
                margin: 0 0 12px;
                color: #78dcd5;
                font-size: 12px;
                font-weight: 800;
                letter-spacing: 0.22em;
                text-transform: uppercase;
            }
            h1 {
                max-width: 760px;
                margin: 0;
                font-size: clamp(38px, 6vw, 72px);
                line-height: 1.04;
                letter-spacing: -0.055em;
            }
            .intro {
                max-width: 680px;
                margin: 18px 0 34px;
                color: #afbed0;
                line-height: 1.65;
            }
            .layout {
                display: grid;
                grid-template-columns: minmax(0, 1.5fr) minmax(265px, 0.8fr);
                gap: 20px;
            }
            .card {
                border: 1px solid #ffffff20;
                border-radius: 23px;
                background: #101d30db;
                box-shadow: 0 25px 65px #0004;
            }
            .generator {
                padding: clamp(22px, 4vw, 38px);
            }
            .label {
                color: #a9bad0;
                font-size: 12px;
                font-weight: 750;
                letter-spacing: 0.14em;
                text-transform: uppercase;
            }
            .hero-number {
                min-height: 140px;
                display: flex;
                align-items: center;
                overflow-wrap: anywhere;
                color: #9df4e9;
                font-size: clamp(52px, 10vw, 106px);
                font-weight: 800;
                line-height: 1;
                letter-spacing: -0.075em;
                font-variant-numeric: tabular-nums;
                text-shadow: 0 0 55px #4ce2cf4d;
            }
            .range-note {
                margin: 0 0 29px;
                color: #8da6ba;
            }
            form {
                border-top: 1px solid #ffffff1b;
                padding-top: 26px;
            }
            .fields {
                display: grid;
                grid-template-columns: repeat(3, minmax(0, 1fr));
                gap: 13px;
            }
            .field label {
                display: block;
                margin-bottom: 8px;
                color: #c7d4e3;
                font-size: 13px;
                font-weight: 700;
            }
            .field input {
                width: 100%;
                min-width: 0;
                padding: 13px 14px;
                border: 1px solid #446078;
                border-radius: 11px;
                color: #fff;
                background: #0c1728;
                font-variant-numeric: tabular-nums;
            }
            .options {
                display: flex;
                align-items: center;
                gap: 10px;
                margin: 21px 0;
                color: #c7d4e3;
                font-size: 14px;
            }
            .options input {
                width: 18px;
                height: 18px;
                accent-color: #72ddd2;
            }
            .buttons {
                display: flex;
                flex-wrap: wrap;
                gap: 10px;
            }
            .primary,
            .secondary {
                min-height: 45px;
                padding: 11px 18px;
                border-radius: 11px;
                font-weight: 750;
            }
            .primary {
                border: 1px solid #9df4e9;
                color: #0b222a;
                background: #9df4e9;
            }
            .primary:hover {
                background: #c0fff5;
            }
            .secondary {
                border: 1px solid #526e84;
                color: #eaf2fa;
                background: transparent;
            }
            .secondary:hover {
                background: #ffffff13;
            }
            .status {
                min-height: 24px;
                margin: 18px 0 0;
                color: #9cb5c9;
                font-size: 13px;
            }
            .results {
                display: flex;
                flex-wrap: wrap;
                gap: 9px;
                margin-top: 10px;
            }
            .pill {
                padding: 9px 12px;
                border: 1px solid #427a87;
                border-radius: 9px;
                color: #d9fffa;
                background: #123541;
                font-variant-numeric: tabular-nums;
            }
            .history {
                padding: 25px;
            }
            .history h2 {
                margin: 0 0 5px;
                font-size: 22px;
            }
            .history p {
                margin: 0 0 22px;
                color: #9fb3c5;
                font-size: 13px;
                line-height: 1.55;
            }
            .history-list {
                display: grid;
                gap: 10px;
            }
            .history-item {
                padding: 13px 14px;
                border: 1px solid #ffffff1b;
                border-radius: 11px;
                background: #0b1829;
            }
            .history-item strong {
                display: block;
                overflow-wrap: anywhere;
                font-size: 14px;
                font-variant-numeric: tabular-nums;
            }
            .history-item small {
                color: #8da6ba;
            }
            .empty {
                padding: 26px 12px;
                border: 1px dashed #52657a;
                border-radius: 11px;
                color: #9fb3c5;
                text-align: center;
            }
            .clear {
                margin-top: 22px;
                padding: 0;
                border: 0;
                color: #a8bdcf;
                background: transparent;
                text-decoration: underline;
                text-underline-offset: 3px;
            }
            footer {
                margin-top: 28px;
                color: #839bb1;
                font-size: 12px;
                line-height: 1.6;
            }
            @media (max-width: 780px) {
                .layout {
                    grid-template-columns: 1fr;
                }
                main {
                    padding-top: 40px;
                }
            }
            @media (max-width: 510px) {
                .fields {
                    grid-template-columns: repeat(2, 1fr);
                }
                .field:last-child {
                    grid-column: 1 / -1;
                }
                .header-note {
                    display: none;
                }
            }
        </style>
    </head>
    <body>
        <header>
            <div class="shell">
                <div class="brand">
                    <div class="mark" aria-hidden="true">#</div>
                    <div>
                        <small>Ваш домен</small><strong>{{DOMAIN}}</strong>
                    </div>
                </div>
                <div class="header-note">Числа без лишних вопросов</div>
            </div>
        </header>
        <main class="shell">
            <p class="eyebrow">Локальный инструмент</p>
            <h1>Случайное число — за секунду.</h1>
            <p class="intro">
                Задайте диапазон, количество и нажмите кнопку. Результаты
                появляются здесь же, а небольшая история остаётся только в вашем
                браузере.
            </p>
            <div class="layout">
                <section
                    class="card generator"
                    aria-labelledby="generator-title"
                >
                    <div class="label" id="generator-title">
                        Последний результат
                    </div>
                    <div class="hero-number" id="featured" aria-live="polite">
                        —
                    </div>
                    <p class="range-note" id="range-note">
                        Диапазон от 1 до 100
                    </p>
                    <form id="generator-form">
                        <div class="fields">
                            <div class="field">
                                <label for="minimum">От</label
                                ><input
                                    id="minimum"
                                    type="number"
                                    min="-1000000"
                                    max="1000000"
                                    step="1"
                                    value="1"
                                    required
                                />
                            </div>
                            <div class="field">
                                <label for="maximum">До</label
                                ><input
                                    id="maximum"
                                    type="number"
                                    min="-1000000"
                                    max="1000000"
                                    step="1"
                                    value="100"
                                    required
                                />
                            </div>
                            <div class="field">
                                <label for="quantity">Сколько чисел</label
                                ><input
                                    id="quantity"
                                    type="number"
                                    min="1"
                                    max="50"
                                    step="1"
                                    value="1"
                                    required
                                />
                            </div>
                        </div>
                        <label class="options"
                            ><input id="unique" type="checkbox" /> Без
                            повторений в одной генерации</label
                        >
                        <div class="buttons">
                            <button class="primary" type="submit">
                                Сгенерировать →</button
                            ><button
                                class="secondary"
                                id="copy"
                                type="button"
                                disabled
                            >
                                Копировать
                            </button>
                        </div>
                        <p
                            class="status"
                            id="status"
                            role="status"
                            aria-live="polite"
                        >
                            Готово к генерации.
                        </p>
                        <div
                            class="results"
                            id="results"
                            aria-label="Сгенерированные числа"
                        ></div>
                    </form>
                </section>
                <aside class="card history" aria-labelledby="history-title">
                    <h2 id="history-title">Недавние серии</h2>
                    <p>Последние восемь результатов в этом браузере.</p>
                    <div class="history-list" id="history-list"></div>
                    <button class="clear" id="clear-history" type="button">
                        Очистить историю
                    </button>
                </aside>
            </div>
            <footer>
                Сайт не отправляет диапазон, числа или историю на сервер.
                Историю можно очистить в любой момент.
            </footer>
        </main>
        <script>
            (() => {
                "use strict";
                const key = "3x-ui-setup-numbers-v1";
                const byId = (id) => document.getElementById(id);
                const featured = byId("featured");
                const results = byId("results");
                const historyList = byId("history-list");
                const status = byId("status");
                let current = [];
                let history = [];
                try {
                    const saved = JSON.parse(localStorage.getItem(key));
                    if (Array.isArray(saved))
                        history = saved
                            .filter(
                                (item) =>
                                    item &&
                                    Array.isArray(item.numbers) &&
                                    item.numbers.every(Number.isSafeInteger) &&
                                    typeof item.label === "string",
                            )
                            .slice(0, 8);
                } catch (_) {
                    /* Browser storage is optional. */
                }
                function save() {
                    try {
                        localStorage.setItem(key, JSON.stringify(history));
                    } catch (_) {
                        status.textContent =
                            "История недоступна в этом браузере; генерация работает.";
                    }
                }
                function randomInt(minimum, maximum) {
                    if (!window.crypto || !window.crypto.getRandomValues)
                        throw new Error(
                            "В этом браузере недоступен генератор случайных чисел.",
                        );
                    const span = maximum - minimum + 1;
                    const limit = Math.floor(4294967296 / span) * span;
                    const buffer = new Uint32Array(1);
                    do {
                        window.crypto.getRandomValues(buffer);
                    } while (buffer[0] >= limit);
                    return minimum + (buffer[0] % span);
                }
                function renderHistory() {
                    historyList.replaceChildren();
                    if (!history.length) {
                        const empty = document.createElement("div");
                        empty.className = "empty";
                        empty.textContent = "Пока нет результатов";
                        historyList.append(empty);
                        return;
                    }
                    for (const item of history) {
                        const row = document.createElement("div");
                        const numbers = document.createElement("strong");
                        const label = document.createElement("small");
                        row.className = "history-item";
                        numbers.textContent = item.numbers
                            .join(", ")
                            .slice(0, 180);
                        label.textContent = item.label.slice(0, 80);
                        row.append(numbers, label);
                        historyList.append(row);
                    }
                }
                byId("generator-form").addEventListener("submit", (event) => {
                    event.preventDefault();
                    const minimum = Number(byId("minimum").value);
                    const maximum = Number(byId("maximum").value);
                    const quantity = Number(byId("quantity").value);
                    const unique = byId("unique").checked;
                    if (
                        ![minimum, maximum, quantity].every(
                            Number.isSafeInteger,
                        ) ||
                        minimum < -1000000 ||
                        maximum > 1000000 ||
                        minimum > maximum ||
                        quantity < 1 ||
                        quantity > 50
                    ) {
                        status.textContent =
                            "Проверьте диапазон (−1 000 000…1 000 000) и количество (1…50).";
                        return;
                    }
                    if (unique && quantity > maximum - minimum + 1) {
                        status.textContent =
                            "В диапазоне меньше уникальных чисел, чем вы запросили.";
                        return;
                    }
                    try {
                        const seen = new Set();
                        current = [];
                        while (current.length < quantity) {
                            const value = randomInt(minimum, maximum);
                            if (unique && seen.has(value)) continue;
                            current.push(value);
                            seen.add(value);
                        }
                    } catch (error) {
                        status.textContent = error.message;
                        return;
                    }
                    featured.textContent = String(current[0]);
                    byId("range-note").textContent =
                        `Диапазон от ${minimum} до ${maximum}`;
                    results.replaceChildren();
                    for (const value of current) {
                        const pill = document.createElement("span");
                        pill.className = "pill";
                        pill.textContent = String(value);
                        results.append(pill);
                    }
                    byId("copy").disabled = false;
                    status.textContent =
                        current.length === 1
                            ? "Число готово."
                            : `Готово: ${current.length} чисел.`;
                    history.unshift({
                        numbers: current.slice(),
                        label: `${minimum}…${maximum} · ${new Date().toLocaleString("ru-RU")}`,
                    });
                    history = history.slice(0, 8);
                    save();
                    renderHistory();
                });
                byId("copy").addEventListener("click", async () => {
                    if (!current.length) return;
                    try {
                        await navigator.clipboard.writeText(current.join(", "));
                        status.textContent = "Результат скопирован.";
                    } catch (_) {
                        status.textContent =
                            "Не удалось скопировать автоматически. Выделите числа на странице.";
                    }
                });
                byId("clear-history").addEventListener("click", () => {
                    if (
                        !history.length ||
                        !window.confirm(
                            "Очистить историю генератора в этом браузере?",
                        )
                    )
                        return;
                    history = [];
                    save();
                    renderHistory();
                    status.textContent = "История очищена.";
                });
                renderHistory();
            })();
        </script>
    </body>
</html>
