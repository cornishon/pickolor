// # Resources:
// - https://keithp.com/blogs/Cursor_tracking/
package color_picker

import rl "vendor:raylib"
import X "vendor:x11/xlib"
import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:os"

PIXELS_AROUND :: 4
PIXEL_SIZE :: 20
PICKER_CELLS :: 2*PIXELS_AROUND + 1
PICKER_SIZE :: PICKER_CELLS*PIXEL_SIZE

/* Return true if XI2 is available, false otherwise */
has_xi2 :: proc(dpy: ^X.Display) -> bool {
	/* We support XI 2.2 */
	major: i32 = 2
	minor: i32 = 2

	rc := X.XIQueryVersion(dpy, &major, &minor)
	if (rc == .BadRequest) {
		fmt.printf("No XI2 support. Server supports version %d.%d only.\n", major, minor)
		return false
	} else if (rc != .Success) {
		fmt.eprintf("Internal Error! This is a bug in Xlib.\n")
	}

	fmt.printf("XI2 supported. Server provides version %d.%d.\n", major, minor)

	return true
}

/* Select RawMotion XInput events */
select_events :: proc(dpy: ^X.Display, win: X.Window) {
	evmask: X.XIEventMask
	mask1: [size_of(X.XIEventType)]u8
	// mask1: [(i32(X.XIEventType.LastEvent) + 7)/8]u8

	/* select for button and key events from all master devices */
	X.XISetMask(&mask1[0], .RawMotion)
	X.XISetMask(&mask1[0], .RawKeyPress)

	evmask.deviceid = X.XIAllMasterDevices
	evmask.mask_len = len(mask1)
	evmask.mask = &mask1[0]

	X.XISelectEvents(dpy, win, &evmask, 1)
	X.Flush(dpy)
}

main :: proc() {
	// rl.SetConfigFlags({.WINDOW_TOPMOST, .VSYNC_HINT, .WINDOW_UNDECORATED})
	rl.SetConfigFlags({.WINDOW_HIDDEN})
	rl.InitWindow(0, 0, "Color Picker")
	defer rl.CloseWindow()

	dpy := X.OpenDisplay("")

	if dpy == nil {
		fmt.eprintln("Failed to open display.")
		os.exit(1)
	}

	xi_opcode, event, error: i32
	if !X.QueryExtension(dpy, "XInputExtension", &xi_opcode, &event, &error) {
		fmt.printf("X Input extension not available.\n")
		os.exit(1)
	}

	if !has_xi2(dpy) {
		os.exit(1)
	}

	root_info: X.XWindowAttributes
	root_window := X.DefaultRootWindow(dpy)
	X.GetWindowAttributes(dpy, root_window, &root_info)

	/* select for XI2 events */
	select_events(dpy, root_window)

	picker_window := X.CreateSimpleWindow(dpy, root_window, 0, 0, PICKER_SIZE, PICKER_SIZE, 0, X.BlackPixel(dpy, 0), X.WhitePixel(dpy, 0))
	X.MapWindow(dpy, picker_window)
	make_always_on_top(dpy, root_window, picker_window)

	root_ret, child_ret: X.Window
	root_x, root_y, win_x, win_y: i32
	mask: X.KeyMask
	X.QueryPointer(dpy, root_window, &root_ret, &child_ret, &root_x, &root_y, &win_x, &win_y, &mask)
	// status := cast(X.Status) X.GrabPointer(dpy, picker_window, false, {.PointerMotion, .PointerMotionHint}, .GrabModeAsync, .GrabModeAsync, X.None, X.None, X.CurrentTime)
	// defer X.UngrabPointer(dpy, X.CurrentTime)
	// fmt.println(status)

	gc := X.DefaultGC(dpy, 0)

	event_loop: for ev: X.XEvent; true; /**/ {
		X.NextEvent(dpy, &ev)
		cookie := &ev.xcookie

		if cookie.type != .GenericEvent || cookie.extension != xi_opcode || !X.GetEventData(dpy, cookie) {
			continue
		}

		defer X.FreeEventData(dpy, cookie)

		#partial switch cast(X.XIEventType)cookie.evtype {
		case .RawKeyPress:
			re := (cast(^X.XIRawEvent)cookie.data)^
			keysym := X.KeycodeToKeysym(dpy, cast(X.KeyCode)re.detail, 0)
			fmt.println("RawKeyPress:", keysym)

			#partial switch keysym {
			case .XK_Escape:
				break event_loop
			case .XK_space:
				img := X.GetImage(dpy, root_window, root_x, root_y, 1, 1, ~uint(0), .ZPixmap)
				defer X.DestroyImage(img)

				color := fmt.ctprintf("#%06x", X.GetPixel(img, 0, 0))
				rl.SetClipboardText(color)
			}
			
		case .RawMotion:
			re := (cast(^X.XIRawEvent)cookie.data)^
			X.QueryPointer(dpy, root_window, &root_ret, &child_ret, &root_x, &root_y, &win_x, &win_y, &mask)
			// fmt.printf("raw %g,%g root %d,%d\n", re.raw_values[0], re.raw_values[1], root_x, root_y)

			img_x := clamp(root_x - PIXELS_AROUND - 1, 0, root_info.width - PICKER_CELLS - 1)
			img_y := clamp(root_y - PIXELS_AROUND - 1, 0, root_info.height - PICKER_CELLS - 1)
			img := X.GetImage(dpy, root_window, img_x, img_y, PICKER_CELLS, PICKER_CELLS, ~uint(0), .ZPixmap)
			defer X.DestroyImage(img)

			// X.SetFillStyle(dpy, gc, .FillSolid)
			for y in i32(0)..<PICKER_CELLS {
				for x in i32(0)..<PICKER_CELLS {
					color := X.GetPixel(img, x, y)
					X.SetForeground(dpy, gc, color)
					X.FillRectangle(dpy, picker_window, gc, PIXEL_SIZE*x, PIXEL_SIZE*y, PIXEL_SIZE, PIXEL_SIZE)
					if y == 4 && x == 4 {
						X.SetForeground(dpy, gc, ~color)
						X.DrawRectangle(dpy, picker_window, gc, PIXEL_SIZE*x, PIXEL_SIZE*y, PIXEL_SIZE-1, PIXEL_SIZE-1)
					}
				}
			}

			X.MoveWindow(dpy, picker_window, root_x+4, root_y+4)
		}
	}
}

