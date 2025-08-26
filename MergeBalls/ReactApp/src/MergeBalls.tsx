import React, { useEffect, useRef, useState } from "react";
import Matter from "matter-js";

/**
 * MergeBallsGame (React + Matter.js)
 *
 * ■ 目的 / Purpose
 *  - 元コードの機能を React コンポーネントとして完全再現します。
 *    (プレビュー球、重み付き出現、同数衝突での合体 + クールダウン、
 *     スコア更新、天井センサーによるゲームオーバー、afterRender での数字描画、
 *     アンマウント時のリソース解放)
 *
 * ■ ライフサイクル / Lifecycle
 *  - useEffect 内で Matter.js の Engine / Render / Runner / World を初期化し、
 *    イベントリスナー(衝突、描画後)と UI 入力(マウス/タッチ)を登録します。
 *  - クリーンアップでは、イベント解除・ワールド破棄・レンダラ停止・Runner 停止
 *    まで漏れなく実施し、再マウント(再スタート)に耐える設計です。
 *
 * ■ 複雑な部分の要点 / Highlights of Complex Parts
 *  - 擬似乱数(rand) & 重み付き抽選(weightedPick):
 *      独自シードの Xorshift 風 PRNG を使って重み付きランダムを実装。
 *  - 合体ロジック(collisionStart → toMerge → removed):
 *      同数の円同士の衝突ペアを一旦 toMerge に集約 → 二重処理を避けるため
 *      removed セットで除外管理 → その後ペア毎に元の 2 球を削除&新球を追加。
 *  - 合体クールダウン(lastMergedAtRef + canMerge):
 *      合体直後の再合体ループを避けるため、各 Body.id に最終合体時刻を記録し、
 *      経過時間が MERGE_COOLDOWN_MS 未満なら合体を抑制。
 *  - afterRender での数字描画:
 *      Matter.Render の描画後に Canvas へテキスト描画し、球の中央に数値を表示。
 */
