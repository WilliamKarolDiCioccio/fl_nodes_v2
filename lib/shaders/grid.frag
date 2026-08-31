#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// The whole background — fill and grid — in a single draw call. The CPU
// alternative emits one drawLine per visible line, which is what makes a
// zoomed-out canvas expensive: the line count grows as the scene shrinks.
//
// Everything is in screen pixels, so lines stay hairline-thin at any zoom
// rather than thickening with the scene.

// Screen-space position of the scene origin.
uniform vec2 uOrigin;
// Minor line spacing, in screen pixels.
uniform float uSpacing;
// Every n-th line away from the origin is drawn as a major line.
uniform float uMajorEvery;
// Line thickness, in screen pixels.
uniform float uLineWidth;
// Premultiplied colours.
uniform vec4 uBackground;
uniform vec4 uMinorColor;
uniform vec4 uMajorColor;
// Fades minor lines out as they crowd together, instead of popping off.
uniform float uMinorOpacity;

out vec4 fragColor;

// Antialiased coverage of a line of uLineWidth centred `dist` pixels away.
float lineCoverage(float dist) {
    float halfWidth = uLineWidth * 0.5;
    return 1.0 - smoothstep(halfWidth - 0.5, halfWidth + 0.5, dist);
}

// 1.0 when the line `index` steps from the origin is a major one.
float majorness(float index) {
    float m = mod(index, uMajorEvery);
    return 1.0 - step(0.5, min(m, uMajorEvery - m));
}

// Premultiplied source-over.
vec4 over(vec4 src, float coverage, vec4 dst) {
    return src * coverage + dst * (1.0 - src.a * coverage);
}

void main() {
    vec2 p = FlutterFragCoord().xy - uOrigin;

    // Distance to the nearest grid line on each axis, and whether that line
    // is major. Rounding gives the nearest line in one step, with no loop.
    vec2 index = round(p / uSpacing);
    vec2 dist = abs(p - index * uSpacing);

    vec2 coverage = vec2(lineCoverage(dist.x), lineCoverage(dist.y));
    vec2 major = vec2(majorness(index.x), majorness(index.y));

    float majorCoverage = max(coverage.x * major.x, coverage.y * major.y);
    float minorCoverage =
        max(coverage.x * (1.0 - major.x), coverage.y * (1.0 - major.y)) *
        uMinorOpacity;

    vec4 color = over(uMinorColor, minorCoverage, uBackground);
    fragColor = over(uMajorColor, majorCoverage, color);
}
