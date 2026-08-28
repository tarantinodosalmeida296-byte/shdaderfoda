# 🚀 PIPELINE CINEMÁTICA ULTRA - GTX 750 Ti OPTIMIZED
## A Melhor Pipeline de Rendering do Universo (para a 750 Ti)

```
┌─────────────────────────────────────────────────────────────────┐
│                    GTX 750 Ti SPECIFICATIONS                     │
├─────────────────────────────────────────────────────────────────┤
│ GPU: GM107 (Maxwell First Gen)                                  │
│ CUDA Cores: 640                                                  │
│ VRAM: 2GB GDDR5                                                  │
│ Memory Bandwidth: 88.4 GB/s                                     │
│ Peak FP32: ~1.4 TFLOPS                                          │
│ Target: 75+ FPS @ 1080p                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 ESTRUTURA DE FICHEIROS

```
shaders/
├── vertex/
│   └── gbuffer_vert.glsl          # GBuffer Vertex Shader
├── fragment/
│   ├── gbuffer_frag.glsl          # GBuffer Fragment (Packed)
│   ├── lighting_frag.glsl         # Deferred Lighting Pass
│   ├── ssao_frag.glsl             # Ground Truth AO
│   └── ssr_frag.glsl              # Screen Space Reflections
├── postprocess/
│   ├── bloom_frag.glsl            # Dual Kawase Bloom
│   ├── tonemap_frag.glsl          # ACES + Color Grading
│   ├── dof_frag.glsl              # Depth of Field
│   ├── motionblur_frag.glsl       # Per-Object Motion Blur
│   ├── fxaa_frag.glsl             # FXAA 3.11
│   ├── cas_frag.glsl              # Contrast Adaptive Sharpen
│   ├── fog_frag.glsl              # Atmospheric Fog
│   ├── lensflare_frag.glsl        # Screen Space Lens Flare
│   └── autoexposure_frag.glsl     # Auto Exposure
├── shadows/
│   └── shadowmap_vert.glsl        # Cascaded Shadow Maps
└── utils/
    └── (common functions aqui)
