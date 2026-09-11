import Foundation

/// The fold, in one full-screen fragment pass.
///
/// Every glass pixel maps back into the frozen picture through the inverse
/// perspective. The picture lives on a black margin inside one texture with a
/// Gaussian pyramid over it, so the blur is a tent of trilinear samples at a
/// level chosen per pixel. Frost, dimming, sheen and grain follow the
/// picture's own height above the hinge, normalised to what the glass shows.
public enum DuoShaders {
    public static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 column0;          // screen → picture, column 0 in xyz
        float4 column1;
        float4 column2;
        float4 screenAndOrigin;  // screen size (pt), padded origin (pt)
        float4 paddedAndBlur;    // padded size (pt), max radius (px), blur strength
        float4 shape;            // blur floor, max dim, pixel scale, max mip level
        float4 light;            // dim start, dim strength, visible top, sheen amount
        float4 extra;            // sheen position, grain, time, dim reach
        float4 more;             // dim floor at the hinge, recede, picture top edge on the glass
    };

    // Fills the padded picture from a frame: inside, the frame itself; the
    // margin is black, so the blur lets the picture's edges dissolve into
    // the dark.
    struct PadUniforms {
        float4 inset;   // inset in pixels (x, y), frame size in pixels (z, w)
    };

    fragment float4 padFragment(float4 position [[position]],
                                constant PadUniforms &u [[buffer(0)]],
                                texture2d<float> frame [[texture(0)]]) {
        constexpr sampler edge(filter::linear, address::clamp_to_edge);
        float2 uv = (position.xy - u.inset.xy) / u.inset.zw;
        if (any(uv < 0.0) || any(uv > 1.0)) { return float4(0.0, 0.0, 0.0, 1.0); }
        return float4(frame.sample(edge, uv).rgb, 1.0);
    }

    vertex float4 duoVertex(uint id [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(corners[id], 0.0, 1.0);
    }

    static inline float hash(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 duoFragment(float4 position [[position]],
                                constant Uniforms &u [[buffer(0)]],
                                texture2d<float> picture [[texture(0)]]) {
        constexpr sampler smooth(filter::linear, mip_filter::linear, address::clamp_to_edge);

        const float2 screenSize   = u.screenAndOrigin.xy;
        const float2 paddedOrigin = u.screenAndOrigin.zw;
        const float2 paddedSize   = u.paddedAndBlur.xy;
        const float  maxRadius    = u.paddedAndBlur.z;
        const float  blurStrength = u.paddedAndBlur.w;
        const float  blurFloor    = u.shape.x;
        const float  maxDim       = u.shape.y;
        const float  pixelScale   = u.shape.z;
        const float  maxLevel     = u.shape.w;
        const float  dimStart     = u.light.x;
        const float  dimStrength  = u.light.y;
        const float  visibleTop   = u.light.z;
        const float  sheenAmount  = u.light.w;
        const float  sheenPos     = u.extra.x;
        const float  grain        = u.extra.y;
        const float  time         = u.extra.z;
        const float  dimReach     = u.extra.w;
        const float  dimHinge     = u.more.x;
        const float  recede       = u.more.y;
        const float  topEdge      = u.more.z;

        // Fragments are pixels with y down; the geometry is points with y up.
        float2 screenPoint = float2(position.x / pixelScale, screenSize.y - position.y / pixelScale);
        // Above the picture's far edge the glass carries the edge's own light,
        // fading in screen space, so there is never a hard line where the
        // picture ends. Rows above the edge sample the edge itself.
        float above = max(screenPoint.y - (topEdge - 2.0), 0.0);
        screenPoint.y = min(screenPoint.y, topEdge - 2.0);
        float3x3 toPicture = float3x3(u.column0.xyz, u.column1.xyz, u.column2.xyz);
        float3 mapped = toPicture * float3(screenPoint, 1.0);
        if (abs(mapped.z) < 1e-6) { return float4(0.0, 0.0, 0.0, 1.0); }
        float2 picturePoint = mapped.xy / mapped.z;

        // Behind the eye there is nothing to show.
        if (mapped.z < 0.0) { return float4(0.0, 0.0, 0.0, 1.0); }

        // Outside the padded picture there is only the dark.
        float2 unit = (picturePoint - paddedOrigin) / paddedSize;
        if (any(unit < 0.0) || any(unit > 1.0)) { return float4(0.0, 0.0, 0.0, 1.0); }
        float2 clampedPoint = clamp(picturePoint, float2(0.0), screenSize);
        float2 texCoord = float2(unit.x, 1.0 - unit.y);

        // Height above the hinge in the picture: 0 at the hinge, 1 at the far
        // edge. Frost and darkness follow it linearly.
        float g = clamp(clampedPoint.y / screenSize.y, 0.0, 1.0);

        // Frost. The far edge dissolves first; the hinge stays readable.
        float blur = blurStrength * (blurFloor + (1.0 - blurFloor) * g);
        float radius = blur * maxRadius;
        // Naming this `level` would shadow Metal's level() selector.
        float mip = clamp(log2(max(radius, 1.0)), 0.0, maxLevel);

        float3 colour;
        if (radius < 0.75) {
            colour = picture.sample(smooth, texCoord, level(0.0)).rgb;
        } else {
            // A 3×3 tent of trilinear taps hides the pyramid's steps.
            float2 texel = 1.0 / (paddedSize * pixelScale);
            float2 stride = texel * radius * 0.45;
            colour = float3(0.0);
            const float weights[3] = { 1.0, 2.0, 1.0 };
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    float w = weights[x + 1] * weights[y + 1] / 16.0;
                    colour += picture.sample(smooth, texCoord + float2(x, y) * stride, level(mip)).rgb * w;
                }
            }
        }
        // Dimming, in linear light so the far edge fades into the dark
        // rather than going grey. It reaches full strength at `dimReach`;
        // the hinge sinks a little too, so the whole picture recedes.
        float spread = smoothstep(dimStart, max(dimReach, dimStart + 0.05), g);
        float dim = dimStrength * (dimHinge + (1.0 - dimHinge) * spread) * maxDim;
        colour *= pow(1.0 - dim, 2.2) * recede;
        colour *= exp(-pow(above / max(0.22 * screenSize.y, 1.0), 1.4));

        // Sheen: a soft band of light crossing the frost, tinted by the
        // picture's own average colour (the top of the pyramid).
        if (sheenAmount > 0.0005) {
            float band = exp(-pow((g - sheenPos) / 0.22, 2.0));
            float3 average = picture.sample(smooth, float2(0.5, 0.5), level(maxLevel)).rgb;
            float3 tint = 0.55 + 0.45 * average;
            colour += sheenAmount * band * tint * (1.0 - 0.5 * dim) * recede;
        }

        // Grain, so a dark gradient does not band.
        float noise = hash(position.xy + fract(time) * 17.0) - 0.5;
        colour += noise * grain * (2.5 / 255.0);

        return float4(max(colour, 0.0), 1.0);
    }
    """
}
