"""
敵を避けるだけのゲーム
"""

import random
from enum import Enum, auto
import pygame

# 定数
ENEMY_MAX = 10
DELAY = 0.1


class Direction(Enum):
    """
    方向
    """
    LEFT = auto()
    RIGHT = auto()
    UP = auto()
    DOWN = auto()


class GameObject:
    """
    ゲームオブジェクト（基底クラス）
    """

    def __init__(self, size, x, y, step=10):
        self.size = size
        self.x = x
        self.y = y
        self.step = step

    def move(self, direction):
        """
        移動
        """
        if direction == Direction.LEFT and self.x > self.size:
            self.x -= self.step
        if direction == Direction.RIGHT and self.x < screen.get_width() - self.size:
            self.x += self.step
        if direction == Direction.UP and self.y > self.size:
            self.y -= self.step
        if direction == Direction.DOWN and self.y < screen.get_height() - self.size:
            self.y += self.step

    def draw(self):
        """
        描画
        """
        raise NotImplementedError("draw メソッドが実装されていません")


class Player(GameObject):
    """
    プレイヤー
    """

    def __init__(self):
        super().__init__(60, screen.get_width() // 2 - 30, screen.get_height() - 60, 24)

    def draw(self):
        """
        描画
        """
        pygame.draw.rect(
            screen, "white", (self.x, self.y, self.size, self.size))


class Enemy(GameObject):
    """
    敵
    """

    def __init__(self):
        self.size = 60
        self.x = random.randint(0, screen.get_width() - self.size)
        super().__init__(60, random.randint(0, screen.get_width() - 60), 0, 24)

    def move(self, direction):
        """
        移動
        """
        if direction == Direction.DOWN:
            self.y += self.step
        else:
            super().move(direction)

    def draw(self):
        """
        描画
        """
        pygame.draw.rect(screen, "red", (self.x, self.y, self.size, self.size))


# 初期化
pygame.init()
screen = pygame.display.set_mode((1280, 720))
clock = pygame.time.Clock()
font = pygame.font.Font(None, 48)
pygame.display.set_caption("敵を避けるだけのゲーム")
running = True

# ゲームオブジェクトの初期化
player = Player()
enemy_list = []
score = 0

while running:
    # イベントの取得
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            break

    # 画面を色で塗りつぶして前のフレームの内容を消去
    screen.fill("black")

    # キー入力でプレーヤーを移動して表示
    keys = pygame.key.get_pressed()
    if keys[pygame.K_a] or keys[pygame.K_LEFT]:
        player.move(Direction.LEFT)
    if keys[pygame.K_d] or keys[pygame.K_RIGHT]:
        player.move(Direction.RIGHT)
    player.draw()

    # 敵の追加
    if len(enemy_list) < ENEMY_MAX and random.random() < DELAY:
        enemy = Enemy()
        enemy_list.append(enemy)

    # 敵の移動
    for enemy in enemy_list.copy():
        if enemy.y < screen.get_height():
            # 下に移動
            enemy.move(Direction.DOWN)
        else:
            # 画面外に出たら削除してスコアを加算
            enemy_list.remove(enemy)
            score += 1

    # 敵の描画
    for enemy in enemy_list:
        enemy.draw()

    # スコアの表示
    score_text = font.render("Score: " + str(score), True, "white")
    screen.blit(score_text, (10, 10))

    # ゲームオーバー判定
    for enemy in enemy_list:
        if enemy.y + enemy.size > player.y and \
           enemy.y < player.y + player.size and \
           enemy.x + enemy.size > player.x and\
           enemy.x < player.x + player.size:
            surface = font.render("Game Over !!!!", True, "white")
            rect = surface.get_rect(
                center=(screen.get_width() // 2, screen.get_height() // 2))
            screen.blit(surface, rect)
            pygame.display.update()
            pygame.time.wait(2000)
            running = False
            break

    # 画面を更新
    pygame.display.flip()

    # FPSを12に制限
    clock.tick(12)

# PyGameの終了
pygame.quit()
