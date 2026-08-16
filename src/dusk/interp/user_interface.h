#pragma once

#include "dusk/game_clock.h"

#include "JSystem/J2DGraph/J2DAnimation.h"
#include "SSystem/SComponent/c_lib.h"

#include <dolphin/types.h>

#include <algorithm>
#include <cmath>

namespace dusk::vdt {

inline void advance_looping_frame(f32& frame, f32 speed, f32 max) {
    if (max <= 0.0f) {
        return;
    }
    frame += speed * game_clock::original_frames();
    if (frame >= max) {
        frame = fmodf(frame, max);
    }
}

inline void advance_toward_frame(f32& frame, f32 target, f32 speed) {
    if (frame == target) {
        return;
    }
    const f32 step = speed * game_clock::original_frames();
    frame = frame < target ? std::min(frame + step, target) : std::max(frame - step, target);
}

template <typename Animation>
bool request_animation(Animation& animation, f32& frame, s16 time,
                       decltype(animation.start) from, decltype(animation.end) to, u8 curve) {
    if (frame < time) {
        animation = {true, time, curve, from, to};
        return false;
    }
    animation.active = false;
    frame = time;
    return true;
}

template <typename Animation, typename Pane, typename Apply>
void present_animation(Animation& animation, f32& frame, Pane& pane, Apply apply) {
    if (!animation.active) {
        return;
    }
    advance_toward_frame(frame, animation.duration, 1.0f);
    apply(pane.rateCalc(animation.duration, frame, animation.curve));
    if (frame >= animation.duration) {
        animation.active = false;
    }
}

inline void present_looping(f32& frame, J2DAnmBase* anm, f32 speed) {
    if (anm == nullptr) {
        return;
    }
    advance_looping_frame(frame, speed, anm->getFrameMax());
    anm->setFrame(frame);
}

inline void present_addCalc(f32* value, f32 target, f32 scale, f32 maxStep, f32 minStep) {
    const f32 frames = game_clock::original_frames();
    if (*value == target || frames <= 0.0f) {
        return;
    }
    const f32 timedScale = frames == 1.0f ? scale : 1.0f - std::pow(1.0f - scale, frames);
    cLib_addCalc(value, target, timedScale, maxStep * frames, minStep * frames);
}

inline void present_addCalc2(f32* value, f32 target, f32 scale, f32 maxStep, f32 snap) {
    const f32 frames = game_clock::original_frames();
    if (*value == target || frames <= 0.0f) {
        return;
    }
    const f32 timedScale = frames == 1.0f ? scale : 1.0f - std::pow(1.0f - scale, frames);
    cLib_addCalc2(value, target, timedScale, maxStep * frames);
    if (fabsf(*value - target) < snap) {
        *value = target;
    }
}

inline bool present_chase(f32* value, f32 target, f32 scale, f32 maxStep, f32 snap) {
    if (*value == target) {
        return false;
    }
    present_addCalc2(value, target, scale, maxStep, snap);
    return true;
}

}  // namespace dusk::vdt
