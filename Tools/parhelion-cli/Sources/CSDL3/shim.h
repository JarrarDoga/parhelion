#ifndef PARHELION_CSDL3_SHIM_H
#define PARHELION_CSDL3_SHIM_H

#include <SDL3/SDL.h>

// SDL defines these flags with function-like macros, which Swift cannot
// import. Constants give them names Swift can see.
static const SDL_InitFlags parhelion_init_video = SDL_INIT_VIDEO;
static const SDL_WindowFlags parhelion_window_high_pixel_density = SDL_WINDOW_HIGH_PIXEL_DENSITY;
static const Uint8 parhelion_button_left = SDL_BUTTON_LEFT;
static const SDL_MouseButtonFlags parhelion_button_left_mask = SDL_BUTTON_LMASK;

#endif
