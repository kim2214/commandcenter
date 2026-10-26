# Chzzk Multiviewer

[![Build](https://github.com/kim2214/commandcenter/actions/workflows/build.yml/badge.svg)](https://github.com/kim2214/commandcenter/actions/workflows/build.yml)

> 네이버 치지직(Chzzk) 라이브 방송 여러 개를 한 화면에서 보는 데스크톱 멀티뷰어

Flutter로 만든 데스크톱 애플리케이션입니다. 방송 영상은 웹페이지가 아니라 HLS 스트림을 [media_kit](https://pub.dev/packages/media_kit)(libmpv)으로 직접 재생하기 때문에, 14개 이상을 동시에 띄워도 가볍습니다.

## 주요 기능

- **멀티뷰**: 최대 16개 방송을 동시에 재생
  - **균등 분할**: 방송 수에 맞춰 화면을 고르게 나눔 (예: 14개 → 4×4)
  - **메인 + 서브**: 소리 나는 방송을 16:9로 크게, 나머지를 오른쪽·아래에 작게 배치
- **소리 선택**: 타일을 클릭하면 그 방송만 소리가 남
- **자동 화질**: 타일 수와 크기에 맞춰 1080p~360p를 자동 선택. 타일별로 직접 고를 수도 있음
- **멤버 프리셋**: 자주 보는 채널을 등록해 두면 1분마다 방송 상태를 확인해 방송 중인 멤버만 자동으로 띄우고, 방송을 시작하면 데스크톱 알림
- **채팅**: 메인 방송 또는 고정한 방송의 채팅을 사이드 패널에서 실시간으로 보기 (읽기 전용, 이모티콘·후원 표시)
- **자동 재연결**: 방송이 끊기거나 멈추면 스트림 주소를 새로 받아 다시 연결
- **이어 보기**: 마지막으로 띄워 둔 방송과 소리 타일, 멤버 목록·순서, 레이아웃, 볼륨 등 설정을 다음 실행에 그대로 이어서 사용

## 지원 플랫폼

| 플랫폼  | 지원 | 비고 |
| ------- | :--: | ---- |
| Linux   |  ✅  | 개발·검증 환경 |
| macOS   |  ✅  | 빌드 구성만 되어 있고 실제 실행은 아직 확인하지 않음 |
| Windows |  ✅  | 빌드 구성만 되어 있고 실제 실행은 아직 확인하지 않음 |

## 개발 환경

- Flutter 3.44 이상
- Dart SDK `^3.12.2`

플랫폼별로 데스크톱 빌드 도구가 필요합니다. 자세한 내용은 [Flutter 데스크톱 지원 문서](https://docs.flutter.dev/platform-integration/desktop)를 참고하세요.

- **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, 그리고 영상 재생용 **`libmpv-dev`, `mpv`**
  ```bash
  sudo apt install libmpv-dev mpv
  ```
- **macOS**: Xcode
- **Windows**: Visual Studio ("Desktop development with C++" 워크로드). 아래 두 가지가 없으면 빌드가 실패합니다.
  - **C++ ATL** 구성 요소: `flutter_local_notifications_windows`가 `atlbase.h`를 필요로 합니다. 없으면 `error C1083: 'atlbase.h': No such file or directory`가 납니다. Visual Studio Installer의 개별 구성 요소에서 "최신 v143 빌드 도구용 C++ ATL"을 추가하거나, 명령줄로 설치할 수 있습니다.
    ```powershell
    & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe" modify `
      --installPath "<Visual Studio 설치 경로>" `
      --add Microsoft.VisualStudio.Component.VC.ATL --passive --norestart
    ```
  - **개발자 모드**: Flutter가 플러그인을 심볼릭 링크로 연결하므로 Windows 개발자 모드가 켜져 있어야 합니다. 꺼져 있으면 `Building with plugins requires symlink support`가 납니다. `start ms-settings:developers`에서 켭니다.

macOS와 Windows는 `media_kit_libs_video`가 libmpv를 함께 포함하므로 따로 설치할 것이 없습니다.

## 시작하기

```bash
git clone git@github.com:kim2214/commandcenter.git
cd commandcenter
flutter pub get
```

### 실행

```bash
flutter run -d linux     # 또는 macos, windows
```

### 빌드

```bash
flutter build linux --release
```

빌드 결과물은 `build/<플랫폼>/` 아래에 생성됩니다.

## 사용법

### 방송 추가

- 상단 입력창에 **채널 ID**(32자리) 또는 **라이브 주소**(`https://chzzk.naver.com/live/...`)를 넣고 Enter
- 타일에 마우스를 올리면 화질 메뉴와 닫기(✕) 버튼이 나타납니다.
- 이름 왼쪽의 손잡이(⠿)를 끌어 다른 타일 위에 놓으면 그 자리로 옮겨집니다. 멤버 방송은 멤버 패널의 순서도 함께 바뀌고, 멤버가 아닌 방송은 항상 멤버 뒤에 놓입니다.

### 소리와 레이아웃

- 타일을 클릭하면 그 방송만 소리가 납니다. 소리 나는 타일은 초록 테두리로 표시됩니다.
- 상단 버튼으로 **균등 분할**(▦)과 **메인 + 서브**(▤)를 전환합니다. 메인 + 서브에서는 소리 나는 방송이 메인이 됩니다.
- 볼륨과 음소거는 상단 툴바에서 조절합니다.
- 타일에 마우스를 올리면 방송 제목, 시청자 수, 방송 경과 시간이 보입니다. 멤버 패널에도 같은 정보가 1분마다 갱신됩니다.

### 단축키

입력창에 글자를 치는 중에는 동작하지 않습니다. Esc로 입력창에서 빠져나올 수 있습니다.

| 키 | 동작 |
| -- | ---- |
| `1`~`9` | 해당 번호 타일의 소리 켜기 (번호는 타일 이름 앞에 표시) |
| `M` | 음소거 |
| `G` | 균등 분할 / 메인 + 서브 전환 |
| `P` | 사이드 패널 열기 / 닫기 |
| `F` | 시청 모드: 툴바와 패널을 숨기고 전체 화면으로 보기 |
| 타일 더블클릭 | 단독 보기: 그 방송만 화면 가득 보기 (소리도 그 방송으로) |
| `Esc` | 단독 보기 / 시청 모드 나가기 |

### 멤버

오른쪽 패널의 **멤버** 탭에서 사용합니다. 👥 버튼으로 패널을 열고 닫을 수 있습니다.

- 채널 ID나 채널 주소로 멤버를 등록합니다. 방송 중이 아니어도 등록할 수 있습니다.
- **자동 띄우기**가 켜져 있으면 방송 중인 멤버를 자동으로 띄우고, 방송이 끝나면 내립니다.
- 방송 중인 멤버의 타일을 직접 닫으면, 그 방송이 끝날 때까지는 다시 자동으로 뜨지 않습니다.
- 왼쪽 손잡이(⠿)를 끌어 순서를 바꾸면 타일도 그 순서대로 배치됩니다.
- **방송 시작 알림**이 켜져 있으면 멤버가 방송을 시작할 때 데스크톱 알림을 띄웁니다. 앱을 켤 때 이미 방송 중인 멤버는 알리지 않습니다.

### 채팅

오른쪽 패널의 **채팅** 탭에서 메인(소리 나는) 방송의 채팅을 봅니다.

- 맨 위의 방송 이름을 누르면 다른 방송의 채팅을 골라 **고정**할 수 있습니다. 고정하면 메인을 바꿔도 그 방송의 채팅이 유지되고, 그 방송을 닫거나 "메인 방송 따라가기"를 고르면 다시 메인을 따라갑니다.

- 로그인 없이 읽기 전용으로 접속하며, 채팅 입력은 지원하지 않습니다.
- 채팅 탭이 열려 있을 때만 채팅 서버에 접속합니다.
- 위로 스크롤해서 지난 채팅을 보는 동안에는 목록이 고정됩니다. 아래의 "새 채팅 N개" 버튼을 누르거나 맨 아래로 내리면 다시 실시간으로 따라갑니다.

## 성능 측정 모드

환경변수를 주고 실행하면 방송을 자동으로 띄워 성능을 잴 수 있습니다. 평소 실행에는 영향이 없습니다.

| 환경변수 | 설명 |
| -------- | ---- |
| `CC_BENCH_COUNT=14` | 시청자가 많은 방송 14개(성인 방송 제외)를 자동으로 띄움 |
| `CC_BENCH_CHANNELS=id1,id2,...` | 정해진 채널을 띄움. 개선 전후를 같은 방송으로 비교할 때 사용 |

```bash
# Linux / macOS
CC_BENCH_COUNT=14 build/linux/x64/release/bundle/command_center
```

```powershell
# Windows (PowerShell)
$env:CC_BENCH_COUNT = "14"; .\build\windows\x64\runner\Release\command_center.exe
```

- 측정 모드는 음소거로 시작하고, 설정과 멤버 목록을 별도 공간(`bench.` 키)에 두어 평소 데이터를 건드리지 않습니다.
- 띄운 채널 목록(`bench: channels=...`)과 타일별 재생 상태(`bench: tile ...`)가 표준 출력에 기록됩니다.
- 정확한 수치는 디버그 빌드가 아닌 **릴리스 빌드**로 측정하세요.

참고로 Linux(20코어)에서 14개(360p)를 띄웠을 때 메모리는 약 1.1GB였고, 시간이 지나도 계속 늘지 않았습니다.

## 알아둘 점

- **비공식 API**: 치지직의 방송 정보·스트림·채팅은 공식 API가 아니라 치지직 웹이 쓰는 API를 사용합니다. 치지직 쪽 변경으로 동작하지 않을 수 있으며, 관련 코드는 `lib/chzzk_api.dart`와 `lib/chzzk_chat.dart`에 모아 두었습니다.
- **성인 방송**: 로그인이 필요해 재생할 수 없습니다.
- **Linux 렌더링**: X11 세션에서는 media_kit이 GPU 렌더링을 쓰지 못하고 소프트웨어 렌더링으로 동작합니다(media_kit_video 2.0.1 기준). Wayland, Windows, macOS에는 해당하지 않습니다.
- **Linux 디코딩**: 타일마다 GPU 디코더를 만드는 메모리 비용이 커서, 480p 이하 화질은 CPU로 디코딩합니다.
- **작은 화질의 디코더 스레드**: 480p 이하 화질은 모든 플랫폼에서 디코더 스레드를 2개로 제한합니다. 코어 수만큼 스레드를 띄우면 스레드마다 메모리를 따로 잡기 때문입니다.
- **Linux 영상 출력 크기**: media_kit_video 2.0.1의 Linux 소프트웨어 렌더링 버그로 앱이 가끔 시작 직후 종료되던 문제를 피하려고, 영상 출력 크기를 화질 해상도로 고정합니다.
- **개인 용도**: 개인 시청용으로 만든 앱입니다. 배포하려면 치지직 이용약관을 확인하세요.

## 자동 빌드

`main`에 push하거나 PR을 올리면 GitHub Actions가 분석과 테스트를 돌리고, Linux / Windows / macOS 릴리스 빌드를 만듭니다.

- 결과물은 Actions 실행 화면의 **Artifacts**에서 14일 동안 내려받을 수 있습니다.
- 빌드 서버에는 화면이 없어서 영상 재생까지는 확인하지 못합니다. 결과물을 내려받아 직접 실행해 확인하세요.
- Actions 화면에서 **Run workflow**로 수동 실행할 수도 있습니다.

| 워크플로 | 하는 일 |
| -------- | ------- |
| `build.yml` | push·PR 때 공통 빌드를 돌려 확인 |
| `release.yml` | `v*` 태그를 push하면 공통 빌드 후 GitHub Release 생성 |
| `_build.yml` | 공통 빌드: 분석, 테스트, 3개 플랫폼 빌드와 zip 압축 |

## 릴리스

1. `pubspec.yaml`의 `version`을 올리고 커밋합니다. (예: `1.0.0+1` → `1.1.0+2`. `+` 뒤는 빌드 번호)
2. 같은 버전으로 태그를 만들어 push합니다.
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```
3. Actions가 빌드를 마치면 GitHub **Releases**에 `v1.1.0`이 생기고 zip 3개가 첨부됩니다. 릴리스 노트는 이전 릴리스 이후의 커밋 제목으로 자동 작성됩니다(`tool/release_notes.sh`). 정식 릴리스는 중간의 시험판을 건너뛰고 이전 정식 릴리스와 비교합니다. 미리 보려면 태그를 만든 뒤 `tool/release_notes.sh v1.1.0 kim2214/commandcenter`를 실행하세요.

- 태그와 `pubspec.yaml` 버전이 다르면 빌드하지 않고 멈춥니다.
- 하이픈이 들어간 태그(예: `v1.1.0-beta.1`)는 시험판(prerelease)으로 올라갑니다.
- 앱의 툴바 ⓘ 버튼에서 실행 중인 버전을 확인할 수 있습니다.
- 앱은 켤 때 GitHub의 최신 정식 릴리스를 확인해서, 새 버전이 있으면 툴바에 **"새 버전 vX.Y.Z"** 버튼을 띄웁니다. 누르면 릴리스 페이지가 열립니다. 저장소가 공개여야 동작하며, 확인에 실패하면 아무것도 표시하지 않습니다.

| 파일 | 실행 방법 |
| ---- | --------- |
| `chzzk-multiviewer-windows.zip` | 압축을 풀고 `command_center.exe` 실행. 처음에 SmartScreen 경고가 뜨면 "추가 정보 → 실행" |
| `chzzk-multiviewer-macos.zip` | 압축을 풀고 `Chzzk Multiviewer.app`을 우클릭 → 열기 (서명하지 않은 앱) |
| `chzzk-multiviewer-linux.zip` | `libmpv`가 설치된 PC에서 압축을 풀고 `command_center` 실행 |

## 테스트 및 정적 분석

```bash
flutter test
flutter analyze
```

테스트는 네트워크 없이 동작하도록 치지직 API를 가짜 구현으로 바꿔 끼웁니다. 린트 규칙은 `analysis_options.yaml`에서 관리하며 [`flutter_lints`](https://pub.dev/packages/flutter_lints)를 기반으로 합니다.

## 프로젝트 구조

```
lib/
  main.dart             # 진입점. 설정 저장소를 열고 측정 모드를 실행
  chzzk_api.dart        # 치지직 API (방송 정보, 스트림 주소, 채널, 방송 상태)
  chzzk_chat.dart       # 치지직 채팅 웹소켓 클라이언트와 메시지 해석
  multiview_state.dart  # 띄운 방송 목록, 소리 타일, 볼륨, 레이아웃 상태
  members_state.dart    # 멤버 목록 저장과 방송 상태 자동 동기화
  chat_state.dart       # 메인 방송의 채팅 상태
  settings.dart         # 사용자 설정 저장소
  tile_layout.dart      # 균등 분할 / 메인 + 서브 배치 계산
  benchmark.dart        # 성능 측정 모드
  multiview_page.dart   # 메인 화면 (툴바와 타일 그리드)
  stream_tile.dart      # 방송 하나를 재생하는 타일
  side_panel.dart       # 멤버 / 채팅 탭 패널
  members_panel.dart    # 멤버 목록 화면
  chat_panel.dart       # 채팅 화면
test/                   # 단위 테스트
tool/generate_icons.py  # 앱 아이콘 생성 스크립트 (Pillow 필요)
linux/ macos/ windows/  # 플랫폼별 네이티브 러너
```

상태 관리는 [Riverpod](https://riverpod.dev)을 사용합니다.

앱 아이콘은 `tool/generate_icons.py`로 그려서 플랫폼별 위치(macOS 아이콘 세트, Windows `.ico`, Linux `linux/runner/resources/app_icon.png`)에 저장합니다. 모양이나 색을 바꾸려면 스크립트를 고친 뒤 `python3 tool/generate_icons.py`를 실행하세요.
