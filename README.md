# Command Center

> TODO: 프로젝트 한 줄 소개

Flutter로 만드는 데스크톱 애플리케이션입니다.

## 지원 플랫폼

| 플랫폼  | 지원 |
| ------- | :--: |
| Linux   |  ✅  |
| macOS   |  ✅  |
| Windows |  ✅  |

## 개발 환경

- Flutter 3.44 이상
- Dart SDK `^3.12.2`

플랫폼별로 데스크톱 빌드 도구가 필요합니다. 자세한 내용은 [Flutter 데스크톱 지원 문서](https://docs.flutter.dev/platform-integration/desktop)를 참고하세요.

- **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`
- **macOS**: Xcode
- **Windows**: Visual Studio ("Desktop development with C++" 워크로드)

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

## 테스트 및 정적 분석

```bash
flutter test
flutter analyze
```

린트 규칙은 `analysis_options.yaml`에서 관리하며 [`flutter_lints`](https://pub.dev/packages/flutter_lints)를 기반으로 합니다.

## 프로젝트 구조

```
lib/        # 앱 소스 코드 (진입점: lib/main.dart)
test/       # 위젯 및 단위 테스트
linux/      # Linux 네이티브 러너
macos/      # macOS 네이티브 러너
windows/    # Windows 네이티브 러너
```
