# RV32IM 어셈블러 과제

C++17로 작성한 단일 파일 어셈블러다. RV32IM과 과제의 Zicsr 명령을 대상으로 하며, 일부 RV32F 명령과 추가 지시어를 지원한다. ELF 없이 `0x00010000`에 적재할 리틀엔디안 raw binary와 listing을 만든다.

## 저장소 안내

| 경로 | 설명 |
| --- | --- |
| `src/rv32asm.cpp` | 최종 제출 소스 |
| `examples/test_assembler.s` | LED로 성공·실패를 표시하는 기본 테스트 |
| `examples/course/` | 과제 제공 검증 예제 4개 |
| `examples/f/` | F 명령·데이터·지역 라벨·매크로·인클루드 검증 소스 |
| [docs/implementation.md](docs/implementation.md) | 구현 상세와 지원 범위 |
| [docs/process.md](docs/process.md) | 개발 과정 및 AI 사용 프롬프트 |
| [docs/verification.md](docs/verification.md) | 검증 절차, 오류 원인·수정 및 결과 |

## 빌드와 실행

저장소 루트에서 실행한다. `<` 리다이렉션이 아니라 소스 파일 경로를 인자로 전달한다.

```sh
mkdir -p build
g++ -std=c++17 -O2 -Wall -Wextra -Wpedantic src/rv32asm.cpp -o build/rv32asm
./build/rv32asm examples/test_assembler.s build/test_assembler.bin
for n in 1 2 3 4; do
  ./build/rv32asm "examples/course/asm_example$n.s" "build/asm_example$n.bin" || exit 1
done
./build/rv32asm examples/f/test_f.s build/test_f.bin
```

각 `.bin` 옆에 `.lst`가 생성된다. 출력 인자를 생략하면 입력 파일과 같은 디렉터리에 생성된다. CPUlator `rv32-de10-lite`에서는 기본 및 과제 예제의 raw 바이너리를 `0x00010000`에 로드하고 PC도 같은 주소로 설정한다. F 예제는 **인코딩 확인용**으로, F 지원 여부를 확인하지 않은 타깃에서는 실행 결과를 보장하지 않는다.
