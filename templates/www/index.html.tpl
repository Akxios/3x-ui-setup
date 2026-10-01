<!doctype html>
<!-- Managed by 3x-ui-setup -->
<html lang="ru">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="theme-color" content="#15231d">
    <title>Племя · {{DOMAIN}}</title>
    <style>
        :root { color-scheme: dark; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; color: #f6f0df; background: #101d18; }
        button { font: inherit; cursor: pointer; }
        button:focus-visible { outline: 3px solid #eac178; outline-offset: 3px; }
        .shell { width: min(1120px, calc(100% - 40px)); margin: 0 auto; }
        header { border-bottom: 1px solid #ffffff1c; background: #11211b; }
        header .shell { min-height: 76px; display: flex; align-items: center; justify-content: space-between; gap: 16px; }
        .brand { display: flex; align-items: center; gap: 13px; min-width: 0; }
        .mark { width: 38px; height: 38px; display: grid; place-items: center; border: 1px solid #b69b66; border-radius: 11px; color: #e9c77c; font-size: 23px; }
        .brand-text { display: grid; min-width: 0; }
        .brand-text strong { font-size: 17px; overflow-wrap: anywhere; }
        .brand-text small, .top-note { color: #a8b7a8; font-size: 12px; letter-spacing: .08em; text-transform: uppercase; }
        main { padding: 48px 0 72px; }
        .intro { display: flex; align-items: end; justify-content: space-between; gap: 20px; margin-bottom: 24px; }
        .eyebrow { margin: 0 0 10px; color: #dfbd7e; font-size: 12px; font-weight: 700; letter-spacing: .17em; text-transform: uppercase; }
        h1 { margin: 0; font-size: clamp(34px, 5vw, 58px); line-height: 1.05; letter-spacing: -.045em; }
        .subtitle { margin: 14px 0 0; color: #b6c3b7; line-height: 1.55; }
        .reset { padding: 11px 15px; border: 1px solid #6f8876; border-radius: 10px; background: transparent; color: #e5e9db; white-space: nowrap; }
        .reset:hover { background: #ffffff13; }
        .board, .lower { display: grid; grid-template-columns: minmax(0, 1.55fr) minmax(285px, 1fr); gap: 20px; }
        .scene, .panel, .actions, .journal { border: 1px solid #ffffff20; border-radius: 20px; overflow: hidden; box-shadow: 0 18px 55px #0003; }
        .scene { min-height: 465px; position: relative; display: flex; flex-direction: column; justify-content: space-between; background: linear-gradient(#6c8b7a, #a4ae88 38%, #d6ba84 54%, #385543 55%, #1f3b31); }
        .sun { position: absolute; top: 65px; right: 18%; width: 110px; height: 110px; border-radius: 50%; background: #f8d698; box-shadow: 0 0 0 18px #f7d99a24, 0 0 85px #f7d99a8c; }
        .hill { position: absolute; bottom: 20%; width: 120%; height: 42%; border-radius: 50% 50% 0 0; }
        .hill.back { left: -34%; background: #6f8164; transform: rotate(-7deg); }
        .hill.front { right: -36%; bottom: 12%; background: #355946; transform: rotate(7deg); }
        .ground { position: absolute; inset: auto 0 0; height: 27%; background: linear-gradient(#254535, #172e28); }
        .hut { position: absolute; bottom: 17%; left: 15%; width: 155px; height: 110px; background: #a6754e; clip-path: polygon(50% 0, 100% 42%, 92% 100%, 8% 100%, 0 42%); filter: drop-shadow(8px 13px 4px #11271c80); }
        .hut::after { content: ""; position: absolute; bottom: 0; left: 42%; width: 20%; height: 42%; border-radius: 45% 45% 0 0; background: #342720; }
        .hut.two { left: 48%; bottom: 16%; transform: scale(.72); transform-origin: bottom left; background: #8d684c; }
        .fire { position: absolute; bottom: 14%; right: 21%; color: #ffca7f; font-size: 48px; filter: drop-shadow(0 0 14px #f5aa5f); }
        .scene-top, .scene-bottom { position: relative; z-index: 1; padding: 22px; }
        .scene-top { display: flex; justify-content: space-between; gap: 10px; }
        .tag { padding: 9px 12px; border: 1px solid #fff5; border-radius: 999px; background: #142b27bd; font-size: 13px; font-weight: 650; backdrop-filter: blur(8px); }
        .scene-bottom { background: linear-gradient(transparent, #0d201ce8); }
        .scene-bottom p { margin: 0 0 5px; color: #d1dccb; font-size: 13px; }
        .scene-bottom strong { display: block; font-size: clamp(25px, 3vw, 36px); letter-spacing: -.03em; }
        .panel, .actions, .journal { background: #1b3028; padding: 24px; }
        h2 { margin: 0 0 19px; font-size: 19px; letter-spacing: -.02em; }
        .stats { display: grid; grid-template-columns: 1fr 1fr; gap: 11px; }
        .stat { min-height: 103px; padding: 15px; border: 1px solid #ffffff1a; border-radius: 14px; background: #ffffff0a; }
        .stat span { display: block; color: #b9c9b8; font-size: 13px; }
        .stat strong { display: block; margin-top: 8px; font-size: 29px; line-height: 1; }
        .stat small { font-size: 12px; color: #b9c9b8; }
        .food-bar { height: 8px; margin-top: 10px; border-radius: 99px; background: #0d211a; overflow: hidden; }
        .food-bar i { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg, #cb9256, #ebc879); transition: width .3s; }
        .divider { height: 1px; background: #ffffff1d; margin: 23px 0; }
        .panel-note { color: #b7c7b8; font-size: 14px; line-height: 1.55; }
        .panel-note strong { color: #f4e5bd; }
        .lower { margin-top: 20px; }
        .buttons { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
        .action { min-height: 98px; padding: 15px; text-align: left; border: 1px solid #ffffff27; border-radius: 14px; background: #294638; color: #fff4dc; transition: transform .16s, background .16s; }
        .action:hover { transform: translateY(-2px); background: #355744; }
        .action.primary { background: #d6a566; border-color: #eac482; color: #1d271f; }
        .action.primary:hover { background: #e5b878; }
        .action strong, .action span { display: block; }
        .action strong { margin-bottom: 7px; font-size: 15px; }
        .action span { font-size: 12px; line-height: 1.35; opacity: .83; }
        .journal p { min-height: 66px; margin: 0; color: #d5dfcd; line-height: 1.55; }
        .privacy { margin: 22px 0 0; color: #aab9ab; font-size: 12px; }
        .privacy::before { content: "●  "; color: #8cbd8f; }
        @media (max-width: 800px) { .board, .lower { grid-template-columns: 1fr; } .scene { min-height: 390px; } }
        @media (max-width: 560px) { .shell { width: calc(100% - 28px); } main { padding-top: 34px; } .top-note { display: none; } .intro { align-items: start; flex-direction: column; } .buttons { grid-template-columns: 1fr; } .action { min-height: 72px; } }
        @media (prefers-reduced-motion: reduce) { *, *::before, *::after { transition: none !important; } }
    </style>
</head>
<body>
    <header><div class="shell"><div class="brand"><div class="mark" aria-hidden="true">ᛟ</div><div class="brand-text"><small>Ваш мир</small><strong>{{DOMAIN}}</strong></div></div><span class="top-note">Маленькая история одного племени</span></div></header>
    <main class="shell">
        <div class="intro"><div><p class="eyebrow">Мини-симулятор · Древний мир</p><h1>Племя у костра</h1><p class="subtitle">Собирайте припасы, кормите людей и встречайте новые времена.</p></div><button class="reset" id="reset" type="button">Создать новое племя</button></div>
        <div class="board">
            <section class="scene" aria-label="Поселение племени">
                <div class="sun" aria-hidden="true"></div><div class="hill back" aria-hidden="true"></div><div class="hill front" aria-hidden="true"></div><div class="ground" aria-hidden="true"></div><div class="hut" aria-hidden="true"></div><div class="hut two" aria-hidden="true"></div><div class="fire" aria-hidden="true">✦</div>
                <div class="scene-top"><span class="tag" id="season">Весна</span><span class="tag" id="year">100 г. до н. э.</span></div>
                <div class="scene-bottom"><p>На этой земле живёт</p><strong id="tribe-name">Племя Соснового ручья</strong></div>
            </section>
            <section class="panel" aria-labelledby="stats-title"><h2 id="stats-title">Жизнь поселения</h2><div class="stats">
                <div class="stat"><span>Мужчины</span><strong id="men">30</strong><small>жителей</small></div>
                <div class="stat"><span>Женщины</span><strong id="women">40</strong><small>жителей</small></div>
                <div class="stat"><span>Припасы</span><strong id="food">90</strong><div class="food-bar" aria-hidden="true"><i id="food-bar"></i></div></div>
                <div class="stat"><span>Настроение</span><strong id="morale">70%</strong><small id="morale-word">воодушевлённое</small></div>
            </div><div class="divider"></div><p class="panel-note">Сейчас в племени <strong id="total">70 человек</strong>. Чтобы пережить следующий сезон, им понадобятся припасы. История меняется только от ваших действий.</p></section>
        </div>
        <div class="lower"><section class="actions" aria-labelledby="actions-title"><h2 id="actions-title">Что сделаем?</h2><div class="buttons">
            <button class="action" id="gather" type="button"><strong>Собрать еду</strong><span>Пополнить общие запасы</span></button>
            <button class="action" id="feed" type="button"><strong>Накормить племя</strong><span>Потратить припасы и поднять дух</span></button>
            <button class="action primary" id="next" type="button"><strong>Следующий сезон →</strong><span>Время идёт, запасы тают</span></button>
        </div></section><section class="journal" aria-labelledby="journal-title"><h2 id="journal-title">Летопись</h2><p id="message" role="status" aria-live="polite">Люди развели первый костёр. Что принесёт им этот год?</p><div class="privacy">Прогресс хранится только в этом браузере</div></section></div>
    </main>
    <script>
        (() => {
            'use strict';
            const key = '3x-ui-setup-tribe-v1';
            const names = ['Соснового ручья', 'Тихой долины', 'Янтарного холма', 'Северного ветра', 'Золотой реки'];
            const seasons = ['Весна', 'Лето', 'Осень', 'Зима'];
            const byId = (id) => document.getElementById(id);
            const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
            const validInt = (value, fallback, min, max) => Number.isSafeInteger(value) && value >= min && value <= max ? value : fallback;
            const random = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
            const fresh = () => ({ name: names[random(0, names.length - 1)], men: 30, women: 40, food: 90, morale: 70, year: 100, season: 0, message: 'Люди развели первый костёр. Что принесёт им этот год?' });
            let state = fresh();
            try {
                const saved = JSON.parse(localStorage.getItem(key));
                if (saved && typeof saved === 'object' && names.includes(saved.name)) {
                    state = {
                        name: saved.name,
                        men: validInt(saved.men, 30, 0, 100000), women: validInt(saved.women, 40, 0, 100000),
                        food: validInt(saved.food, 90, 0, 1000000), morale: validInt(saved.morale, 70, 0, 100),
                        year: validInt(saved.year, 100, -999, 100), season: validInt(saved.season, 0, 0, 3),
                        message: typeof saved.message === 'string' ? saved.message.slice(0, 240) : ''
                    };
                }
            } catch (_) { /* Storage is optional. */ }
            function save() { try { localStorage.setItem(key, JSON.stringify(state)); } catch (_) { /* Private mode may block storage. */ } }
            function render() {
                const people = state.men + state.women;
                byId('tribe-name').textContent = 'Племя ' + state.name;
                byId('season').textContent = seasons[state.season];
                byId('year').textContent = state.year > 0 ? state.year + ' г. до н. э.' : (1 - state.year) + ' г. н. э.';
                byId('men').textContent = state.men; byId('women').textContent = state.women;
                byId('food').textContent = state.food;
                byId('food-bar').style.width = clamp(state.food / Math.max(people, 1) * 50, 0, 100) + '%';
                byId('morale').textContent = state.morale + '%';
                byId('morale-word').textContent = state.morale >= 70 ? 'воодушевлённое' : state.morale >= 35 ? 'спокойное' : 'тревожное';
                byId('total').textContent = people + ' человек';
                byId('message').textContent = state.message;
                save();
            }
            byId('gather').addEventListener('click', () => {
                if (!state.men && !state.women) { state.message = 'Племя опустело. Можно создать новое.'; render(); return; }
                const found = random(18, 36);
                state.food = Math.min(1000000, state.food + found);
                state.message = 'Собиратели вернулись с припасами: +' + found + ' еды.';
                render();
            });
            byId('feed').addEventListener('click', () => {
                const people = state.men + state.women;
                if (!people) { state.message = 'Некого кормить. Можно создать новое племя.'; render(); return; }
                const needed = Math.ceil(people / 2);
                if (state.food < needed) { state.message = 'Для общего ужина нужно ' + needed + ' еды. Сначала соберите припасы.'; render(); return; }
                state.food -= needed; state.morale = clamp(state.morale + 8, 0, 100);
                state.message = 'Все поели у костра. Настроение племени улучшилось.';
                render();
            });
            byId('next').addEventListener('click', () => {
                const people = state.men + state.women;
                if (!people) { state.message = 'История этого племени завершилась. Можно начать новую.'; render(); return; }
                const needed = Math.ceil(people * 0.6);
                if (state.food < needed) {
                    const lost = Math.min(people, Math.ceil((needed - state.food) / 3));
                    const lostMen = Math.min(state.men, Math.max(lost - state.women, Math.floor(lost / 2)));
                    state.men -= lostMen; state.women -= lost - lostMen; state.food = 0;
                    state.morale = clamp(state.morale - 18, 0, 100);
                    state.message = 'Не хватило еды. Племя потеряло ' + lost + ' человек.';
                } else {
                    state.food -= needed; state.morale = clamp(state.morale - 4, 0, 100);
                    state.message = 'Племя пережило ещё один сезон. Израсходовано ' + needed + ' еды.';
                }
                state.season = (state.season + 1) % 4;
                if (state.season === 0) {
                    state.year = Math.max(-999, state.year - 1);
                    if (state.men > 0 && state.women > 0 && state.morale >= 45) {
                        const children = random(1, 4);
                        const boys = random(0, children);
                        state.men += boys; state.women += children - boys;
                        state.message += ' Весной родилось детей: ' + children + '.';
                    }
                }
                render();
            });
            byId('reset').addEventListener('click', () => {
                if (!window.confirm('Создать новое племя? Текущий прогресс в этом браузере будет удалён.')) return;
                state = fresh(); render();
            });
            render();
        })();
    </script>
</body>
</html>
