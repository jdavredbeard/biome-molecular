#define GLFW_INCLUDE_NONE
#import <GLFW/glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#import <GLFW/glfw3native.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#include "metal_layer.h"

void *biome_attach_metal_layer(void *glfw_window) {
    NSWindow *ns_window = glfwGetCocoaWindow((GLFWwindow *)glfw_window);
    NSView *view = [ns_window contentView];
    CAMetalLayer *layer = [CAMetalLayer layer];
    [view setWantsLayer:YES];
    [view setLayer:layer];
    return (__bridge void *)layer;
}

// 1 if any part of the window is currently visible on screen, 0 if fully
// occluded / hidden / minimized. Used to pause rendering so we never present
// into a hidden CAMetalLayer (which exhausts the drawable pool and hangs).
int biome_window_is_visible(void *glfw_window) {
    NSWindow *ns_window = glfwGetCocoaWindow((GLFWwindow *)glfw_window);
    return (([ns_window occlusionState] & NSWindowOcclusionStateVisible) != 0) ? 1 : 0;
}
