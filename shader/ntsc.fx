// ntsc.fx - NTSC/VHS analog video effect for gamescope
// Simulates composite color bleed, tape noise, scanlines, and head-switching.
//
// Compatible with gamescope --reshade-effect / --reshade-techs NTSCEffect
// Avoids static const arrays and [unroll] for maximum reshadefx compatibility.

// ─────────────────────────────────────────────
// Built-in uniforms
// ─────────────────────────────────────────────
uniform float Timer < source = "timer"; >;

// ─────────────────────────────────────────────
// Tunable parameters
// ─────────────────────────────────────────────
uniform float ChromaBleed <
    ui_label = "Chroma Bleed";
    ui_type  = "drag";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.80;

uniform float ChromaShiftPixels <
    ui_label = "Chroma Shift (pixels)";
    ui_type  = "drag";
    ui_min = 0.0; ui_max = 8.0; ui_step = 0.5;
> = 2.0;

uniform float LumaNoise <
    ui_label = "Luma Noise";
    ui_type  = "drag";
    ui_min = 0.0; ui_max = 0.15; ui_step = 0.005;
> = 0.025;

uniform float ChromaNoise <
    ui_label = "Chroma Noise";
    ui_type  = "drag";
    ui_min = 0.0; ui_max = 0.30; ui_step = 0.005;
> = 0.050;

uniform float ScanlineStrength <
    ui_label = "Scanline Strength";
    ui_type  = "drag";
    ui_min = 0.0; ui_max = 0.80; ui_step = 0.01;
> = 0.25;

uniform float VHSWobble <
    ui_label = "VHS Tape Wobble";
    ui_type  = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.40;

uniform float HeadSwitching <
    ui_label = "Head Switching Noise";
    ui_type  = "drag";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.60;

// ─────────────────────────────────────────────
// Texture / sampler
// ─────────────────────────────────────────────
texture ReShade__BackBufferTex : COLOR;
sampler BackBuffer {
    Texture   = ReShade__BackBufferTex;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
};

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────
float hash(float2 p)
{
    p  = frac(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return frac(p.x * p.y);
}

float3 rgb2yiq(float3 c)
{
    return float3(
        dot(c, float3( 0.2990,  0.5870,  0.1140)),
        dot(c, float3( 0.5959, -0.2746, -0.3213)),
        dot(c, float3( 0.2115, -0.5227,  0.3112))
    );
}

float3 yiq2rgb(float3 c)
{
    return float3(
        dot(c, float3(1.0,  0.9563,  0.6210)),
        dot(c, float3(1.0, -0.2721, -0.6474)),
        dot(c, float3(1.0, -1.1070,  1.7046))
    );
}

// 7-tap horizontal Gaussian blur returning averaged YIQ
// Manually unrolled — avoids static const arrays and loop pragmas
float3 chromaBlur(float2 center_uv, float spread)
{
    float px = BUFFER_RCP_WIDTH;
    float3 acc =
        rgb2yiq(tex2D(BackBuffer, center_uv + float2(-3.0 * px * spread, 0.0)).rgb) * 0.0540
      + rgb2yiq(tex2D(BackBuffer, center_uv + float2(-2.0 * px * spread, 0.0)).rgb) * 0.1216
      + rgb2yiq(tex2D(BackBuffer, center_uv + float2(-1.0 * px * spread, 0.0)).rgb) * 0.1945
      + rgb2yiq(tex2D(BackBuffer, center_uv                                       ).rgb) * 0.2270
      + rgb2yiq(tex2D(BackBuffer, center_uv + float2( 1.0 * px * spread, 0.0)).rgb) * 0.1945
      + rgb2yiq(tex2D(BackBuffer, center_uv + float2( 2.0 * px * spread, 0.0)).rgb) * 0.1216
      + rgb2yiq(tex2D(BackBuffer, center_uv + float2( 3.0 * px * spread, 0.0)).rgb) * 0.0540;
    // weights sum to ~0.9672, close enough — skip the divide for perf
    return acc;
}

// ─────────────────────────────────────────────
// Vertex shader
// ─────────────────────────────────────────────
void VS_NTSC(
    in  uint   id  : SV_VertexID,
    out float4 pos : SV_Position,
    out float2 uv  : TEXCOORD0)
{
    uv  = float2((id == 2) ? 2.0 : 0.0,
                 (id == 1) ? 2.0 : 0.0);
    pos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// ─────────────────────────────────────────────
// Main pixel shader
// ─────────────────────────────────────────────
float4 PS_NTSC(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float px = BUFFER_RCP_WIDTH;
    float py = BUFFER_RCP_HEIGHT;
    float t  = Timer * 0.001;

    // 1. VHS tape wobble
    float wobble =
          sin(uv.y * 137.0 + t * 8.7)  * 0.00025 * VHSWobble
        + sin(uv.y * 311.0 + t * 5.1)  * 0.00010 * VHSWobble
        + sin(uv.y *  47.0 + t * 13.3) * 0.00005 * VHSWobble;
    float2 wuv = float2(uv.x + wobble, uv.y);

    // 2. VHS head-switching glitch (bottom ~7%)
    float frame   = floor(t * 30.0);
    float hs      = smoothstep(0.93, 1.0, uv.y) * HeadSwitching;
    float hsShift = (hash(float2(frame, floor(uv.y * BUFFER_HEIGHT))) - 0.5) * 0.06 * hs;
    wuv.x = frac(wuv.x + hsShift);

    // 3. Chroma shift (luma/chroma misalignment)
    float2 chromaUV = float2(wuv.x + ChromaShiftPixels * px, wuv.y);

    // 4. Horizontal chroma bleed — luma from unshifted, chroma from shifted+blurred
    float spread = 1.0 + ChromaBleed * 4.0;
    float3 lumaBlur   = chromaBlur(wuv,     spread);
    float3 chromaBlur_ = chromaBlur(chromaUV, spread);

    float3 yiq = float3(lumaBlur.x, chromaBlur_.y, chromaBlur_.z);
    yiq.y *= 1.0 + ChromaBleed * 0.25;
    yiq.z *= 1.0 + ChromaBleed * 0.25;

    // 5. Analog noise (updates at ~30 fps)
    float2 noiseP = float2(wuv.x * BUFFER_WIDTH, floor(wuv.y * BUFFER_HEIGHT));
    float  nf     = floor(t * 30.0);
    float  ln  = (hash(noiseP              + nf * 47.31) - 0.5) * 2.0 * LumaNoise;
    float  in_ = (hash(noiseP * 0.73 + nf * 83.17 + float2(100.0, 0.0)) - 0.5) * 2.0 * ChromaNoise;
    float  qn  = (hash(noiseP * 0.73 + nf * 61.73 + float2(200.0, 0.0)) - 0.5) * 2.0 * ChromaNoise;
    yiq += float3(ln, in_, qn);

    // 6. Scanlines
    float scan = 1.0 - ScanlineStrength
                     * pow(sin(uv.y * BUFFER_HEIGHT * 3.14159265), 2.0)
                     * 0.5;
    yiq.x *= scan;

    // 7. Back to RGB
    float3 rgb = clamp(yiq2rgb(yiq), 0.0, 1.0);
    return float4(rgb, 1.0);
}

// ─────────────────────────────────────────────
// Technique
// ─────────────────────────────────────────────
technique NTSCEffect {
    pass {
        VertexShader = VS_NTSC;
        PixelShader  = PS_NTSC;
    }
}
