#ifndef PARHELION_CSDL3_SHIM_H
#define PARHELION_CSDL3_SHIM_H

#include <SDL3/SDL.h>

// SDL defines these flags with function-like macros, which Swift cannot
// import. Constants give them names Swift can see.
static const SDL_InitFlags parhelion_init_video = SDL_INIT_VIDEO;
static const SDL_WindowFlags parhelion_window_high_pixel_density = SDL_WINDOW_HIGH_PIXEL_DENSITY;
static const SDL_WindowFlags parhelion_window_transparent = SDL_WINDOW_TRANSPARENT;
static const Uint8 parhelion_button_left = SDL_BUTTON_LEFT;
static const SDL_MouseButtonFlags parhelion_button_left_mask = SDL_BUTTON_LMASK;
static const SDL_Keymod parhelion_keymod_shift = SDL_KMOD_SHIFT;

// Line-buffers standard output, so progress shows up immediately even when
// output goes to a pipe or a file. C's `stdout` is a global variable, which
// Swift 6 does not allow code to touch directly.
#include <stdio.h>
static inline void parhelion_line_buffer_standard_output(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
}

#endif