```

---

## 🎯 ORDEM DE RENDERIZAÇÃO COMPLETA

### PASSO 1: GEOMETRY PASS (1.5ms)
```cpp
// GBuffer Fill
glBindFramebuffer(GBUFFER_FBO);
glDrawArrays(GL_TRIANGLES, ...);
// Outputs:
//   RT0: Albedo.rgb + Metallic.a (RGBA8)
//   RT1: Normal.xy (octahedron) + Roughness.z + AO.w (RGBA8)
//   RT2: Emission.rgb + MatID.a (RGBA8)
//   Depth: Depth buffer (R32F)
```

### PASSO 2: SHADOW MAPS (1.5ms)
```cpp
// 3 Cascatas de Shadow Maps
for (int cascade = 0; cascade < 3; cascade++) {
    glBindFramebuffer(SHADOW_FBO[cascade]);
    glViewport(0, 0, 2048, 2048);
    // Render geometry em depth-only mode
}
```

### PASSO 3: AMBIENT PASS (0.3ms)
```cpp
// Spherical Harmonics Order 2
// Calculado no lighting pass
```

### PASSO 4: DIRECT LIGHTING (1.2ms)
```cpp
// Deferred lighting com PBR simplificado
glBindFramebuffer(LIGHTING_FBO);
// Sample GBuffer + Shadow Maps
// GGX Schlick approximation
```

### PASSO 5: SSAO (0.8ms - half-res)
```cpp
// GTAO half-resolution
glViewport(0, 0, 960, 540);
glBindFramebuffer(SSAO_FBO);
// 8 directions, 4 samples cada
// Bilateral upscale depois
```

### PASSO 6: SSR (1.0ms - half-res)
```cpp
// Screen Space Reflections
glViewport(0, 0, 960, 540);
glBindFramebuffer(SSR_FBO);
// Hi-Z traced, 16 steps max
// Binary search refinement
```

### PASSO 7: COMPOSITE LIGHTING (0.2ms)
```cpp
// Juntar direct + ambient + SSAO + SSR
glBindFramebuffer(COMPOSITE_FBO);
// Blend todos os componentes
```

### PASSO 8: POST-PROCESSING STACK (3.5ms total)

#### 8.1: Motion Blur (0.4ms)
```cpp
glBindFramebuffer(MOTIONBLUR_FBO);
// Usar velocity buffer do GBuffer pass
// 5-7 samples ao longo do vector
```

#### 8.2: Depth of Field (0.5ms - half-res)
```cpp
glViewport(0, 0, 960, 540);
// Horizontal blur pass
glBindFramebuffer(DOF_H_FBO);
// Vertical blur pass
glBindFramebuffer(DOF_V_FBO);
// Separable blur baseado em CoC
```

#### 8.3: Bloom (0.6ms)
```cpp
// Bright pass extract
glBindFramebuffer(BLOOM_EXTRACT_FBO);
// 4x Downscale passes (Dual Kawase)
for (int i = 0; i < 4; i++) {
    // Downscale + blur combinados
}
// 4x Upscale passes
// Combine com source
```

#### 8.4: Lens Flare (0.2ms)
```cpp
glBindFramebuffer(FLARE_FBO);
// Threshold detection
// Render ghosts + glow
// Blend aditivo
```

#### 8.5: Auto Exposure (0.1ms)
```cpp
// Downscale luminance chain
// Calcular average log luminance
// Temporal smoothing
// Output: exposure value
```

#### 8.6: Tone Mapping + Color Grading (0.3ms)
```cpp
glBindFramebuffer(TONEMAP_FBO);
// Apply exposure
// ACES Filmic tone mapping
// 3D LUT color grading
// Chromatic aberration
// Vignette
// Film grain + dithering
```

#### 8.7: FXAA (0.25ms)
```cpp
glBindFramebuffer(FXAA_FBO);
// Edge detection
// Sub-pixel aliasing removal
// Quality preset 12
```

#### 8.8: CAS Sharpen (0.2ms)
```cpp
glBindFramebuffer(FINAL_FBO);
// Contrast adaptive sharpen
// Clamp para evitar ringing
```

### PASSO 9: UI OVERLAY (0.1ms)
```cpp
// Render UI elements
// Blended over final image
```

---

## ⏱️ FRAME TIMING BREAKDOWN

```
┌──────────────────────┬──────────┬─────────────┐
│ Pass                 │ Tempo    │ Acumulado   │
├──────────────────────┼──────────┼─────────────┤
│ Geometry/GBuffer     │ 1.50ms   │ 1.50ms      │
│ Shadow Maps (3x)     │ 1.50ms   │ 3.00ms      │
│ Direct Lighting      │ 1.20ms   │ 4.20ms      │
│ SSAO (half-res)      │ 0.80ms   │ 5.00ms      │
│ SSR (half-res)       │ 1.00ms   │ 6.00ms      │
│ Composite            │ 0.20ms   │ 6.20ms      │
│ Motion Blur          │ 0.40ms   │ 6.60ms      │
│ Depth of Field       │ 0.50ms   │ 7.10ms      │
│ Bloom                │ 0.60ms   │ 7.70ms      │
│ Lens Flare           │ 0.20ms   │ 7.90ms      │
│ Auto Exposure        │ 0.10ms   │ 8.00ms      │
│ Tone Mapping         │ 0.30ms   │ 8.30ms      │
│ FXAA                 │ 0.25ms   │ 8.55ms      │
│ CAS Sharpen          │ 0.20ms   │ 8.75ms      │
│ UI Overlay           │ 0.10ms   │ 8.85ms      │
├──────────────────────┼──────────┼─────────────┤
│ TOTAL                │ 8.85ms   │ 113 FPS     │
│ Margem Segurança     │ 4.45ms   │             │
├──────────────────────┼──────────┼─────────────┤
│ BUDGET TOTAL         │ 13.30ms  │ 75 FPS      │
└──────────────────────┴──────────┴─────────────┘
```

**Nota:** Os tempos são estimados para uma cena típica AAA. 
Cenas mais complexas podem requerer LOD adjustments.

---

## 💾 VRAM BUDGET (2GB Total)

```
┌──────────────────────────┬───────────┬──────────┐
│ Allocation               │ Tamanho   │ % VRAM   │
├──────────────────────────┼───────────┼──────────┤
│ GBuffer (3x RGBA8)       │ 24 MB     │ 1.2%     │
│ Depth Buffer (R32F)      │ 8 MB      │ 0.4%     │
│ Shadow Maps (3x R32F)    │ 32 MB     │ 1.6%     │
│ Motion Velocity Buffer   │ 8 MB      │ 0.4%     │
│ Hi-Z Buffer              │ 12 MB     │ 0.6%     │
│ SSAO Buffer (half-res)   │ 2 MB      │ 0.1%     │
│ SSR Buffer (half-res)    │ 2 MB      │ 0.1%     │
│ Bloom Chain (4 mips)     │ 10 MB     │ 0.5%     │
│ DOF Buffers (half-res)   │ 4 MB      │ 0.2%     │
│ Post-Process Temporaries │ 20 MB     │ 1.0%     │
│ Scene Textures           │ 800 MB    │ 40.0%    │
│ LUTs (BRDF, Color, etc)  │ 16 MB     │ 0.8%     │
│ Noise Textures           │ 4 MB      │ 0.2%     │
│ Vertex/Index Buffers     │ 200 MB    │ 10.0%    │
│ Uniform Buffers          │ 8 MB      │ 0.4%     │
├──────────────────────────┼───────────┼──────────┤
│ TOTAL USADO              │ 1150 MB   │ 57.5%    │
│ MARGEM SEGURA            │ 898 MB    │ 42.5%    │
├──────────────────────────┼───────────┼──────────┤
│ VRAM TOTAL               │ 2048 MB   │ 100%     │
└──────────────────────────┴───────────┴──────────┘
```

---

## 🔧 UNIFORM BUFFER OBJECTS

### Global UBO (Binding 0)
```glsl
layout(std140, binding = 0) uniform GlobalUBO {
    mat4 uModelMatrix;
    mat4 uViewMatrix;
    mat4 uProjectionMatrix;
    mat4 uModelViewMatrix;
    mat4 uMVP;
    mat4 uPrevMVP;              // Para motion blur
    vec3 uViewPosition;
    float uTime;
    vec4 uSunDirection;
    vec4 uFogParams;
};
```

### Material UBO (Binding 1)
```glsl
layout(std140, binding = 1) uniform MaterialUBO {
    vec4 uBaseColor;
    vec4 uNormalScale;
    vec4 uRoughnessMetallic;
    vec4 uDetailScale;
    float uParallaxDepth;
    int uMaterialType;
};
```

### Light UBO (Binding 2)
```glsl
layout(std140, binding = 2) uniform LightUBO {
    vec4 uLightColor;
    vec4 uLightDirection;
    vec3 uAmbientColor;
    float uExposure;
    vec4 uShadowCascadeSplits;
    mat4 uShadowMatrices[3];
};
```

---

## 🎨 TEXTURE BINDINGS

```
Binding  | Texture                  | Format    | Usage
─────────┼──────────────────────────┼───────────┼─────────────────────
0-5      | Material Textures        | Various   | Albedo, Normal, ORM
10       | GBuffer0                 | RGBA8     | Albedo + Metallic
11       | GBuffer1                 | RGBA8     | Normal + Rough + AO
12       | GBuffer2                 | RGBA8     | Emission + MatID
13       | Depth Buffer             | R32F      | Depth
20-22    | Shadow Maps              | R32F      │ 3 Cascatas
30       | BRDF LUT                 | RG16F     | Pre-computed BRDF
40       | Blue Noise               | R8        | Dithering/Grain
50       | Hi-Z Buffer              | R32F      | SSR acceleration
60-61    | Bloom Chain              | RGBA16F   | Bloom mip chain
70       | ToneMap Source           | RGBA16F   | Input cena
71       | Color Grading LUT        | RGBA8     | 3D LUT 16³→256x16
72       | Film Grain               | R8        | Blue noise grain
80       | DOF Source               | RGBA16F   | Input DOF
90       | Source                   | RGBA16F   | Motion blur input
91       | Velocity Buffer          | RG16F     | Screen velocity
100      | FXAA Source              | RGBA8     | AA input
110      | CAS Source               | RGBA8     | Sharpen input
120      | Flare Source             | RGBA16F   | Threshold detect
121      | Flare Sprites            | RGBA8     | Ghost sprites
122      | Flare Glow               | RGBA8     | Glow texture
130      | AE Source                | RGBA16F   | Exposure calculation
```

---

## ⚙️ DEFINES DE COMPILAÇÃO RECOMENDADOS

```glsl
// Performance presets
#define GTX_750_TI_OPTIMIZED
#define MAX_SHADOW_CASCADES 3
#define SSAO_HALF_RES
#define SSR_HALF_RES
#define BLOOM_MIP_LEVELS 4
#define FXAA_QUALITY_PRESET 12

