// vibed based on https://www.youtube.com/watch?v=WthCMZ1nm2Q
// Halloween Lightning Sparks - Lightning bolt trail with spark particles (green)

float ease(float x) {
    return pow(1.0 - x, 6.0);
}

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2d(vec2 p) {
    p = vec2(
        dot(p, vec2(127.1, 311.7)),
        dot(p, vec2(269.5, 183.3))
    );
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

vec2 fade(vec2 t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = fade(f);

    return mix(
        mix(dot(hash2d(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
            dot(hash2d(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
        mix(dot(hash2d(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
            dot(hash2d(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
        u.y
    );
}

float fbm(vec2 uv) {
    float value = 0.0;
    float amplitude = 0.5;
    float freq = 2.0;

    for (int i = 0; i < 6; i++) {
        value += amplitude * noise(uv);
        uv *= freq;
        amplitude *= 0.5;
    }

    return value;
}

float lightningDist(vec2 uv, vec2 p0, vec2 p1, float time) {
    vec2 dir = p1 - p0;
    float len = length(dir);
    vec2 forward = normalize(dir);
    vec2 side = vec2(-forward.y, forward.x);

    float t = dot(uv - p0, forward) / len;
    t = clamp(t, 0.0, 1.0);

    vec2 point = mix(p0, p1, t);

    float envelope = sin(t * 3.14159265);
    float n = fbm(vec2(t * 8.0, time * 1.5));

    point += side * n * 0.25 * envelope;

    return length(uv - point);
}

vec2 normalizeCoord(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float blend(float t) {
    float sqr = t * t;
    return sqr / (2.0 * (sqr - t) + 1.0);
}

float determineStartVertexFactor(vec2 a, vec2 b) {
    float c1 = step(b.x, a.x) * step(a.y, b.y);
    float c2 = step(a.x, b.x) * step(b.y, a.y);
    return 1.0 - max(c1, c2);
}

vec2 getRectangleCenter(vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.0), rectangle.y - (rectangle.w / 2.0));
}

const vec4 TRAIL_COLOR = vec4(0.2, 1.0, 0.2, 1.0); // halloween green
const vec4 TRAIL_COLOR_ACCENT = vec4(1.0, 1.0, 1.0, 1.0);

const float DURATION = 0.5;
const float SPARK_DURATION = 0.25;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
#if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
#endif

    vec2 vu = normalizeCoord(fragCoord, 1.0);

    vec4 currentCursor = vec4(normalizeCoord(iCurrentCursor.xy, 1.0), normalizeCoord(iCurrentCursor.zw, 0.0));
    vec4 previousCursor = vec4(normalizeCoord(iPreviousCursor.xy, 1.0), normalizeCoord(iPreviousCursor.zw, 0.0));

    float vertexFactor = determineStartVertexFactor(currentCursor.xy, previousCursor.xy);
    float invVertex = 1.0 - vertexFactor;

    vec2 v0 = vec2(currentCursor.x + currentCursor.z * vertexFactor, currentCursor.y - currentCursor.w);
    vec2 v1 = vec2(currentCursor.x + currentCursor.z * invVertex, currentCursor.y);
    vec2 v2 = vec2(previousCursor.x + currentCursor.z * invVertex, previousCursor.y);
    vec2 v3 = vec2(previousCursor.x + currentCursor.z * vertexFactor, previousCursor.y - previousCursor.w);

    vec4 newColor = fragColor;

    float progress = blend(clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0));
    float easedProgress = ease(progress);

    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerCP = getRectangleCenter(previousCursor);

    float lineLength = distance(centerCC, centerCP);

    // Lightning bolt trail
    if (lineLength > 1.5 * max(currentCursor.z, currentCursor.w)) {
        float d = lightningDist(vu, centerCP, centerCC, iTime);

        float core = smoothstep(0.002, -0.002, d);
        float glow = smoothstep(0.025, -0.005, d);

        float flicker = 0.7 + 0.3 * sin(iTime * 40.0 + noise(vu * 50.0) * 10.0);

        float lightningGlow = 0.02 / (d + 0.001);
        lightningGlow *= sin(progress * 3.14159265);

        vec4 electric = TRAIL_COLOR_ACCENT * core * flicker + TRAIL_COLOR * glow + TRAIL_COLOR * lightningGlow * 0.5;

        float alphaModifier = distance(vu.xy, centerCC) / (lineLength * easedProgress);
        alphaModifier = clamp(alphaModifier, 0.0, 1.0);

        newColor = mix(newColor, electric, glow + lightningGlow * 0.3);
        newColor = mix(fragColor, newColor, 1.0 - alphaModifier);
    }

    // Spark particles
    float jumpDist = distance(centerCC, centerCP);
    float sparkTime = (iTime - iTimeCursorChange) / 0.28;

    if (jumpDist > 0.25 && sparkTime < 1.0) {
        vec2 sparkCenter = centerCC;
        float sparks = 0.0;

        const int SPARK_COUNT = 18;

        for (int i = 0; i < SPARK_COUNT; i++) {
            float fi = float(i);
            float seed = hash(fi + iTimeCursorChange * 17.0);
            float angle = seed * 6.28318;
            vec2 dir = vec2(cos(angle), sin(angle));

            float upwardBias = mix(0.6, 1.6, step(0.0, dir.y));
            float speed = (0.10 + hash(fi * 3.1) * 0.18) * upwardBias;
            float gravity = -0.35;

            vec2 pos = sparkCenter + dir * sparkTime * speed;
            pos.y += gravity * sparkTime * sparkTime;

            float d = length(vu - pos);
            float sparkHead = smoothstep(0.006, 0.0, d);

            vec2 prev = sparkCenter + dir * (sparkTime - 0.04) * speed;
            prev.y += gravity * (sparkTime - 0.04) * (sparkTime - 0.04);

            vec2 pa = vu - prev;
            vec2 ba = pos - prev;
            float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float lineDist = length(pa - ba * h);
            float sparkTrail = smoothstep(0.0035, 0.0, lineDist) * 0.9;

            sparks += sparkHead + sparkTrail;
        }

        sparks *= (1.0 - sparkTime);

        vec3 sparkColor = vec3(1.6, 0.7, 0.2);
        newColor.rgb += sparkColor * sparks;
    }

    fragColor = newColor;
}
