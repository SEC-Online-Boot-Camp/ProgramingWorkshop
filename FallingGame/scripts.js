const { Engine, Render, Runner, World, Bodies, Body, Events, Composite } = Matter;

// ゲーム画面サイズ
const WIDTH = 400;
const HEIGHT = 600;
const BORDER = 10;
const SPAWN_Y = 40;
const PREVIEW_Y = 40;
const LEFT_LIMIT = 32;
const RIGHT_LIMIT = WIDTH - 20;

// 数字と色
const COLORS = {
    1:   '#3498db',
    2:   '#e74c3c',
    4:   '#f1c40f',
    8:   '#2ecc71',
    16:  '#9b59b6',
    32:  '#34495e',
    64:  '#16a085',
    128: '#2980b9',
    256: '#8e44ad',
    512: '#2c3e50',
    1024:'#f39c12',
    2048:'#d35400'
};

// 数字から半径を求める関数
function radiusFor(num) {
    const base = 16;
    const r = Math.round(base * (1 + Math.sqrt(num) / 4));
    return Math.min(Math.max(r, 12), 60);
}

// 初期のボール生成確率（重み付き）
const WEIGHTED_POOL = [
    { n: 1, w: 40 },
    { n: 2, w: 30 },
    { n: 4, w: 20 },
    { n: 8, w: 100 }
];

// 乱数関連（重み付き抽選）
let rngSeed = Date.now() & 0xffffffff;
function rand() {
    rngSeed ^= rngSeed << 13; rngSeed ^= rngSeed >>> 17; rngSeed ^= rngSeed << 5;
    return ((rngSeed >>> 0) / 0xffffffff);
}
function weightedPick(pool) {
    const total = pool.reduce((s, p) => s + p.w, 0);
    let r = rand() * total;
    for (const p of pool) {
        if ((r -= p.w) <= 0) return p.n;
    }
    return pool[0].n;
}

// エンジンとワールドの作成
const engine = Engine.create({ enableSleeping: true });
const world = engine.world;

// レンダラーの作成
const render = Render.create({
    element: document.getElementById('game'),
    engine,
    options: {
        width: WIDTH,
        height: HEIGHT,
        wireframes: false,
        background: '#fafafa',
        pixelRatio: window.devicePixelRatio || 1
    }
});
Render.run(render);

// ランナーの作成
const runner = Runner.create();
Runner.run(runner, engine);

// 壁・床・天井センサー（ゲームオーバー判定用）
const ground   = Bodies.rectangle(WIDTH/2, HEIGHT - BORDER/2, WIDTH, BORDER, { isStatic: true });
const leftWall = Bodies.rectangle(BORDER/2, HEIGHT/2, BORDER, HEIGHT, { isStatic: true });
const rightWall= Bodies.rectangle(WIDTH - BORDER/2, HEIGHT/2, BORDER, HEIGHT, { isStatic: true });
// 天井センサー（ボールが当たったらゲームオーバー）
const topSensor= Bodies.rectangle(WIDTH/2, BORDER/2, WIDTH, BORDER, {
    isStatic: true, isSensor: true, render: { visible: false }
});
World.add(world, [ground, leftWall, rightWall, topSensor]);

// スコア管理
let score = 0;
const scoreSpan = document.getElementById('score');
function updateScore(delta = 0) {
    score += delta;
    scoreSpan.textContent = score;
}

// プレビュー用のボール管理
let previewBall = null;
let nextNum = weightedPick(WEIGHTED_POOL);

function colorFor(num) {
   return COLORS[num] || '#555';
}

// プレビュー用のボールを表示する関数
function ensurePreview(x) {
    const clampedX = Math.max(LEFT_LIMIT, Math.min(RIGHT_LIMIT, x));
    if (previewBall) {
        Body.setPosition(previewBall, { x: clampedX, y: PREVIEW_Y });
        return;
    }
    const radius = radiusFor(nextNum);
    previewBall = Bodies.circle(clampedX, PREVIEW_Y, radius, {
        isStatic: true,
        render: { opacity: 0.6, fillStyle: colorFor(nextNum) }
    });
    previewBall.num = nextNum;
    World.add(world, previewBall);
}

function removePreview() {
    if (previewBall) {
        World.remove(world, previewBall);
        previewBall = null;
    }
}

