# Light Thinking VoXels — 연산 최적화 로드맵

> 이 문서는 쉐이더의 시각적 결과물을 일절 변경하지 않으면서,
> 연산 비효율적인 부분만 개선하는 작업의 **전체 로드맵**입니다.
>
> 각 Phase는 독립적으로 테스트 가능하며, 반드시 순서대로 진행합니다.
> Phase 내부의 Step도 위에서 아래 순서로 진행합니다.

---

## Phase 0: 사전 준비

### Step 0-1. 기준 스크린샷 촬영
- 마인크래프트에서 **고정 시드 월드** 생성 (예: `seed = 12345`)
- 다음 5개 장면에서 F2 스크린샷 촬영 후 `screenshots/before/` 폴더에 보관:
  1. **낮 평야** — 태양광 + 그림자 + 구름
  2. **밤 마을** — 횃불/랜턴 등 다량의 블록 광원
  3. **동굴 내부** — 용암 + 광석 발광 + 어둠
  4. **수중** — 물속 포그 + 수면 반사 + 코스틱
  5. **지옥(Nether)** — 용암 폭포 + 네더 안개 + 포탈 빛
- 각 장면에서 `F3` 디버그 화면의 **좌표와 바라보는 방향**을 메모

### Step 0-2. 기준 성능 측정
- Iris 디버그 오버레이 (`Ctrl+F3`) 또는 Iris의 셰이더 프로파일러로 각 패스별 GPU 시간(ms) 기록
- 기록할 항목:
  - `shadow` 패스 총 시간
  - `shadowcomp0~2` 패스 총 시간
  - `prepare0~4` 패스 총 시간
  - `deferred1` 패스 시간
  - `composite0~7` 패스 총 시간
  - `final` 패스 시간
  - **전체 프레임 시간 (ms)** 및 **FPS**
- 5개 장면 각각에서 10초간 정지 상태로 측정, 평균값 기록

### Step 0-3. Git 브랜치 생성
- `git checkout -b optimization/phase1` 형태로 Phase별 브랜치 분리
- 매 Step 완료 시 커밋하여 롤백 가능하도록 유지

---

## Phase 1: 🔴 볼류메트릭 라이트 루프 행렬 연산 제거 (매우 높은 효과)

> **대상 파일**: `shaders/lib/atmospherics/volumetricLight.glsl`, `volumetricBlocklight.glsl`
>
> **예상 효과**: GPU 시간 ~10-15% 감소

### Step 1-1. `volumetricLight.glsl` 레이 벡터 사전 계산

1. `GetVolumetricLight()` 함수의 `for` 루프 **진입 직전**(L136 위)에 다음을 추가:
   - `texCoord`과 `nViewPos`로부터 `viewRay` 방향 벡터 계산
   - `gbufferModelViewInverse`를 적용하여 `playerRay` 방향 벡터 계산
   - `shadowProjection * shadowModelView`를 결합한 `shadowMatrix` 계산
   - `playerStart`, `shadowStart` 기준점 계산
2. 루프 내부(L141~L158)의 기존 코드를 교체:
   - `vec4 viewPos = gbufferProjectionInverse * (...)` → **삭제**
   - `vec4 wpos = gbufferModelViewInverse * viewPos` → **삭제**
   - `vec3 playerPos = wpos.xyz / wpos.w` → `vec3 playerPos = playerStart + playerRay * currentDist`
   - 섀도 좌표도 동일하게 `shadowStart + shadowRay * currentDist`로 교체
3. **검증**: 낮 평야 장면에서 라이트 샤프트가 이전과 동일한지 스크린샷 비교

### Step 1-2. `volumetricBlocklight.glsl` 레이 벡터 사전 계산

1. `GetVolumetricBlocklight()` 함수의 `for` 루프 진입 전(L63 위)에 동일한 레이 사전 계산 추가
2. 루프 내부(L68~L71)의 행렬 곱을 FMA로 교체
3. **검증**: 동굴 장면에서 블록라이트 볼류메트릭 안개가 동일한지 스크린샷 비교

### Step 1-3. Phase 1 성능 측정
- Step 0-2와 동일한 5개 장면에서 GPU 시간 재측정
- `composite` 패스의 시간 변화량 기록
- 커밋: `perf: remove matrix math from volumetric light loops`

---

## Phase 2: 🔴 SDF 거리장 업데이트 분리 필터 적용 (매우 높은 효과)

> **대상 파일**: `shaders/program/shadowcomp_sdf_loop.glsl`
>
> **예상 효과**: shadowcomp 패스 텍스처 페치 ~66% 감소

