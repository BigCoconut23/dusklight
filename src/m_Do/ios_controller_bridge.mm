#include "m_Do/ios_controller_bridge.h"

#import <GameController/GameController.h>
#include <SDL3/SDL.h>
// The game SDK uses BOOL for an integer; Apple's headers use BOOL for a bool.
// Rename only the game SDK typedef while including its C++ declarations.
#define BOOL DuskGameBool
#include <dolphin/pad.h>
#undef BOOL

#include <algorithm>

namespace {
SDL_JoystickID virtualID = 0;
SDL_Joystick* virtualJoystick = nullptr;
GCController* selectedController = nil;
int lastAppleCount = -1;
int lastPhysicalCount = -1;
bool wasExternalScene = false;
bool discoveryStarted = false;

Sint16 stick(float value) {
    return static_cast<Sint16>(std::clamp(value, -1.0f, 1.0f) * (value < 0.0f ? 32768.0f : 32767.0f));
}

Sint16 trigger(float value) {
    return static_cast<Sint16>(std::clamp(value, 0.0f, 1.0f) * 65535.0f - 32768.0f);
}

void button(SDL_GamepadButton which, GCControllerButtonInput* input) {
    SDL_SetJoystickVirtualButton(virtualJoystick, which, input != nil && input.isPressed);
}

void detach_virtual() {
    if (virtualJoystick != nullptr) {
        SDL_CloseJoystick(virtualJoystick);
        virtualJoystick = nullptr;
    }
    if (virtualID != 0) {
        SDL_Log("iOS controller bridge: removing virtual gamepad %u", virtualID);
        SDL_DetachVirtualJoystick(virtualID);
        virtualID = 0;
    }
    selectedController = nil;
}
} // namespace

int DuskIOSControllerBridgeCount() {
    return static_cast<int>(GCController.controllers.count);
}