// https://stackoverflow.com/questions/4345224/x11-xlib-window-always-on-top
make_always_on_top :: proc(display: ^X.Display, root, mywin: X.Window) -> bool {
	_NET_WM_STATE_REMOVE :: 0    // remove/unset property
	_NET_WM_STATE_ADD    :: 1    // add/set property
	_NET_WM_STATE_TOGGLE :: 2    // toggle property

    wmStateAbove := X.InternAtom(display, "_NET_WM_STATE_ABOVE", true)
    if wmStateAbove == X.None  {
        fmt.eprintf("ERROR: cannot find atom for _NET_WM_STATE_ABOVE !\n")
        return false
    }
    
    wmNetWmState := X.InternAtom(display, "_NET_WM_STATE", true)
    if wmNetWmState == X.None  {
        fmt.eprintf("ERROR: cannot find atom for _NET_WM_STATE !\n")
        return false
    }

    // set window always on top hint
    //
    //window  = the respective client window
    //message_type = _NET_WM_STATE
    //format = 32
    //data.l[0] = the action, as listed below
    //data.l[1] = first property to alter
    //data.l[2] = second property to alter
    //data.l[3] = source indication (0-unk,1-normal app,2-pager)
    //other data.l[] elements = 0
    //
    xclient: X.XClientMessageEvent
    xclient.type = .ClientMessage
    xclient.window = mywin                // GDK_WINDOW_XID(window)
    xclient.message_type = wmNetWmState   //gdk_x11_get_xatom_by_name_for_display( display, "_NET_WM_STATE" )
    xclient.format = 32
    xclient.data.l[0] = _NET_WM_STATE_ADD // add ? _NET_WM_STATE_ADD : _NET_WM_STATE_REMOVE
    xclient.data.l[1] = int(wmStateAbove) //gdk_x11_atom_to_xatom_for_display (display, state1)
    xclient.data.l[2] = 0                 //gdk_x11_atom_to_xatom_for_display (display, state2)
    xclient.data.l[3] = 0
    xclient.data.l[4] = 0

    //gdk_wmspec_change_state( FALSE, window,
    //  gdk_atom_intern_static_string ("_NET_WM_STATE_BELOW"),
    //  GDK_NONE );
    X.SendEvent(
    	display,
		//mywin - wrong, not app window, send to root window!
		root,     // <-- DefaultRootWindow( display )
		propagate = false,
		mask      = {.SubstructureRedirect, .SubstructureNotify},
		event     = cast(^X.XEvent)&xclient,
	)

    X.Flush(display)

    return true
}

// XCopy :: proc(display: ^X.Display, window: X.Window, selection: X.Atom, text: cstring, size: int) -> bool {
// 	X.SetSelectionOwner(display, selection, window, 0)
// 	if X.GetSelectionOwner(display, selection) != window {
// 		return false
// 	}

// 	targets_atom := X.InternAtom(display, "TARGETS", false);
// 	text_atom := X.InternAtom(display, "TEXT", false);
// 	UTF8 := X.InternAtom(display, "UTF8_STRING", true);
// 	if UTF8 == X.None {
// 		UTF8 = X.InternAtom(display, "STRING", true)
// 	}

// 	event: X.XEvent
// 	for {
// 		X.NextEvent(display, &event)
// 		#partial switch (event.type) {
// 		case .SelectionRequest:
// 			if event.xselectionrequest.selection == selection {
// 				xsr := &event.xselectionrequest
// 				ev: X.XSelectionEvent
// 				r := 0
// 				ev.type = .SelectionNotify
// 				ev.display = xsr.display
// 				ev.requestor = xsr.requestor
// 				ev.selection = xsr.selection
// 				ev.time = xsr.time
// 				ev.target = xsr.target
// 				ev.property = xsr.property
// 				if ev.target == targets_atom {
// 					r = X.ChangeProperty(ev.display, ev.requestor, ev.property, X.XA_ATOM, 32, .PropModeReplace, &UTF8, 1)
// 				} else if (ev.target == XA_STRING || ev.target == text_atom) { 
// 					r = X.ChangeProperty(ev.display, ev.requestor, ev.property, XA_STRING, 8, .PropModeReplace, text, size);
// 				} else if (ev.target == UTF8) {
// 					r = X.ChangeProperty(ev.display, ev.requestor, ev.property, UTF8, 8, .PropModeReplace, text, size);
// 				} else {
// 					ev.property = None
// 				}
// 				if ((r & 2) == 0) {
// 					X.SendEvent (display, ev.requestor, {}, {}, &ev);
// 				}
// 			}
// 		case .SelectionClear:
// 			return true
// 		}
// 	}

// 	return false
// }