// Feature toggles
#define ENABLE_SSR
#define ENABLE_SSAO
#define ENABLE_BLOOM
#define ENABLE_DOF
#define ENABLE_MOTION_BLUR
#define ENABLE_FILM_GRAIN
#define ENABLE_CHROMATIC_ABERRATION

// Precision hints (para mobile/drivers específicos)
#ifdef GL_ES
precision mediump float;
#endif
```

---

## 🚨 DICAS DE OTIMIZAÇÃO CRÍTICAS

1. **Sempre usar Early-Z** - Não usar `discard` ou `clip()` no GBuffer pass
2. **Texture compression** - BC1/BC3/BC7 para todas as texturas
3. **MIP maps obrigatórios** - Evitar cache misses em minification
4. **Batch draws** - Minimizar state changes e bind calls
5. **Instancing** - Para objetos repetidos (vegetação, props)
6. **Frustum culling** - CPU-side antes de enviar para GPU
7. **LOD system** - Reduzir complexidade geométrica com distância
8. **Async compute** - Se disponível, usar para post-process paralelo

---

## 📊 QUALIDADE VISUAL ESPERADA

```
Iluminação:     ████████░░ 80% (vs RTX real)
Sombras:        ███████░░░ 70% (vs Ray-traced)
Reflexos:       ██████░░░░ 60% (vs SSR full-res)
Materiais:      █████████░ 90% (vs Path-traced)
Post-Process:   █████████░ 90% (vs Offline render)
Performance:    ██████████ 100% (75+ FPS estáveis)
```

---

## 🎬 ESTILO VISUAL ALVO

- **Iluminação suave** tipo Pixar/Disney
- **Profundidade atmosférica** estilo Red Dead Redemption 2
- **Color grading cinematográfico** como God of War (2018)
- **Nitidez e clareza** estilo Horizon Zero Dawn
- **Tudo isso a 75+ FPS na GTX 750 Ti**

---

*"Neste universo, a GTX 750 Ti é a rainha das GPUs. Cada shader foi forjado nas chamas da otimização extrema, cada instrução MAD conta, cada texture fetch é precioso. Esta é a pipeline definitiva para o hardware Maxwell."*

🚀 **Agora vai e faz esta 750 Ti voar!**
