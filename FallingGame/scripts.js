const { Engine, Render, Runner, World, Bodies, Events } = Matter;

// エンジンとワールドの作成
const engine = Engine.create();
const world = engine.world;

// レンダラーの作成
const render = Render.create({
    element: document.getElementById('game'),
    engine: engine,
    options: {
        width: 400,
        height: 600,
        wireframes: false,
        background: '#fafafa'
    }
});
Render.run(render);

// ランナーの作成
const runner = Runner.create();
Runner.run(runner, engine);

// 床と壁
const ground = Bodies.rectangle(200, 600, 400, 10, { isStatic: true });
const leftWall = Bodies.rectangle(0, 300, 10, 600, { isStatic: true });
const rightWall = Bodies.rectangle(400, 300, 10, 600, { isStatic: true });
World.add(world, [ground, leftWall, rightWall]);

// 数字と色
const colors = {
  1: '#3498db',
  2: '#e74c3c',
  4: '#f1c40f',
  8: '#2ecc71',
  16: '#9b59b6',
  32: '#34495e',
  64: '#16a085',
  128: '#2980b9',
  256: '#8e44ad',
  512: '#2c3e50',
  1024: '#f39c12',
  2048: '#d35400'
};

// プレビュー用のボール
let previewBall = null;

// スコア管理
let score = 0;
function updateScore() {
    document.getElementById('score').textContent = score;
}

// プレビュー用のボールを表示する関数
function showPreviewBall(x) {
  if (previewBall) {
    console.log('Preview ball already exists');
    Matter.Body.setPosition(previewBall, { x: x, y: 32 });
  } else {
    console.log('Creating new preview ball');
    const keys = Object.keys(colors);
    const num = keys[Math.floor(Math.random() * 4)];
    const radius = 16 * (1 + Math.sqrt(num) / 4);
    previewBall = Bodies.circle(x, 32, radius, { isStatic: true, render: { opacity: 0.5, fillStyle: colors[num] } });
    previewBall.num = num;
    World.add(world, previewBall);
  }
}

// マウス移動でプレビュー位置を更新
document.addEventListener('mousemove', function(event) {
  const rect = render.canvas.getBoundingClientRect();
  let x = event.clientX - rect.left;
  x = Math.max(32, Math.min(380, x));
  showPreviewBall(x);
});

document.addEventListener('click', function(event) {
  // クリックしたらボールを落とす
  if (!previewBall) return;
  const x = previewBall.position.x;
  const radius = previewBall.circleRadius;
  const color = previewBall.render.fillStyle;
  const num = previewBall.num;
  // プレビューを削除
  World.remove(world, previewBall);
  previewBall = null;
  // 本物のボールを落とす
  const ball = Bodies.circle(x, 32, radius, { restitution: 0.2, render: { fillStyle: color } });
  ball.num = num;
  World.add(world, ball);
  // 少し待ってから次のプレビューを表示
  setTimeout(() => {
    showPreviewBall(x);
  }, 400);
});

// afterRenderで数字を描画
Events.on(render, 'afterRender', function() {
  world.bodies.forEach(body => {
    if (body.label === 'Circle Body' && body.num) {
      const ctx = render.context;
      ctx.save();
      ctx.font = `${body.circleRadius}px Arial`;
      ctx.fillStyle = '#222';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.globalAlpha = body.render.opacity || 1;
      ctx.fillText(body.num, body.position.x, body.position.y);
      ctx.restore();
    }
  });
});

// 初期プレビュー表示
showPreviewBall(200);

// 同じnumのボールが衝突したら合体
function tryMergeBalls(pairs) {
  pairs.forEach(pair => {
    const a = pair.bodyA;
    const b = pair.bodyB;
    if (
      a.label === 'Circle Body' && b.label === 'Circle Body' &&
      a.num && b.num && a.num === b.num
    ) {
      // 合体位置（2つの中心の中点）
      const newX = (a.position.x + b.position.x) / 2;
      const newY = (a.position.y + b.position.y) / 2;
      const newNum = a.num * 2;
      const color = colors[newNum];
      const radius = 16 * (1 + Math.sqrt(newNum) / 4);
      // 2つのボールを削除
      World.remove(world, a);
      World.remove(world, b);
      // 新しいボールを追加
      const newBall = Bodies.circle(newX, newY, radius, { restitution: 0.2, render: { fillStyle: color } });
      newBall.num = newNum;
      World.add(world, newBall);
      // スコア加算
      score += newNum;
      updateScore();
    }
  });
}

// 衝突開始・継続の両方で合体を試みる
Events.on(engine, 'collisionStart', function(event) {
  tryMergeBalls(event.pairs);
});
Events.on(engine, 'collisionActive', function(event) {
  tryMergeBalls(event.pairs);
});

let isGameOver = false;

function gameOver() {
  isGameOver = true;
  alert('Game Over!');
  // クリックイベントを無効化
  document.removeEventListener('click', dropHandler);
}

// クリックイベント用の関数を分離
function dropHandler(event) {
  if (isGameOver) return;
  if (!previewBall) return;
  const x = previewBall.position.x;
  const radius = previewBall.circleRadius;
  const color = previewBall.render.fillStyle;
  const num = previewBall.num;
  World.remove(world, previewBall);
  previewBall = null;
  const ball = Bodies.circle(x, 32, radius, { restitution: 0.2, render: { fillStyle: color } });
  ball.num = num;
  World.add(world, ball);
  setTimeout(() => {
    showPreviewBall(x);
  }, 400);
}

// 既存のクリックイベントを置き換え
document.removeEventListener('click', dropHandler); // 念のため
document.addEventListener('click', dropHandler);

// 毎フレーム、ボールが上端に達したか判定
Events.on(runner, 'afterUpdate', function() {
  if (isGameOver) return;
  for (const body of world.bodies) {
    if (body.label === 'Circle Body' && body.position.y - body.circleRadius <= 0) {
      gameOver();
      break;
    }
  }
});
