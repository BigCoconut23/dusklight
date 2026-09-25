#pragma once

// iOS-only bridge from Apple's Game Controller framework to an SDL virtual gamepad.
// Call on the game loop thread, after Aurora has initialized SDL input.
void DuskIOSControllerBridgeUpdate(bool externalScene);
void DuskIOSControllerBridgeAssignPortOne();
int DuskIOSControllerBridgeCount();
