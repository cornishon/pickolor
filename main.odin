// # Resources:
// - https://keithp.com/blogs/Cursor_tracking/
// 
package color_picker

import rl "vendor:raylib"
import X "vendor:x11/xlib"
import "core:fmt"
import "core:math/bits"
import "core:os"

PIXELS_AROUND :: 8
PIXEL_SIZE    :: 12
PICKER_CELLS  :: 2*PIXELS_AROUND + 1
PICKER_SIZE   :: PICKER_CELLS*PIXEL_SIZE
FONT_SIZE     :: PICKER_SIZE/6.0
FONT_SPACING  :: 0.1*FONT_SIZE

main :: proc() {
	rl.SetConfigFlags({.WINDOW_TOPMOST, .VSYNC_HINT, .WINDOW_UNDECORATED})
	rl.InitWindow(PICKER_SIZE, PICKER_SIZE, "Press SPACE to pick")
	defer rl.CloseWindow()

	font := rl.GetFontDefault()

	dpy := X.OpenDisplay("")

	if dpy == nil {
		fmt.eprintln("Failed to open display.")
		os.exit(1)
	}

	xi_opcode, event, error: i32
	if !X.QueryExtension(dpy, "XInputExtension", &xi_opcode, &event, &error) {
		fmt.eprintf("X Input extension not available.\n")
		os.exit(1)
	}

	if !has_xi2(dpy) {
		os.exit(1)
	}

	root_window := X.DefaultRootWindow(dpy)

	/* select for XI2 events */
	select_events(dpy, root_window)

	mouse_x, mouse_y: i32
	mouse_window: X.Window
	X.QueryPointer(dpy, root_window, &{}, &mouse_window, &mouse_x, &mouse_y, &{}, &{}, &{})

	// "#rrggbb\0"
	color_string_buf: [8]u8
	color_string: cstring
	color_string_timer: f32

	event_loop: for !rl.WindowShouldClose() {
		adjust_window(mouse_x, mouse_y)

		for ev: X.XEvent; X.EventsQueued(dpy, .QueuedAlready) != 0; /**/ {
			X.NextEvent(dpy, &ev)
			cookie := &ev.xcookie
			if cookie.type != .GenericEvent || cookie.extension != xi_opcode || !X.GetEventData(dpy, cookie) {
				continue
			}
			if cast(X.XIEventType)cookie.evtype == .RawMotion {
				// raw := (cast(^X.XIRawEvent)cookie.data)^
				X.QueryPointer(dpy, root_window, &{}, &{}, &mouse_x, &mouse_y, &{}, &{}, &{})
			}
		}

		if rl.IsKeyPressed(.SPACE) {
			img := X.GetImage(dpy, root_window, mouse_x, mouse_y, 1, 1, ~uint(0), .ZPixmap)
			defer X.DestroyImage(img)
			color := ximage_color(img, 0, 0)
			fmt.bprintf(color_string_buf[:], "#{:2x}{:2x}{:2x}", color.r, color.g, color.b)
			assert(color_string_buf[len(color_string_buf)-1] == 0)
			color_string = cstring(&color_string_buf[0])
			color_string_timer = 1.0
			rl.SetClipboardText(color_string)
			fmt.println(color_string)
		}
			
		img_x := clamp(mouse_x - PIXELS_AROUND - 1, 0, rl.GetMonitorWidth(0) - PICKER_CELLS - 1)
		img_y := clamp(mouse_y - PIXELS_AROUND - 1, 0, rl.GetMonitorHeight(0) - PICKER_CELLS - 1)
		img := X.GetImage(dpy, root_window, img_x, img_y, PICKER_CELLS, PICKER_CELLS, ~uint(0), .ZPixmap)
		defer X.DestroyImage(img)

		{
			rl.BeginDrawing(); defer rl.EndDrawing()
			rl.ClearBackground(rl.BLACK)

			for y in i32(0)..<PICKER_CELLS {
				for x in i32(0)..<PICKER_CELLS {
					color := ximage_color(img, x, y)
					rl.DrawRectangle(PIXEL_SIZE*x, PIXEL_SIZE*y, PIXEL_SIZE, PIXEL_SIZE, color)
				}
			}

			c :: PICKER_CELLS/2
			outline_color := rl.BLACK if rl.ColorToHSV(ximage_color(img, c, c))[2] > 0.5 else rl.LIGHTGRAY
			rect := rl.Rectangle{PIXEL_SIZE*c - 1, PIXEL_SIZE*c - 1, PIXEL_SIZE + 2, PIXEL_SIZE + 2}
			rl.DrawRectangleLinesEx(rect, 2, outline_color)

			if color_string_timer > 0 {
				color_string_timer -= rl.GetFrameTime()
				text_size := rl.MeasureTextEx(font, color_string, FONT_SIZE, FONT_SPACING)
				text_position: rl.Vector2 = {0.5, 0.75}*PICKER_SIZE - text_size/2
				rl.DrawTextEx(font, color_string, text_position + 2, FONT_SIZE, FONT_SPACING, rl.BLACK)
				rl.DrawTextEx(font, color_string, text_position, FONT_SIZE, FONT_SPACING, rl.GREEN)
			}
		}

		free_all(context.temp_allocator)
	}
}

ximage_color :: proc(img: ^X.XImage, x, y: i32) -> rl.Color {
	xcolor := X.GetPixel(img, x, y) 
	return {
		u8((xcolor & img.red_mask)   >> bits.trailing_zeros(img.red_mask)),
		u8((xcolor & img.green_mask) >> bits.trailing_zeros(img.green_mask)),
		u8((xcolor & img.blue_mask)  >> bits.trailing_zeros(img.blue_mask)),
		255,
	}
}

adjust_window :: proc(mouse_x, mouse_y: i32) {
	mx := mouse_x + PICKER_CELLS
	my := mouse_y + PICKER_CELLS
	dx := rl.GetMonitorWidth(rl.GetCurrentMonitor()) - (mx + PICKER_SIZE)
	dy := rl.GetMonitorHeight(rl.GetCurrentMonitor()) - (my + PICKER_SIZE)
	if dx < 0 && dy < 0 {
		mx = mouse_x - PICKER_SIZE - PICKER_CELLS
		my = mouse_y - PICKER_SIZE - PICKER_CELLS
	} else if dx < 0 {
		mx += dx
	} else if dy < 0 {
		my += dy
	}
	rl.SetWindowPosition(mx, my)
	rl.SetWindowFocused()
}

/* Return true if XI2 is available, false otherwise */
has_xi2 :: proc(dpy: ^X.Display) -> bool {
	/* We support XI 2.2 */
	major: i32 = 2
	minor: i32 = 2

	rc := X.XIQueryVersion(dpy, &major, &minor)
	if (rc == .BadRequest) {
		fmt.eprintf("No XI2 support. Server supports version %d.%d only.\n", major, minor)
		return false
	} else if (rc != .Success) {
		fmt.eprintf("Internal Error! This is a bug in Xlib.\n")
	}

	fmt.eprintf("XI2 supported. Server provides version %d.%d.\n", major, minor)

	return true
}

/* Select RawMotion XInput events */
select_events :: proc(dpy: ^X.Display, win: X.Window) {
	mask1: [size_of(X.XIEventType)]u8
	evmask := X.XIEventMask{
		deviceid = X.XIAllMasterDevices,
		mask_len = len(mask1),
		mask = &mask1[0],
	}

	X.XISetMask(evmask.mask, .RawMotion)
	X.XISelectEvents(dpy, win, &evmask, 1)
	X.Flush(dpy)
}

