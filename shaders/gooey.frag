precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform float uProgress;
uniform vec2 uButtonPos;
uniform vec2 uCardPos;
uniform float uButtonRadius;
uniform float uCardWidth;
uniform float uCardHeight;
uniform float uCardRadius;
uniform float uBlur;
uniform vec4 uButtonColor;  // 按钮颜色
uniform vec4 uCardColor;    // 卡片颜色

// SDF for circle
float sdCircle(vec2 p, float r) {
    return length(p) - r;
}

// SDF for rounded rectangle
float sdRoundedRect(vec2 p, vec2 size, float r) {
    vec2 q = abs(p) - size + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Smooth minimum - 增强版本产生更强的粘连效果
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    
    // 按钮距离场
    float distButton = sdCircle(fragCoord - uButtonPos, uButtonRadius);
    
    // 卡片距离场
    vec2 cardHalfSize = vec2(uCardWidth, uCardHeight) * 0.5;
    float distCard = sdRoundedRect(fragCoord - uCardPos, cardHalfSize, uCardRadius);
    
    // 使用smooth minimum合并，产生粘连效果
    // uBlur控制粘连强度，值越大粘连越明显
    float dist = smin(distButton, distCard, uBlur);
    
    // 抗锯齿：使用0.5像素的过渡范围，保持边缘清晰
    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    
    // 消除白色光圈：对alpha进行非线性增强，但保留抗锯齿
    // 使用平方函数增强对比度，同时保持边缘平滑
    alpha = alpha * alpha;
    
    // 硬截断：只保留真正不透明的像素，消除半透明边缘
    if (alpha < 0.3) {
        fragColor = vec4(0.0);
        return;
    }
    
    // 根据到按钮和卡片的距离混合颜色
    float buttonWeight = smoothstep(uButtonRadius + 30.0, uButtonRadius - 30.0, distButton);
    vec4 color = mix(uCardColor, uButtonColor, buttonWeight);
    
    fragColor = vec4(color.rgb, alpha * color.a);
}
