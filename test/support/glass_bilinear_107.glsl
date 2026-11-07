// Frozen sampling formula from the 1.0.7 renderer, used only for pixel tests.
vec4 textureBilinear(vec2 uv, vec2 size, vec2 invSize) {
    vec2 px = uv * size - 0.5;
    vec2 f = fract(px);
    vec2 p0 = floor(px);
    vec4 c0 = texture(uBackgroundTexture, (p0 + 0.5) * invSize);
    vec4 c1 = texture(uBackgroundTexture, (p0 + vec2(1.5, 0.5)) * invSize);
    vec4 c2 = texture(uBackgroundTexture, (p0 + vec2(0.5, 1.5)) * invSize);
    vec4 c3 = texture(uBackgroundTexture, (p0 + 1.5) * invSize);
    vec4 bg = mix(mix(c0, c1, f.x), mix(c2, c3, f.x), f.y);
    if (uBackgroundFallback.a > 0.0) {
        bg.rgb += uBackgroundFallback.rgb * uBackgroundFallback.a * (1.0 - bg.a);
        bg.a += uBackgroundFallback.a * (1.0 - bg.a);
    }
    return bg;
}
