import pygame

# PyGameの設定
pygame.init()
screen = pygame.display.set_mode((1280, 720))
clock = pygame.time.Clock()
running = True

# 前のフレームからの経過時間（秒）で、フレームレートに依存しない物理演算に使用される
dt = 0

# プレイヤーの位置
player_pos = pygame.Vector2(screen.get_width() / 2, screen.get_height() / 2)

while running:
    # イベントの取得
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False

    # 画面を色で塗りつぶして前のフレームの内容を消去
    screen.fill("purple")

    # プレイヤーとして赤い円を描画
    pygame.draw.circle(screen, "red", player_pos, 40)

    # キー入力でプレイヤーを移動
    keys = pygame.key.get_pressed()
    if keys[pygame.K_w]:
        player_pos.y -= 300 * dt
    if keys[pygame.K_s]:
        player_pos.y += 300 * dt
    if keys[pygame.K_a]:
        player_pos.x -= 300 * dt
    if keys[pygame.K_d]:
        player_pos.x += 300 * dt

    # flip()を使って画面に描画を表示
    pygame.display.flip()

    # FPSを60に制限
    dt = clock.tick(60) / 1000

# PyGameの終了
pygame.quit()