### Step 2-1. 기존 27-tap 루프 분석
1. `shadowcomp_sdf_loop.glsl`의 `for (int k = 0; k < 27; k++)` 루프 구조를 정확히 이해
2. 이 파일이 `shadowcomp.glsl`에서 몇 번 `#include`되는지, 어떤 LOD 레벨에서 사용되는지 매핑

### Step 2-2. 3축 분리 필터(Separable Filter)로 변환
1. 기존 27-tap 루프를 제거
2. X축 3-tap → Y축 3-tap → Z축 3-tap 순서의 3단계 분리 필터로 교체
   - 각 축별로 `min(current, neighbor_left, neighbor_right)` 형태
   - 총 텍스처 페치: 27회 → 9회
3. 중간 결과 저장을 위해 `shared` 메모리 또는 임시 변수 활용

### Step 2-3. Phase 2 검증 및 성능 측정
- 동굴 장면에서 SDF 기반 그림자가 이전과 동일한지 확인
- `shadowcomp` 패스 GPU 시간 변화량 기록
- 커밋: `perf: replace 27-tap SDF loop with separable 3x3 filter`

---

## Phase 3: 🔴 블룸 가우시안 블러 분리형 전환 (매우 높은 효과)

> **대상 파일**: `shaders/program/composite4.glsl`
>
> **예상 효과**: 텍스처 페치 343회 → ~98회 (약 70% 감소)

### Step 3-1. 현재 블룸 구조 파악
1. `composite4.glsl`의 `BloomTile()` 함수가 7×7 2D 커널을 사용하는 구조 파악
2. `main()`에서 7개 LOD 타일을 호출하는 방식 파악
3. `shaders.properties`에서 composite 패스 간의 버퍼 라우팅 확인

### Step 3-2. 가로 패스 구현
1. `composite4.glsl`을 **가로(Horizontal) 블러 전용**으로 수정:
   - `BloomTile()` 내부의 2중 루프를 X축 단일 루프로 변경
   - 7-tap 1D 가우시안 가중치 적용
2. 출력을 중간 버퍼에 저장

### Step 3-3. 세로 패스 구현
1. `composite5.glsl`의 시작 부분(블룸 읽기 전)에 **세로(Vertical) 블러 패스** 추가하거나,
   별도의 composite 패스를 `shaders.properties`에 등록
2. 중간 버퍼에서 읽어 Y축 7-tap 1D 가우시안 적용
3. 최종 결과를 기존 블룸 출력 버퍼에 저장

### Step 3-4. Phase 3 검증 및 성능 측정
- 낮 평야 + 밤 마을 장면에서 블룸 글로우가 시각적으로 동일한지 비교
- `composite4~5` 패스 GPU 시간 변화량 기록
- 커밋: `perf: convert bloom to separable gaussian blur`

---

## Phase 4: 🟠 복셀 레이트레이싱 코어 최적화 (높은 효과)

> **대상 파일**: `shaders/lib/vx/voxelReading.glsl`, `prepare4_csh.glsl`, `prepare4_csh_a.glsl`
>
> **예상 효과**: VX 관련 패스 ~15-20% 성능 향상

### Step 4-1. `distanceFieldGradient` 6-tap → 4-tap 테트라헤드랄
1. `voxelReading.glsl` L18~L25의 6축 중앙 차분을 4-tap 테트라헤드랄 근사로 교체
2. **검증**: 동굴 장면에서 소프트 섀도 품질이 동일한지 비교

### Step 4-2. `voxelTrace` DDA 정수 최적화
1. `voxelReading.glsl` L110~L133에서 `ivec3 thisVoxelCoord`를 정수 벡터로 유지
2. 매 스텝마다 float→int 변환 대신 정수 덧셈(`+= ivec3(...)`)으로 전진
3. **검증**: 스테인드 글라스 통과 빛 색상이 동일한지 비교

### Step 4-3. `registerLight` 상수 배열화 + 해시 캐싱
1. `prepare4_csh.glsl` L134~L139의 이웃 오프셋을 `const ivec3[6]` 배열로 교체
2. L143과 L152의 `posToHash` 중복 호출을 로컬 변수 1회 캐싱으로 통합
3. **검증**: 밤 마을 장면에서 광원 색상 및 그림자 동일 확인

### Step 4-4. `prepare4_csh_a` 랜덤 생성 경량화
1. `prepare4_csh_a.glsl` L144~L195의 8-tap 루프 내 `randomGaussian()` 호출을
   사전 계산된 Halton 시퀀스 `const vec2[8]` 배열 룩업으로 교체
