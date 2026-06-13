#pragma once
// Attach a CAMetalLayer to the Cocoa window backing the given GLFWwindow* and
// return it (as void*). Implemented in metal_layer.m so all Objective-C / GLFW
// native interop stays out of the Zig @cImport.
void *biome_attach_metal_layer(void *glfw_window);

// 1 if the window is at least partially visible on screen, 0 if occluded.
int biome_window_is_visible(void *glfw_window);
