import pygame

# PyGameの設定
pygame.init()
screen = pygame.display.set_mode((1280, 720))
clock = pygame.time.Clock()
running = True

while running:
    # イベントの取得
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False

    # 画面を塗りつぶす
    screen.fill("purple")

    # ここに描画処理を書く

    # 画面を更新
    pygame.display.flip()

    # FPSを60に設定
    clock.tick(60)

# PyGameの終了
pygame.quit()
