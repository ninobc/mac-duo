# How the fold is built

## The model

The hinge runs along x. y is up, z points at the person. A point at height `h` on a lid open to angle θ (0° flat, 90° upright) sits at `(x, h·sinθ, h·cosθ)`; the glass faces `(0, −cosθ, sinθ)`.

When the lid passes the **start angle** θ₀, the desktop is frozen as a plane P at θ₀. As the lid keeps turning to θ, the picture the glass shows is what a fixed eye E sees of P *through* the glass: for each of P's corners, cast a ray from E and intersect the glass plane. That gives a quadrilateral on the glass; a homography maps the picture rectangle onto it, and the shader uses the inverse to look up each glass pixel in the picture. At θ = θ₀ the quad is the screen itself, so there is no seam when the fold starts.

The eye sits `eyeDistance` screen heights in front of the screen centre along the glass normal at θ₀, lifted `eyeHeight` screen heights (people look slightly down at a laptop). `depth` scales how far the picture lags behind the lid: 1 holds it exactly where it was in the room, 0 lets it ride with the glass, more leans it away harder.

Because the glass folds towards the eye it covers less of the room, so the picture's far edge climbs past the top of the glass and its sides draw in. That is the "content locked in space" illusion.

## The shader

One full-screen pass. The picture lives on a black margin (176 pt) inside a mipmapped texture with a Gaussian pyramid over it (MPSImageGaussianPyramid), rebuilt whenever a live frame lands.

Per pixel:

1. Map to picture coordinates through the inverse homography. Outside the padded texture is black.
2. `height` = picture y / screen height, clamped; `g` = height normalised by how much of the picture the glass still shows at its top edge, so the glass's own far edge always reads as 1.
3. **Frost**: radius = blurStrength · (floor + (1−floor)·g^1.35) · maxRadius. The blur is a 3×3 tent of trilinear samples at mip level log₂(radius). Past the picture's edge the radius has a floor and the colour fades with distance (`exp(−(d/reach)^1.3)`), so the picture's light leaks into the dark instead of cutting off.
4. **Dim**: spread = (g − dimStart)/(1 − dimStart); dim = dimStrength · spread^1.9 · maxDim; colour *= (1 − dim)^1.6 in linear light.
5. **Sheen**: a Gaussian band across g whose position runs 0.15 → 0.9 with progress and whose strength peaks mid-fold, tinted by the picture's average colour (the top of the pyramid).
6. **Grain**: ±1.25/255 hash noise.

`blurStrength = progress^1.45`, `dimStrength = progress^0.9`, and `progress = smoothstep((θ₀ − θ)/span)`.

## Motion

The sensor reports about every 100 ms. `AngleTracker` keeps a velocity estimate and predicts where a fast-closing lid actually is; `FoldDecider` arms the capture as the lid comes down and starts the fold when the predicted angle crosses θ₀, with hysteresis and a minimum duration. `DampedSpring` (ω = 14 rad/s, critically damped) turns the 10 Hz steps into a value that moves smoothly at the display refresh rate.

## Capture

A ScreenCaptureKit stream of the built-in display is started while the lid is still above the start angle and handed over as IOSurface-backed Metal textures; a screenshot seeds the picture if the stream has no frame yet. The app's own windows are excluded from the filter. The overlay is a borderless window at the shielding level that ignores clicks; its Metal layer is deliberately non-opaque so the window server keeps the apps underneath drawing.