2. Golden Ratio 지터 연산의 프레임 상수 부분을 루프 밖으로 추출
3. **검증**: 광원 디노이징 품질이 동일한지 비교

### Step 4-5. `getColor` 좌표 캐싱
1. `voxelReading.glsl` L27~L45의 `coords * ivec3(1, 2, 1)` 중복 연산을 로컬 변수로 캐싱
2. **검증**: 반투명 틴트 색상 동일 확인

### Step 4-6. Phase 4 성능 측정
- 밤 마을 + 동굴 장면에서 `prepare4` 패스 GPU 시간 변화량 기록
- 커밋: `perf: optimize voxel ray tracing core (DF gradient, DDA, light registration)`

---

## Phase 5: 🟠 그림자 및 조명 파이프라인 최적화 (높은 효과)

> **대상 파일**: `shadow.glsl`, `shadowcomp.glsl`, `shadowcomp1.glsl`, `shadowcomp2.glsl`
>
> **예상 효과**: shadow 관련 패스 ~10-15% 성능 향상

### Step 5-1. `shadow.glsl` — textureGather 도입 및 Early-out 추가
1. GS 3×3 알파 탐색(L356~L360)의 9회 `textureLod`를 `textureGather`로 교체 (9→2회)
2. `DoNaturalShadowCalculation`(L39~L46)에 `color1.a ≈ 0.0 || ≈ 1.0` Early-out 추가
3. **검증**: 반투명 그림자(스테인드 글라스, 나뭇잎) 품질 동일 확인

### Step 5-2. `shadowcomp.glsl` — 엔티티 광원 병합 최적화
1. L178~L188의 이중 루프 광원 거리 비교를 공간 해시 그리드 버킷팅으로 교체
2. 같은 버킷 내 광원끼리만 거리 비교하여 O(N²) → ~O(N) 근사
3. **검증**: 밤 마을에서 엔티티 발광(알레이, 블레이즈 등) 동일 확인

### Step 5-3. `shadowcomp1.glsl` — 광원 거리 Fast Rejection 및 GI 노멀 캐싱
1. L308~L353의 `length(dir)` 거리 검사를 `dot(dir, dir)` 제곱 비교로 교체
2. L503~L545의 GI 히트 지점 노멀 계산에서 `getDistanceField` 6회 → 캐시 조회
3. **검증**: GI 간접광 색상 및 강도 동일 확인

### Step 5-4. `shadowcomp2.glsl` — Interactive Water 수면 탐색 최적화
1. L42~L54의 Y축 선형 하강 탐색을 SDF 기반 스킵(빈 공간 건너뛰기)으로 교체
2. **검증**: 물 표면 상호작용 파동이 동일하게 동작하는지 확인

### Step 5-5. Phase 5 성능 측정
- 밤 마을 + 지옥 장면에서 `shadow`, `shadowcomp` 패스 시간 변화량 기록
- 커밋: `perf: optimize shadow pipeline (textureGather, spatial hash, fast rejection)`

---

## Phase 6: 🟡 디퍼드/컴포짓 파이프라인 최적화 (중간 효과)

> **대상 파일**: `deferred1.glsl`, `deferred1_csh.glsl`, `composite.glsl`, `composite3.glsl`, `final.glsl`, `blocklightColors.glsl`, `ggx.glsl`
>
> **예상 효과**: 전체 프레임 ~3-5% 추가 개선

### Step 6-1. SSAO 삼각함수 제거
1. `deferred1.glsl` L51~L54의 `OffsetDist` 내부 `cos(n)`, `sin(n)` 호출을
   `const vec2[]` Poisson Disk 상수 배열 룩업으로 교체

### Step 6-2. 반사 필터링 `exp()` 경량화
1. `deferred1_csh.glsl` L152~L162의 `exp(-10 * ...)` 호출에
   벡터 차이 임계값 기반 Early-skip 추가 (차이가 미미하면 `weight = 0`)

### Step 6-3. Composite 조기 종료 / 지연 평가
1. `composite.glsl` L95~L133: 기능 비활성 시 viewPos 계산을 조건문 내부로 이동
2. `composite3.glsl` L134~L145: `z1 < 0.56` 검사를 `main()` 최상단으로 이동

### Step 6-4. SSBO 초기화 분리
1. `final.glsl` L146~L152의 SSBO 클리어 루프를 별도 컴퓨트 셰이더 패스로 분리
   (또는 `memoryBarrier` + 최소 스레드 수로 리팩토링)

### Step 6-5. 블록라이트 색상 LUT 전환
1. `blocklightColors.glsl`의 `GetSpecialBlocklightColor` if-else 트리(L18~L177)를
   1D `vec4` 텍스처 LUT로 교체
