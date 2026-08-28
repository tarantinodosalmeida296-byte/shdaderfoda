# Pipeline Cinemática Ultra - GTX 750 Ti Optimized
## Arquitetura de Rendering Completa

Esta pipeline foi desenhada especificamente para extrair o máximo da arquitetura Maxwell (GM107).

### Orçamento de Frame: 13.3ms @ 1080p/75fps

```
┌─────────────────────────────────────────────────────────────┐
│                    FRAME TIMING BUDGET                       │
├─────────────────────────────────────────────────────────────┤
│ Geometry Pass        │ 1.5ms  │ Vertex + GBuffer Fill       │
│ Shadow Maps          │ 1.5ms  │ 3 Cascades, PCF 3x3         │
│ Lighting Pass        │ 3.0ms  │ Deferred + SSAO + SSR       │
│ Post-Process Stack   │ 4.0ms  │ Bloom→Tonemap→DOF→etc       │
│ Margem Segurança     │ 0.8ms  │ Spike protection            │
├─────────────────────────────────────────────────────────────┤
│ TOTAL                │ 10.8ms │ Target: 13.3ms (75fps)      │
└─────────────────────────────────────────────────────────────┘
```

### Estrutura de GBuffer Packed (3 RTs):

```
RT0 (RGBA8): [Albedo.r][Albedo.g][Albedo.b][Metallic]
RT1 (RGBA8): [Normal.x][Normal.y][Roughness ][AO       ]
             (Octahedron encoded normals)
RT2 (RGBA8): [Emission.r][Emission.g][Emission.b][MatID]
```

### Ordem de Renderização:

1. Depth Pre-pass (opcional, apenas para cenas complexas)
2. GBuffer Fill (3 render targets)
3. Shadow Map Pass (3 cascatas)
4. Ambient Pass (SH Order 2)
5. Direct Lighting Pass (deferred)
6. SSAO Pass (half-res, GTAO)
7. SSR Pass (hi-z traced)
8. Composite Lighting
9. Post-Process Stack:
   - Motion Blur
   - Depth of Field
   - Bloom (Dual Kawase)
   - Lens Flare
   - Color Grading + Tone Mapping
   - Chromatic Aberration
   - Vignette
   - Film Grain
   - FXAA/TAA
   - CAS Sharpen
10. UI Overlay

---

Abaixo estão todos os shaders completos e funcionais.