export default function MergeBallsGame() {
  // =========================
  //  UI State (React 管理状態)
  // =========================
  const [score, setScore] = useState(0);       // 画面表示用スコア
  const [isGameOver, setIsGameOver] = useState(false); // ゲームオーバー表示用フラグ

  // score は加算時に即時参照したいので、
  // React state と別にミュータブルな ref を併用します。
  const scoreRef = useRef(0);

  // ゲームキャンバスを挿入する DOM コンテナ
  const containerRef = useRef<HTMLDivElement | null>(null);

  // =========================
  //  Matter.js オブジェクト参照
  // =========================
  const engineRef = useRef<Matter.Engine | null>(null);
  const renderRef = useRef<Matter.Render | null>(null);
  const runnerRef = useRef<Matter.Runner | null>(null);
  const worldRef  = useRef<Matter.World  | null>(null);

  // プレビュー用の球と次の数字、PRNG、合体クールダウン記録
  const previewBallRef  = useRef<Matter.Body | null>(null);
  const nextNumRef      = useRef<number>(1);
  const rngSeedRef      = useRef<number>(Date.now() & 0xffffffff); // Xorshift 風 PRNG のシード
  const lastMergedAtRef = useRef<Map<number, number>>(new Map());    // Body.id → 最終合体時刻(ms)

  // Restart ボタンで完全初期化を行うためのキー (useEffect の再実行トリガ)
  const [restartKey, setRestartKey] = useState(0);

  // =========================
  //  ゲーム定数 (サイズ・境界など)
  // =========================
  const WIDTH = 400;
  const HEIGHT = 600;
  const BORDER = 10;     // 壁/床/天井の厚み
  const SPAWN_Y = 40;    // 落下開始位置 Y
  const PREVIEW_Y = 40;  // プレビュー表示位置 Y
  const LEFT_LIMIT  = 32;            // プレビュー X の左端制限
  const RIGHT_LIMIT = WIDTH - 20;    // プレビュー X の右端制限

  // 数値→色のマッピング
  const COLORS = {
    1:   "#3498db",
    2:   "#e74c3c",
    4:   "#f1c40f",
    8:   "#2ecc71",
    16:  "#9b59b6",
    32:  "#34495e",
    64:  "#16a085",
    128: "#2980b9",
    256: "#8e44ad",
    512: "#2c3e50",
    1024:"#f39c12",
    2048:"#d35400",
  } as Record<number, string>;

  // 初期球の重み付き出現テーブル (n: 数字, w: 重み)
  const WEIGHTED_POOL = [
    { n: 1, w: 40 },
    { n: 2, w: 30 },
    { n: 4, w: 20 },
    { n: 8, w: 100 },
  ];

  // =========================
  //  ユーティリティ
  // =========================
  // 数字から半径を算出 (下限12, 上限60)。2048 など大きい数も視認性を確保。
  const radiusFor = (num: number) => {
    const base = 16;
    const r = Math.round(base * (1 + Math.sqrt(num) / 4));
    return Math.min(Math.max(r, 12), 60);
  };

  // 数字→表示色
  const colorFor = (num: number) => COLORS[num] || "#555";

  // --- 擬似乱数 (Xorshift 風) ---
  // Math.random ではなく、シード制御可能な PRNG を用意。
  const rand = () => {
    let s = rngSeedRef.current >>> 0;
    s ^= s << 13; // 左シフト + XOR
    s ^= s >>> 17; // 右シフト + XOR
    s ^= s << 5;  // 左シフト + XOR
    rngSeedRef.current = s >>> 0;
    return (rngSeedRef.current >>> 0) / 0xffffffff; // 0..1 の浮動小数
  };

  // --- 重み付き抽選 ---
  // 合計重みに対して一様乱数を引き、範囲に入った要素の n を返します。
  const weightedPick = (pool: { n: number; w: number }[]) => {
    const total = pool.reduce((acc, p) => acc + p.w, 0);
    let r = rand() * total;
    for (const p of pool) {
      r -= p.w;
      if (r <= 0) return p.n;
    }
    return pool[0].n; // フォールバック (理論上ここには来ない)
  };

  // 定義外の最大値を超えた場合は最大色に丸める (過剰な色定義を省くため)
  const safeNewNum = (n: number) => {
    const maxDefined = Math.max(...Object.keys(COLORS).map(Number));
    return n > maxDefined ? maxDefined : n;
  };

  // スコア加算 (ref を更新後、React state へ反映)
  const updateScore = (delta = 0) => {
    scoreRef.current += delta;
    setScore(scoreRef.current);
  };

  // =========================
  //  初期化 & 破棄 (useEffect)
  //  restartKey が変わるたび完全再初期化
  // =========================
  useEffect(() => {
    if (!containerRef.current) return;

    // --- UI を初期状態へ ---
    setIsGameOver(false);
    scoreRef.current = 0;
    setScore(0);

    // --- Engine / World 作成 ---
    const engine = Matter.Engine.create({ enableSleeping: true });
    const world  = engine.world;
    engineRef.current = engine;
    worldRef.current  = world;

    // --- Render(キャンバス)作成 ---
    const render = Matter.Render.create({
      element: containerRef.current, // この DOM に <canvas> が生成される
      engine,
      options: {
        width: WIDTH,
        height: HEIGHT,
        wireframes: false,       // ワイヤーフレームではなく塗りつぶし
        background: "#fafafa",
        pixelRatio: (window.devicePixelRatio || 1) as number, // Retina 対応
      },
    });
    renderRef.current = render;
    Matter.Render.run(render); // レンダラ開始

    // --- Runner(物理ステップ)開始 ---
    const runner = Matter.Runner.create();
    runnerRef.current = runner;
    Matter.Runner.run(runner, engine);

    // --- 壁・床・天井センサーの生成 ---
    // isStatic: true で固定オブジェクト、topSensor は isSensor: true で
    // 接触のみ検出(反発なし) → ゲームオーバー判定に使用。
    const ground = Matter.Bodies.rectangle(
      WIDTH / 2,
      HEIGHT - BORDER / 2,
      WIDTH,
      BORDER,
      { isStatic: true }
    );
    const leftWall = Matter.Bodies.rectangle(
      BORDER / 2,
      HEIGHT / 2,
      BORDER,
      HEIGHT,
      { isStatic: true }
    );
    const rightWall = Matter.Bodies.rectangle(
      WIDTH - BORDER / 2,
      HEIGHT / 2,
      BORDER,
      HEIGHT,
      { isStatic: true }
    );
    const topSensor = Matter.Bodies.rectangle(
      WIDTH / 2,
      BORDER / 2,
      WIDTH,
      BORDER,
      { isStatic: true, isSensor: true, render: { visible: false } as any }
    );

    Matter.World.add(world, [ground, leftWall, rightWall, topSensor]);

    // --- プレビュー球の生成/更新 ---
    // ユーザー入力位置に合わせて、静的(isStatic)な薄透明の球を表示。
    const ensurePreview = (x: number) => {
      const clampedX = Math.max(LEFT_LIMIT, Math.min(RIGHT_LIMIT, x));
      if (previewBallRef.current) {
        // 既存のプレビューがあれば位置のみ更新
        Matter.Body.setPosition(previewBallRef.current, { x: clampedX, y: PREVIEW_Y });
        return;
      }
      // 初回は球を作って World に追加
      const radius = radiusFor(nextNumRef.current);
      const pb = Matter.Bodies.circle(clampedX, PREVIEW_Y, radius, {
        isStatic: true,
        render: { opacity: 0.6, fillStyle: colorFor(nextNumRef.current) } as any,
      });
      (pb as any).num = nextNumRef.current; // 数字をカスタム属性として付与
      previewBallRef.current = pb;
      Matter.World.add(world, pb);
    };

    // プレビューの削除 (落下させた直後などに使用)
    const removePreview = () => {
      if (previewBallRef.current) {
        Matter.World.remove(world, previewBallRef.current);
        previewBallRef.current = null;
      }
    };

    // --- 現在のプレビュー球を落下させる ---
    const dropCurrent = () => {
      if (isGameOver) return;                 // 終了後は何もしない
      if (!previewBallRef.current) return;    // プレビュー未表示なら無視

      const { x } = previewBallRef.current.position;
      const n = (previewBallRef.current as any).num as number;
      const r = radiusFor(n);

      // 動的な球として生成 (反発/摩擦/空気抵抗は控えめ)
      const ball = Matter.Bodies.circle(x, SPAWN_Y, r, {
        restitution: 0.15,
        friction: 0.02,
        frictionAir: 0.001,
        render: { fillStyle: colorFor(n) } as any,
      });
      (ball as any).num = n; // 数字を保持

      Matter.World.add(world, ball); // World に追加して物理シミュレーション開始
      removePreview();               // プレビュー消去

      // 次の球の数字を重み付きで決め、少し待ってからプレビュー再表示
      nextNumRef.current = weightedPick(WEIGHTED_POOL);
      setTimeout(() => ensurePreview(x), 400);
    };

    // =========================
    //  入力処理 (マウス/タッチ)
    // =========================
    // Render.canvas の相対座標へ変換し、X のみ利用
    const getLocalX = (evt: MouseEvent | TouchEvent) => {
      const canvas = render.canvas as HTMLCanvasElement;
      const rect = canvas.getBoundingClientRect();
      const clientX = (evt as TouchEvent).touches?.[0]?.clientX ?? (evt as MouseEvent).clientX;
      return clientX - rect.left;
    };

    // カーソル/指の移動でプレビュー位置を更新
    const onMove = (evt: MouseEvent | TouchEvent) => {
      ensurePreview(getLocalX(evt));
    };

    // クリック/タップで落下
    const onClickOrTap = (_evt: MouseEvent | TouchEvent) => {
      dropCurrent();
    };

    // グローバルではなくホスト要素にイベントをバインド → コンポーネント内で完結
    const host = containerRef.current as HTMLDivElement;
    host.addEventListener("mousemove", onMove, { passive: true });
    host.addEventListener("touchmove", onMove, { passive: true });
    host.addEventListener("click", onClickOrTap, { passive: true });
    host.addEventListener("touchstart", onClickOrTap, { passive: true });

    // =========================
    //  合体ロジック (collisionStart)
    // =========================
    const MERGE_COOLDOWN_MS = 10; // 連続合体の暴走を抑止する最低インターバル

    // 直近の合体時刻を参照し、十分時間が経っているかチェック
    const canMerge = (body: Matter.Body, now: number) => {
      const t = lastMergedAtRef.current.get(body.id) ?? 0;
      return now - t >= MERGE_COOLDOWN_MS;
    };

    // 合体に関与した球の最終時刻を更新
    const markMerged = (...bodies: Matter.Body[]) => {
      const now = performance.now();
      for (const b of bodies) lastMergedAtRef.current.set(b.id, now);
    };

    // 同数の円同士が衝突したら、中心位置の平均・新半径で 1 個に合体する
    const onCollision = (evt: Matter.IEventCollision<Matter.Engine>) => {
      if (isGameOver) return; // 終了後は無視

      const now = performance.now();
      const toMerge: Array<[Matter.Body, Matter.Body]> = []; // 合体候補ペア

      // 1) まず衝突ペアを走査して「合体して良い条件」を満たすものだけ toMerge に蓄える。
      for (const p of (evt as any).pairs as Matter.IPair[]) {
        const a = p.bodyA;
        const b = p.bodyB;
        if (a.label !== "Circle Body" || b.label !== "Circle Body") continue; // 円以外は対象外

        const an = (a as any).num as number | undefined;
        const bn = (b as any).num as number | undefined;
        if (!an || !bn || an !== bn) continue; // 数字が無い or 不一致 → スキップ
        if (!canMerge(a, now) || !canMerge(b, now)) continue; // クールダウン中 → スキップ

        toMerge.push([a, b]);
      }

      // 2) 同じ Body を二重で処理しないよう removed セットで保護しながら合体。
      const removed = new Set<number>();

      for (const [a, b] of toMerge) {
        if (removed.has(a.id) || removed.has(b.id)) continue; // すでに消していたらスキップ

        const newNum = safeNewNum(((a as any).num as number) * 2); // 値は 2 倍 (最大色へ丸め)
        const newX = (a.position.x + b.position.x) / 2;          // 位置は 2 球の平均
        const newY = (a.position.y + b.position.y) / 2;
        const r    = radiusFor(newNum);

        // 元の 2 球をワールドから除去
        Matter.Composite.remove(world, a);
        Matter.Composite.remove(world, b);
        removed.add(a.id);
        removed.add(b.id);

        // 合体後の新しい球を追加
        const merged = Matter.Bodies.circle(newX, newY, r, {
          restitution: 0.15,
          friction: 0.02,
          frictionAir: 0.001,
          render: { fillStyle: colorFor(newNum) } as any,
        });
        (merged as any).num = newNum;
        Matter.World.add(world, merged);

        // 合体に関与した 3 体 (a, b, merged) のクールダウンタイムを更新
        markMerged(a, b, merged);

        // スコアは新しい数字をそのまま加算
        updateScore(newNum);
      }
    };

    // 天井(センサー)に球が触れたらゲームオーバー。
    // センサーは反発しないが衝突イベントは発火するため、ここで検知。
    const onTopHit = (evt: Matter.IEventCollision<Matter.Engine>) => {
      if (isGameOver) return;
      for (const p of (evt as any).pairs as Matter.IPair[]) {
        const a = p.bodyA;
        const b = p.bodyB;
        const isTopHit = (a.isSensor && b.label === "Circle Body") ||
                         (b.isSensor && a.label === "Circle Body");
        if (isTopHit) {
          setIsGameOver(true);
          removePreview(); // これ以上の生成を抑止
          break;
        }
      }
    };

    // 衝突イベント登録 (同一フェーズで 2 つのハンドラを併用)
    Matter.Events.on(engine, "collisionStart", onCollision);
    Matter.Events.on(engine, "collisionStart", onTopHit);

    // =========================
    //  afterRender: 数字のテキスト描画
    // =========================
    // Matter の塗りつぶし後に Canvas API でテキストを重ねる。
    const onAfterRender = () => {
      const ctx = render.context as CanvasRenderingContext2D;
      for (const body of world.bodies) {
        if (body.label !== "Circle Body" || !(body as any).num) continue;
        const r = (body as any).circleRadius || 12;
        const fontSize = Math.max(12, Math.min(24, Math.round(r * 0.9))); // 半径に応じて可読サイズを調整
        ctx.save();
        ctx.font = `${fontSize}px Arial`;
        ctx.fillStyle = "#222";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        // @ts-ignore 透明度は Body の render.opacity を尊重
        ctx.globalAlpha = (body.render.opacity ?? 1) as number;
        ctx.fillText(String((body as any).num), body.position.x, body.position.y);
        ctx.restore();
      }
    };
    Matter.Events.on(render, "afterRender", onAfterRender);

    // 初期プレビュー表示 (中央へ)
    nextNumRef.current = weightedPick(WEIGHTED_POOL);
    ensurePreview(WIDTH / 2);

    // =========================
    //  クリーンアップ (アンマウント/再起動)
    // =========================
    return () => {
      try {
        host.removeEventListener("mousemove", onMove as any);
        host.removeEventListener("touchmove", onMove as any);
        host.removeEventListener("click", onClickOrTap as any);
        host.removeEventListener("touchstart", onClickOrTap as any);
      } catch {}

      try {
        Matter.Events.off(engine, "collisionStart", onCollision as any);
        Matter.Events.off(engine, "collisionStart", onTopHit as any);
        Matter.Events.off(render, "afterRender", onAfterRender as any);
      } catch {}

      try {
        if (previewBallRef.current) {
          Matter.World.remove(world, previewBallRef.current);
          previewBallRef.current = null;
        }
      } catch {}

      try {
        Matter.Render.stop(render);
        (render.canvas?.parentNode as HTMLElement | null)?.removeChild(render.canvas);
      } catch {}

      try {
        Matter.Runner.stop(runner);
      } catch {}

      try {
        // World/Engine の破棄。第二引数を false にしてテクスチャ等は触らない。
        Matter.World.clear(world, false);
        Matter.Engine.clear(engine);
      } catch {}
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [restartKey]);

  // =========================
  //  UI 操作: Restart (完全再初期化)
  // =========================
  const onRestart = () => {
    setRestartKey((k) => k + 1); // restartKey を変える → useEffect が再実行
  };

  // =========================
  //  JSX: スコア表示/ゲームキャンバス/ヘルプ
  // =========================
  return (
    <div className="w-full flex flex-col items-center gap-2">
      <div className="flex items-center gap-4">
        <div className="text-lg font-medium">
          Score: <span>{score}</span>
        </div>
        {isGameOver && (
          <div className="text-red-600 font-semibold">Game Over!</div>
        )}
        <button
          onClick={onRestart}
          className="px-3 py-1 rounded-xl border shadow-sm hover:shadow-md"
        >
          Restart
        </button>
      </div>

      {/* Matter.Render がこの要素の中に <canvas> を生成します */}
      <div
        ref={containerRef}
        className="rounded-xl border bg-white shadow-sm"
        style={{ width: WIDTH, height: HEIGHT, touchAction: "none" }}
      />

      <p className="text-sm text-gray-600">
        Move cursor / finger to position, click / tap to drop.
      </p>
    </div>
  );
}
