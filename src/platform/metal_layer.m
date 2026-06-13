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