void DuskIOSControllerBridgeUpdate(bool externalScene) {
    const bool firstExternalFrame = externalScene && !wasExternalScene;
    wasExternalScene = externalScene;
    NSArray<GCController*>* connected = GCController.controllers;
    int physicalCount = 0;
    int sdlCount = 0;
    SDL_JoystickID* gamepads = SDL_GetGamepads(&sdlCount);
    for (int i = 0; i < sdlCount; ++i) {
        physicalCount += gamepads[i] != virtualID;
    }
    SDL_free(gamepads);

    if (externalScene &&
        (firstExternalFrame || lastAppleCount != static_cast<int>(connected.count) || lastPhysicalCount != physicalCount)) {
        SDL_Log("iOS controller bridge: Apple controllers %lu, physical SDL gamepads %d, virtual gamepad %u, Port 1 index %d",
                static_cast<unsigned long>(connected.count), physicalCount, virtualID, PADGetIndexForPort(PAD_CHAN0));
        for (GCController* controller in connected) {
            SDL_Log("iOS controller bridge: Apple controller '%s', extended gamepad %d, player %ld",
                    controller.vendorName.UTF8String ?: "unknown", controller.extendedGamepad != nil,
                    static_cast<long>(controller.playerIndex));
        }
    }
    lastAppleCount = static_cast<int>(connected.count);
    lastPhysicalCount = physicalCount;

    if (!externalScene || physicalCount != 0) {
        detach_virtual();
        return;
    }

    // If the framework has also lost the controller, ask it to search once.
    if (connected.count == 0 && !discoveryStarted) {
        discoveryStarted = true;
        SDL_Log("iOS controller bridge: starting Game Controller discovery");
        [GCController startWirelessControllerDiscoveryWithCompletionHandler:^{
            SDL_Log("iOS controller bridge: discovery finished; Apple controllers %lu",
                    static_cast<unsigned long>(GCController.controllers.count));
        }];
    }

    GCController* candidate = nil;
    for (GCController* controller in connected) {
        if (controller.extendedGamepad == nil) {
            continue;
        }
        if (candidate != nil && candidate != controller) {
            // Multiple controllers: only retain a previously selected, still connected device.
            if ([connected containsObject:selectedController]) {
                candidate = selectedController;
            } else {
                SDL_Log("iOS controller bridge: multiple Apple controllers; waiting for an unambiguous selection");
                detach_virtual();
                return;
            }
            break;
        }
        candidate = controller;
    }
    if (candidate == nil) {
        detach_virtual();
        return;
    }
    if (selectedController != nil && candidate != selectedController) {
        detach_virtual();
    }

    if (virtualID == 0) {
        SDL_VirtualJoystickDesc desc{};
        SDL_INIT_INTERFACE(&desc);
        desc.type = SDL_JOYSTICK_TYPE_GAMEPAD;
        desc.nbuttons = SDL_GAMEPAD_BUTTON_COUNT;
        desc.naxes = SDL_GAMEPAD_AXIS_COUNT;
        desc.button_mask = (1u << SDL_GAMEPAD_BUTTON_COUNT) - 1u;
        desc.axis_mask = (1u << SDL_GAMEPAD_AXIS_COUNT) - 1u;
        desc.name = "iOS Game Controller bridge";
        virtualID = SDL_AttachVirtualJoystick(&desc);
        if (virtualID == 0) {
            SDL_Log("iOS controller bridge: virtual gamepad attach failed: %s", SDL_GetError());
            return;
        }
        virtualJoystick = SDL_OpenJoystick(virtualID);
        if (virtualJoystick == nullptr) {
            SDL_Log("iOS controller bridge: virtual gamepad open failed: %s", SDL_GetError());
            detach_virtual();
            return;
        }
        SDL_Log("iOS controller bridge: using Apple controller '%s' as SDL virtual gamepad %u",
                candidate.vendorName.UTF8String ?: "unknown", virtualID);
    }
    selectedController = candidate;
    GCExtendedGamepad* pad = candidate.extendedGamepad;

    button(SDL_GAMEPAD_BUTTON_SOUTH, pad.buttonA);
    button(SDL_GAMEPAD_BUTTON_EAST, pad.buttonB);
    button(SDL_GAMEPAD_BUTTON_WEST, pad.buttonX);
    button(SDL_GAMEPAD_BUTTON_NORTH, pad.buttonY);
    button(SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, pad.leftShoulder);
    button(SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, pad.rightShoulder);
    button(SDL_GAMEPAD_BUTTON_DPAD_UP, pad.dpad.up);
    button(SDL_GAMEPAD_BUTTON_DPAD_DOWN, pad.dpad.down);
    button(SDL_GAMEPAD_BUTTON_DPAD_LEFT, pad.dpad.left);
    button(SDL_GAMEPAD_BUTTON_DPAD_RIGHT, pad.dpad.right);
    button(SDL_GAMEPAD_BUTTON_START, pad.buttonMenu);
    button(SDL_GAMEPAD_BUTTON_BACK, pad.buttonOptions);
    button(SDL_GAMEPAD_BUTTON_LEFT_STICK, pad.leftThumbstickButton);
    button(SDL_GAMEPAD_BUTTON_RIGHT_STICK, pad.rightThumbstickButton);

    SDL_SetJoystickVirtualAxis(virtualJoystick, SDL_GAMEPAD_AXIS_LEFTX, stick(pad.leftThumbstick.xAxis.value));
    SDL_SetJoystickVirtualAxis(virtualJoystick, SDL_GAMEPAD_AXIS_LEFTY, stick(-pad.leftThumbstick.yAxis.value));
    SDL_SetJoystickVirtualAxis(virtualJoystick, SDL_GAMEPAD_AXIS_RIGHTX, stick(pad.rightThumbstick.xAxis.value));
    SDL_SetJoystickVirtualAxis(virtualJoystick, SDL_GAMEPAD_AXIS_RIGHTY, stick(-pad.rightThumbstick.yAxis.value));
    SDL_SetJoystickVirtualAxis(virtualJoystick, SDL_GAMEPAD_AXIS_LEFT_TRIGGER, trigger(pad.leftTrigger.value));
    SDL_SetJoystickVirtualAxis(virtualJoystick, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER, trigger(pad.rightTrigger.value));
    SDL_UpdateJoysticks();
}

void DuskIOSControllerBridgeAssignPortOne() {
    if (virtualID == 0 || PADGetIndexForPort(PAD_CHAN0) >= 0) {
        return;
    }
    // Avoid PADSetPortForIndex: that would save the virtual device's GUID over
    // the real controller preference stored before the display was connected.
    for (u32 index = 0; index < PADCount(); ++index) {
        SDL_Gamepad* pad = PADGetSDLGamepadForIndex(index);
        if (pad != nullptr && SDL_GetGamepadID(pad) == virtualID) {
            SDL_SetGamepadPlayerIndex(pad, PAD_CHAN0);
            SDL_Log("iOS controller bridge: assigned virtual gamepad to Port 1 (index %u)", index);
            return;
        }
    }
}