2. 초기화 시 97개 블록의 색상을 텍스처에 미리 기록
3. 함수 본체를 `return texelFetch(lightColorLUT, mat, 0)` 한 줄로 대체

### Step 6-6. GGX `GetNoHSquared` 경량화
1. `ggx.glsl` L2~L32의 Horizon Zero Dawn 구현을 경량 근사식으로 교체하거나,
   `(NdotL, NdotV)` 기반 2D LUT 텍스처 조회로 전환

### Step 6-7. Phase 6 검증 및 성능 측정
- 5개 전체 장면에서 스크린샷 비교 + GPU 시간 재측정
- 커밋: `perf: optimize deferred/composite pipeline (SSAO, LUT, early-out)`

---

## Phase 7: 🟢 마이크로 최적화 (낮은 효과)

> **대상 파일**: `skyColors.glsl`, `sky.glsl`, `irradianceCache.glsl`, `gbuffers_*.glsl`
>
> **예상 효과**: 전체 프레임 ~1-2% 추가 개선

### Step 7-1. 프레임 상수 Vertex Shader 이동
1. `skyColors.glsl`의 하늘 색상 계산을 Vertex Shader로 이동, `flat out`으로 전달
2. `gbuffers_terrain/water/entities/skybasic`의 `sunFactor`, `sunVisibility` 등도 동일 처리
3. `gbuffers_skybasic.glsl`의 달 렌더링 삼각함수(`sin`, `cos`)를 Vertex Shader로 이동

### Step 7-2. 수학 단순화
1. `sky.glsl` L30~L31: `pow(pow2(x), y)` → `pow(x, 2.0*y)` 변환
2. `irradianceCache.glsl`: `isInRange` 함수를 `all(lessThan(abs(vxPos), halfSize))` 단순화
3. `irradianceCache.glsl`: 좌표 변환 상수를 사전 결합하여 FMA 횟수 감소

### Step 7-3. 나눗셈 → 곱셈 교체
1. `gbuffers_terrain.glsl`, `gbuffers_entities.glsl` 등의
   `gl_FragCoord.xy / vec2(viewWidth, viewHeight)`를 `* invViewSize`로 교체
2. `invViewSize`는 Vertex Shader에서 `1.0 / vec2(viewWidth, viewHeight)` 계산 후 전달

### Step 7-4. Phase 7 검증 및 최종 성능 측정
- 5개 전체 장면 최종 스크린샷 비교
- 전체 패스별 GPU 시간 및 FPS 최종 기록
- 커밋: `perf: micro-optimizations (vertex precompute, math simplify)`

---

## Phase 8: 최종 검증 및 문서화

### Step 8-1. 최종 비주얼 동일성 검증
- Phase 0에서 촬영한 5개 기준 스크린샷과 최종 스크린샷을 **픽셀 단위** 비교
- 차이가 발생한 영역이 있다면 해당 Phase로 돌아가 원인 조사

### Step 8-2. 최종 성능 보고서 작성
- Phase별 GPU 시간 감소량을 표로 정리
- 전체 FPS 향상 수치 기록
- 특이 사항(엣지 케이스, 호환성 이슈 등) 기록

### Step 8-3. 브랜치 통합
- 모든 Phase 브랜치를 `main`으로 병합
- 최종 태그 생성: `v1.0-optimized`

---

## 요약 일정표

| Phase | 작업 내용 | 파일 수 | 난이도 | 예상 효과 |
|-------|----------|--------|--------|----------|
| 0 | 사전 준비 (스크린샷, 벤치마크, Git) | — | ⭐ | 기준선 |
| 1 | VL 루프 행렬 제거 | 2 | ⭐⭐ | ~10-15% |
| 2 | SDF 분리 필터 | 1 | ⭐⭐⭐ | ~5-10% |
| 3 | 블룸 분리형 블러 | 1~2 | ⭐⭐⭐ | ~5-8% |
| 4 | VX 코어 최적화 | 3 | ⭐⭐ | ~5-8% |
| 5 | 그림자 파이프라인 | 4 | ⭐⭐⭐ | ~5-8% |
| 6 | 디퍼드/컴포짓 | 7 | ⭐⭐ | ~3-5% |
| 7 | 마이크로 최적화 | 6+ | ⭐ | ~1-2% |
| 8 | 최종 검증 및 문서화 | — | ⭐ | 보고서 |

> **누적 예상 효과**: 전체 프레임 타임 약 **25-40% 감소** (GPU 바운드 기준)
