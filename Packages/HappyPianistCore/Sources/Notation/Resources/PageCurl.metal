#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] half4 scorePageCurl(float2 position, SwiftUI::Layer layer,
                                    float2 size, float2 origin, float gutter,
                                    float rotation, float curvature, float cameraDistance, float direction) {
    float pageWidth = (size.x - gutter) / 2;
    float sheetWidth = pageWidth + gutter / 2;
    float horizontal = (position.x - origin.x - size.x / 2) * direction;
    float distance;
    float angle;
    float depth;
    bool backFace;
    if (curvature < 0.0001) {
        backFace = rotation > M_PI_F / 2;
        distance = horizontal * cos(rotation);
        angle = rotation;
        depth = 0;
    } else {
        float radius = sheetWidth / curvature;
        float slope = horizontal / cameraDistance;
        float root = (sin(rotation) + horizontal / radius - slope * cos(rotation)) / sqrt(1 + slope * slope);
        if (abs(root) > 1) { return half4(0); }
        float inverse = asin(root);
        float tilt = atan(slope);
        float backAngle = tilt + M_PI_F - inverse;
        float lower = rotation + curvature * gutter / 2 / sheetWidth;
        float upper = rotation + curvature;
        backFace = backAngle >= lower && backAngle <= upper;
        angle = backFace ? backAngle : tilt + inverse;
        if (angle < lower || angle > upper) { return half4(0); }
        distance = (angle - rotation) * radius;
        depth = radius * (cos(rotation) - cos(angle));
    }
    if (distance < gutter / 2 || distance > sheetWidth) { return half4(0); }
    float scale = cameraDistance / (cameraDistance - depth);
    float vertical = size.y / 2 + (position.y - origin.y - size.y / 2) / scale;
    if (vertical < 0 || vertical > size.y) { return half4(0); }
    bool reversed = (direction > 0) == backFace;
    float sourceX = reversed ? sheetWidth - distance : distance - gutter / 2;
    float pageOrigin = ((direction > 0) != backFace) ? pageWidth + gutter : 0;
    half4 color = layer.sample(origin + float2(pageOrigin + sourceX, vertical));
    float light = 0.74 + 0.26 * sqrt(abs(cos(angle))) + 0.04 * pow(max(0.0f, sin(angle)), 12.0f);
    color.rgb *= half(light);
    return color;
}