// ボールを落とす処理
let isGameOver = false;
function dropCurrent() {
    if (isGameOver || !previewBall) return;
    const { x } = previewBall.position;
    const n = previewBall.num;
    const r = radiusFor(n);
    const ball = Bodies.circle(x, SPAWN_Y, r, {
        restitution: 0.15,
        friction: 0.02,
        frictionAir: 0.001,
        render: { fillStyle: colorFor(n) }
    });
    ball.num = n;
    World.add(world, ball);

    removePreview();
    nextNum = weightedPick(WEIGHTED_POOL);
    setTimeout(() => ensurePreview(x), 400);
}

// 入力イベント（マウス・タッチ）
function getLocalX(evt) {
    const rect = render.canvas.getBoundingClientRect();
    const clientX = (evt.touches?.[0]?.clientX ?? evt.clientX);
    return clientX - rect.left;
}
function onMove(evt) {
    const x = getLocalX(evt);
    ensurePreview(x);
}
function onClickOrTap(evt) {
    dropCurrent();
}

document.addEventListener('mousemove', onMove, { passive: true });
document.addEventListener('touchmove', onMove, { passive: true });
document.addEventListener('click', onClickOrTap, { passive: true });
document.addEventListener('touchstart', onClickOrTap, { passive: true });

// 同じ数字同士が衝突したら合体する
const MERGE_COOLDOWN_MS = 500; // 連続合体を防ぐためのクールダウン
const lastMergedAt = new Map();

function canMerge(body, now) {
    const t = lastMergedAt.get(body.id) ?? 0;
    return (now - t) >= MERGE_COOLDOWN_MS;
}
function markMerged(...bodies) {
    const now = performance.now();
    for (const b of bodies) lastMergedAt.set(b.id, now);
}
function safeNewNum(n) {
    const maxDefined = Math.max(...Object.keys(COLORS).map(Number));
    return n > maxDefined ? maxDefined : n;
}

// 衝突イベント（合体判定）
Events.on(engine, 'collisionStart', (evt) => {
    if (isGameOver) return;
    const now = performance.now();
    const toMerge = [];
    for (const p of evt.pairs) {
        const a = p.bodyA, b = p.bodyB;
        if (a.label === 'Circle Body' && b.label === 'Circle Body' && a.num && b.num && a.num === b.num) {
            if (canMerge(a, now) && canMerge(b, now)) {
                toMerge.push([a, b]);
            }
        }
    }

    const removed = new Set();
    for (const [a, b] of toMerge) {
        if (removed.has(a.id) || removed.has(b.id)) continue;
        const newNum = safeNewNum(a.num * 2);
        const newX = (a.position.x + b.position.x) / 2;
        const newY = (a.position.y + b.position.y) / 2;
        const r = radiusFor(newNum);
        Composite.remove(world, a);
        Composite.remove(world, b);
        removed.add(a.id);
        removed.add(b.id);
        const merged = Bodies.circle(newX, newY, r, {
            restitution: 0.15,
            friction: 0.02,
            frictionAir: 0.001,
            render: { fillStyle: colorFor(newNum) }
        });
        merged.num = newNum;
        World.add(world, merged);
        markMerged(a, b, merged);
        updateScore(newNum);
    }
});

// ゲームオーバー判定
Events.on(engine, 'collisionStart', (evt) => {
    if (isGameOver) return;
    for (const p of evt.pairs) {
        if (p.bodyA === topSensor && p.bodyB.label === 'Circle Body') { endGame(); break; }
        if (p.bodyB === topSensor && p.bodyA.label === 'Circle Body') { endGame(); break; }
    }
});
function endGame() {
    isGameOver = true;
    removePreview();
    alert('Game Over!');
}

// afterRenderで数字を描画
Events.on(render, 'afterRender', () => {
    const ctx = render.context;
    for (const body of world.bodies) {
        if (body.label !== 'Circle Body' || !body.num) continue;
        const r = body.circleRadius || 12;
        const fontSize = Math.max(12, Math.min(24, Math.round(r * 0.9)));
        ctx.save();
        ctx.font = `${fontSize}px Arial`;
        ctx.fillStyle = '#222';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.globalAlpha = body.render.opacity ?? 1;
        ctx.fillText(body.num, body.position.x, body.position.y);
        ctx.restore();
    }
});

// 初期プレビュー表示
ensurePreview(WIDTH / 2);
