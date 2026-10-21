"""앱 아이콘을 그려서 플랫폼별 위치에 저장한다.

"메인 + 서브" 레이아웃을 본뜬 모양: 어두운 배경에 치지직 초록색 메인 화면 하나와
작은 서브 화면들. 모양이나 색을 바꾸려면 이 파일을 고친 뒤 저장소 루트에서 실행한다.

    python3 tool/generate_icons.py

Pillow가 필요하다.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

BACKGROUND = (17, 19, 24)
MAIN = (0, 255, 163)  # 치지직 초록
SUB = (64, 72, 86)

# 작은 크기에서도 깨끗하게 보이도록 크게 그린 뒤 줄인다.
SCALE = 4
SIZE = 1024


def draw_icon() -> Image.Image:
    s = SIZE * SCALE
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def box(x, y, w, h, radius, color):
        draw.rounded_rectangle(
            [x * SCALE, y * SCALE, (x + w) * SCALE, (y + h) * SCALE],
            radius=radius * SCALE,
            fill=color,
        )

    # macOS 아이콘 가이드처럼 둘레에 여백을 두고 둥근 사각형 바탕을 그린다.
    margin = 100
    body = SIZE - margin * 2
    box(margin, margin, body, body, 185, BACKGROUND)

    # 바탕 안을 메인(왼쪽 위)과 서브(오른쪽 열, 아래 줄)로 나눈다.
    # 작은 크기에서도 모양이 읽히도록 실제 16:9보다 메인을 조금 높게 잡는다.
    pad = 92
    gap = 28
    inner = body - pad * 2
    left = margin + pad
    top = margin + pad
    main_w = round((inner - gap) * 0.70)
    main_h = round((inner - gap) * 0.64)
    box(left, top, main_w, main_h, 34, MAIN)

    # 오른쪽 열: 메인 높이에 서브 2개
    side_x = left + main_w + gap
    side_w = inner - main_w - gap
    side_h = (main_h - gap) / 2
    for i in range(2):
        box(side_x, top + i * (side_h + gap), side_w, side_h, 24, SUB)

    # 아래 줄: 서브 3개
    bottom_y = top + main_h + gap
    bottom_h = inner - main_h - gap
    cell_w = (inner - gap * 2) / 3
    for i in range(3):
        box(left + i * (cell_w + gap), bottom_y, cell_w, bottom_h, 24, SUB)

    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    icon = draw_icon()

    # macOS: 기존 AppIcon 세트의 파일 이름을 그대로 쓴다.
    mac_dir = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        icon.resize((size, size), Image.LANCZOS).save(mac_dir / f"app_icon_{size}.png")

    # Windows: 여러 크기를 담은 .ico 하나
    icon.save(
        ROOT / "windows/runner/resources/app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    # Linux: 실행 시 창 아이콘으로 불러온다 (linux/runner/my_application.cc).
    # 256px는 X11 창 속성으로 전달되지 않고 조용히 빠져서 128px로 둔다.
    linux_dir = ROOT / "linux/runner/resources"
    linux_dir.mkdir(exist_ok=True)
    icon.resize((128, 128), Image.LANCZOS).save(linux_dir / "app_icon.png")

    print("아이콘을 생성했습니다.")


if __name__ == "__main__":
    main()
