// The Mac Duo fold, in WebGL2, driven by scroll or the slider.
//
// This is the same construction as the app's Metal shader: a desktop is
// frozen at the start angle; each glass pixel maps back into it through the
// inverse of the perspective; frost, dimming and sheen follow the picture's
// height above the hinge. The wallpaper here is a stand-in for your desktop.
(function () {
  'use strict';
  const canvas = document.getElementById('fold');
  const angleLabel = document.getElementById('angle');
  const lidLine = document.getElementById('lid-line');
  const hint = document.getElementById('hint');
  const scrub = document.getElementById('scrub');
  const hero = document.getElementById('hero');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Duo preset, mirrored from EffectSettings.duo in the app.
  const effect = { startAngle: 100, span: 60, blurRadius: 72, blurFloor: 0.06, dimming: 1, dimStart: 0.12,
                   depth: 1, eyeDistance: 2.6, eyeHeight: 0.15, sheen: 0.5, grain: 0.5 };
  const OPEN = 108, SHUT = 34;

  const gl = canvas.getContext('webgl2', { antialias: false, alpha: false, preserveDrawingBuffer: false });
  if (!gl) { canvas.remove(); hint.textContent = 'Your browser can\'t show the demo'; return; }

  const vs = `#version 300 es
  void main() { vec2 c[3] = vec2[3](vec2(-1.,-3.), vec2(-1.,1.), vec2(3.,1.)); gl_Position = vec4(c[gl_VertexID], 0., 1.); }`;
  const fs = `#version 300 es
  precision highp float;
  uniform sampler2D picture;
  uniform mat3 toPicture;          // screen point → picture point
  uniform vec2 screenSize;         // in points
  uniform vec2 paddedOrigin, paddedSize;
  uniform vec2 canvasSize;         // in pixels
  uniform float pixelScale, maxRadius, blurStrength, blurFloor, maxDim, maxLevel, dimStart, dimStrength, visibleTop, sheenAmount, sheenPos, grain, time;
  out vec4 fragColor;
  float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
  void main() {
    vec2 screenPoint = vec2(gl_FragCoord.x, gl_FragCoord.y) / pixelScale;
    vec3 m = toPicture * vec3(screenPoint, 1.0);
    if (abs(m.z) < 1e-6) { fragColor = vec4(0,0,0,1); return; }
    vec2 pp = m.xy / m.z;
    vec2 unit = (pp - paddedOrigin) / paddedSize;
    if (any(lessThan(unit, vec2(0))) || any(greaterThan(unit, vec2(1)))) { fragColor = vec4(0,0,0,1); return; }
    vec2 edge = max(-pp, pp - screenSize);
    float outside = max(max(edge.x, edge.y), 0.0);
    vec2 cp = clamp(pp, vec2(0), screenSize);
    vec2 cu = (cp - paddedOrigin) / paddedSize;
    vec2 tc = vec2(cu.x, 1.0 - cu.y);
    float height = clamp(cp.y / screenSize.y, 0.0, 1.0);
    float g = clamp(height / max(visibleTop, 0.25), 0.0, 1.0);
    float blur = blurStrength * (blurFloor + (1.0 - blurFloor) * pow(g, 1.35));
    float radius = blur * maxRadius;
    if (outside > 0.0) radius = max(radius, 0.35 * maxRadius);
    float lod = clamp(log2(max(radius, 1.0)), 0.0, maxLevel);
    vec3 colour = vec3(0);
    if (radius < 0.75) {
      colour = textureLod(picture, tc, 0.0).rgb;
    } else {
      vec2 texel = 1.0 / (paddedSize * pixelScale);
      vec2 stride = texel * radius * 0.45;
      float w[3] = float[3](1.0, 2.0, 1.0);
      for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        colour += textureLod(picture, tc + vec2(float(x), float(y)) * stride, lod).rgb * w[x+1] * w[y+1] / 16.0;
      }
    }
    float glowReach = max(0.9 * maxRadius / pixelScale, 24.0);
    colour *= exp(-pow(outside / glowReach, 1.3)) * 0.85;
    float spread = clamp((g - dimStart) / max(1.0 - dimStart, 0.05), 0.0, 1.0);
    float dim = dimStrength * pow(spread, 1.9) * maxDim;
    colour *= pow(1.0 - dim, 1.6);
    if (sheenAmount > 0.0005) {
      float band = exp(-pow((g - sheenPos) / 0.22, 2.0));
      vec3 average = textureLod(picture, vec2(0.5), maxLevel).rgb;
      colour += sheenAmount * band * (0.55 + 0.45 * average) * (1.0 - 0.5 * dim);
    }
    colour += (hash(gl_FragCoord.xy + fract(time) * 17.0) - 0.5) * grain * (2.5 / 255.0);
    // The texture is sRGB-decoded to linear; encode back for the canvas.
    colour = pow(max(colour, 0.0), vec3(1.0 / 2.2));
    fragColor = vec4(colour, 1.0);
  }`;

  function compile(type, src) {
    const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  const program = gl.createProgram();
  gl.attachShader(program, compile(gl.VERTEX_SHADER, vs));
  gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  const u = {};
  for (const name of ['picture','toPicture','screenSize','paddedOrigin','paddedSize','canvasSize','pixelScale','maxRadius','blurStrength','blurFloor','maxDim','maxLevel','dimStart','dimStrength','visibleTop','sheenAmount','sheenPos','grain','time']) {
    u[name] = gl.getUniformLocation(program, name);
  }

  // ---- The desktop: wallpaper + lock-screen clock, on a black margin. ----
  const PADDING = 176;                 // points, same as the app
  let screen = { w: 1, h: 1 };         // the virtual screen, in points
  let padded = { w: 1, h: 1 };
  let texture = null, maxLevel = 0, textureScale = 1;

  function buildDesktop(image) {
    const dpr = Math.min(devicePixelRatio || 1, 2);
    const rect = canvas.getBoundingClientRect();
    screen = { w: Math.max(rect.width, 320), h: Math.max(rect.height, 240) };
    padded = { w: screen.w + 2 * PADDING, h: screen.h + 2 * PADDING };
    textureScale = Math.min(dpr, 2048 / padded.w, 2048 / padded.h);
    const off = document.createElement('canvas');
    off.width = Math.round(padded.w * textureScale);
    off.height = Math.round(padded.h * textureScale);
    const c = off.getContext('2d');
    c.fillStyle = '#000'; c.fillRect(0, 0, off.width, off.height);
    c.save();
    c.scale(textureScale, textureScale);
    c.translate(PADDING, PADDING);
    // Wallpaper, cover-fit.
    const s = Math.max(screen.w / image.width, screen.h / image.height);
    const w = image.width * s, h = image.height * s;
    c.drawImage(image, (screen.w - w) / 2, (screen.h - h) / 2, w, h);
    // Menu bar.
    c.fillStyle = 'rgba(0,0,0,0.18)'; c.fillRect(0, 0, screen.w, 24);
    c.fillStyle = 'rgba(255,255,255,0.92)';
    c.font = '600 12px -apple-system, system-ui, sans-serif';
    c.textBaseline = 'middle';
    const now = new Date();
    const day = now.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
    c.textAlign = 'right'; c.fillText(day + '  9:41', screen.w - 14, 12);
    c.textAlign = 'left'; c.fillText('', 14, 12);
    // Clock.
    c.textAlign = 'center';
    c.shadowColor = 'rgba(0,0,0,0.35)'; c.shadowBlur = 24;
    c.fillStyle = 'rgba(255,255,255,0.96)';
    c.font = `500 ${Math.round(Math.min(screen.h * 0.06, screen.w * 0.05))}px -apple-system, system-ui, sans-serif`;
    c.fillText(now.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }), screen.w / 2, screen.h * 0.17);
    c.font = `700 ${Math.round(Math.min(screen.h * 0.22, screen.w * 0.24))}px -apple-system, system-ui, sans-serif`;
    c.fillText('9:41', screen.w / 2, screen.h * 0.32);
    c.restore();

    if (texture) gl.deleteTexture(texture);
    texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.SRGB8_ALPHA8, gl.RGBA, gl.UNSIGNED_BYTE, off);
    gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    maxLevel = Math.floor(Math.log2(Math.max(off.width, off.height)));
    canvas.width = Math.round(screen.w * dpr);
    canvas.height = Math.round(screen.h * dpr);
    gl.viewport(0, 0, canvas.width, canvas.height);
    pixelScale = dpr;
  }
  let pixelScale = 1;

  // ---- Geometry, ported from FoldGeometry.swift. ----
  function corners(angle) {
    const W = screen.w, H = screen.h;
    const travel = Math.max(effect.startAngle - angle, 0);
    const separation = Math.min(effect.depth * travel, 84);
    const lid = angle * Math.PI / 180, pic = (angle + separation) * Math.PI / 180, start = effect.startAngle * Math.PI / 180;
    const centre = { y: H / 2 * Math.sin(start), z: H / 2 * Math.cos(start) };
    const normal = { y: -Math.cos(start), z: Math.sin(start) };
    const up = { y: Math.sin(start), z: Math.cos(start) };
    const reach = effect.eyeDistance * H, lift = effect.eyeHeight * H;
    const eye = { x: W / 2, y: centre.y + normal.y * reach + up.y * lift, z: centre.z + normal.z * reach + up.z * lift };
    const n = { y: -Math.cos(lid), z: Math.sin(lid) };
    const nDotEye = n.y * eye.y + n.z * eye.z;
    function project(px, ph) {
      const q = { x: px, y: ph * Math.sin(pic), z: ph * Math.cos(pic) };
      const d = { x: q.x - eye.x, y: q.y - eye.y, z: q.z - eye.z };
      const nDotD = n.y * d.y + n.z * d.z;
      let t = Math.abs(nDotD) < 1e-9 ? 1 : -nDotEye / nDotD;
      t = Math.max(t, 1e-3);
      const hit = { x: eye.x + t * d.x, y: eye.y + t * d.y, z: eye.z + t * d.z };
      return [hit.x, hit.y * Math.sin(lid) + hit.z * Math.cos(lid)];
    }
    return [project(0, 0), project(W, 0), project(W, H), project(0, H)];
  }
  // Heckbert square-to-quad, then the rectangle folded in. Column-major.
  function homography(W, H, c) {
    const [x0,y0] = c[0], [x1,y1] = c[1], [x2,y2] = c[2], [x3,y3] = c[3];
    const dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
    const dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
    let g = 0, h = 0;
    if (Math.abs(dx3) > 1e-10 || Math.abs(dy3) > 1e-10) {
      const det = dx1 * dy2 - dx2 * dy1;
      if (Math.abs(det) > 1e-12) { g = (dx3 * dy2 - dx2 * dy3) / det; h = (dx1 * dy3 - dx3 * dy1) / det; }
    }
    const a = x1 - x0 + g * x1, b = x3 - x0 + h * x3, cc = x0, d = y1 - y0 + g * y1, e = y3 - y0 + h * y3, f = y0;
    return [a / W, d / W, g / W,  b / H, e / H, h / H,  cc, f, 1];
  }
  function invert3(m) {
    const [a,b,c,d,e,f,g,h,i] = m;
    const A = e*i - f*h, B = -(d*i - f*g), C = d*h - e*g;
    const det = a*A + b*B + c*C;
    return [A/det, -(b*i - c*h)/det, (b*f - c*e)/det,  B/det, (a*i - c*g)/det, -(a*f - c*d)/det,  C/det, -(a*h - b*g)/det, (a*e - b*d)/det];
  }
  function apply(m, x, y) { const X = m[0]*x + m[3]*y + m[6], Y = m[1]*x + m[4]*y + m[7], Z = m[2]*x + m[5]*y + m[8]; return [X/Z, Y/Z]; }
  const smooth = t => { t = Math.min(Math.max(t, 0), 1); return t * t * (3 - 2 * t); };

  // ---- Frame. ----
  let target = OPEN, shown = OPEN, velocity = 0, last = performance.now();
  let raf = 0, dirty = true;
  function frame(now) {
    raf = 0;
    const dt = Math.min(Math.max((now - last) / 1000, 1 / 240), 1 / 20); last = now;
    if (reduced) { shown = target; } else {
      const k = 14; const acc = k * k * (target - shown) - 2 * k * velocity;
      velocity += acc * dt; shown += velocity * dt;
    }
    draw(shown, now / 1000);
    if (Math.abs(shown - target) > 0.01 || Math.abs(velocity) > 0.1 || dirty) { dirty = false; raf = requestAnimationFrame(frame); }
  }
  function schedule() { if (!raf) { last = performance.now(); raf = requestAnimationFrame(frame); } }

  function draw(angle, time) {
    if (!texture) return;
    const W = screen.w, H = screen.h;
    const progress = smooth((effect.startAngle - angle) / effect.span);
    const c = corners(angle);
    const inv = invert3(homography(W, H, c));
    const top = apply(inv, W / 2, H);
    const visibleTop = Math.min(Math.max(top[1] / H, 0.2), 1);
    const envelope = 4 * progress * (1 - progress);
    gl.uniformMatrix3fv(u.toPicture, false, inv);
    gl.uniform2f(u.screenSize, W, H);
    gl.uniform2f(u.paddedOrigin, -PADDING, -PADDING);
    gl.uniform2f(u.paddedSize, padded.w, padded.h);
    gl.uniform2f(u.canvasSize, canvas.width, canvas.height);
    gl.uniform1f(u.pixelScale, pixelScale);
    gl.uniform1f(u.maxRadius, effect.blurRadius * textureScale);
    gl.uniform1f(u.blurStrength, Math.pow(progress, 1.45));
    gl.uniform1f(u.blurFloor, effect.blurFloor);
    gl.uniform1f(u.maxDim, effect.dimming);
    gl.uniform1f(u.maxLevel, maxLevel);
    gl.uniform1f(u.dimStart, effect.dimStart);
    gl.uniform1f(u.dimStrength, Math.pow(progress, 0.9));
    gl.uniform1f(u.visibleTop, visibleTop);
    gl.uniform1f(u.sheenAmount, effect.sheen * 0.16 * Math.pow(envelope, 1.5));
    gl.uniform1f(u.sheenPos, 0.15 + 0.75 * progress);
    gl.uniform1f(u.grain, effect.grain);
    gl.uniform1f(u.time, time % 1000);
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, texture); gl.uniform1i(u.picture, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    angleLabel.textContent = Math.round(angle);
    const a = Math.min(Math.max(angle, 5), 135) * Math.PI / 180;
    lidLine.setAttribute('d', `M4.5 12.5l${(11 * Math.cos(a)).toFixed(2)} ${(-11 * Math.sin(a)).toFixed(2)}`);
  }

  // ---- Input: scroll through the hero folds the lid; the slider does too. ----
  let usingSlider = false;
  function fromScroll() {
    if (usingSlider) return;
    const rect = hero.getBoundingClientRect();
    const travel = rect.height - innerHeight;
    const t = Math.min(Math.max(-rect.top / Math.max(travel, 1), 0), 1);
    target = OPEN + (SHUT - OPEN) * t;
    scrub.value = Math.round(t * 1000);
    hint.textContent = t < 0.02 ? 'Scroll to close the lid' : (t > 0.98 ? 'Scroll up to open it' : 'Lid closing');
    schedule();
  }
  scrub.addEventListener('input', () => {
    usingSlider = true;
    const t = scrub.value / 1000;
    target = OPEN + (SHUT - OPEN) * t;
    hint.textContent = 'Drag to fold';
    schedule();
  });
  scrub.addEventListener('change', () => { setTimeout(() => { usingSlider = false; }, 1500); });
  addEventListener('scroll', fromScroll, { passive: true });

  // ---- Boot. ----
  const image = new Image();
  image.src = 'assets/wallpaper-dunes.jpg';
  image.onload = () => {
    buildDesktop(image);
    dirty = true; fromScroll(); schedule();
    let resizeTimer = 0;
    addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { buildDesktop(image); dirty = true; schedule(); }, 150); });
  };
})();
