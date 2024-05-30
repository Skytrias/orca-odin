////////////////////////////////////////////////////////////////////////////////
// Utility data structures and helpers used throughout the Orca API.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Types and helpers for vectors and matrices.
////////////////////////////////////////////////////////////////////////////////

// A 2D vector type.
vec2 :: [2]f32

// A 3D vector type.
vec3 :: [3]f32

// A 2D integer vector type.
vec2i :: [2]i32

// A 4D vector type.
vec4 :: [4]f32

// A 2-by-3 matrix.
mat2x3 :: #row_major matrix[2, 3]f32

// An axis-aligned rectangle.
rect :: [4]f32

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	// Check if two 2D vectors are equal.
	vec2_equal :: proc(v0: vec2, v1: vec2) -> bool ---
	// Multiply a 2D vector by a scalar.
	vec2_mul :: proc(f: f32, v: vec2) -> vec2 ---
	// Add two 2D vectors
	vec2_add :: proc(v0: vec2, v1: vec2) -> vec2 ---
	// Transforms a vector by an affine transformation represented as a 2x3 matrix.
	mat2x3_mul :: proc(m: mat2x3, p: vec2) -> vec2 ---
	// Multiply two affine transformations represented as 2x3 matrices. Both matrices are treated as 3x3 matrices with an implicit `(0, 0, 1)` bottom row
	mat2x3_mul_m :: proc(lhs: mat2x3, rhs: mat2x3) -> mat2x3 ---
	// Invert an affine transform represented as a 2x3 matrix.
	mat2x3_inv :: proc(x: mat2x3) -> mat2x3 ---
	// Return a 2x3 matrix representing a rotation.
	mat2x3_rotate :: proc(radians: f32) -> mat2x3 ---
	// Return a 2x3 matrix representing a translation.
	mat2x3_translate :: proc(x: f32, y: f32) -> mat2x3 ---
}

////////////////////////////////////////////////////////////////////////////////
// Helpers for logging, asserting and aborting.
////////////////////////////////////////////////////////////////////////////////

// Constants allowing to specify the level of logging verbosity.
log_level :: enum u32 {
	// Only errors are logged.
	ERROR = 0,
	// Only warnings and errors are logged.
	WARNING = 1,
	// All messages are logged.
	INFO = 2,
	COUNT = 3,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	/*
	Abort the application, showing an error message.
	
	This function should not be called directly by user code, which should use the `OC_ABORT` macro instead, as the macro takes care of filling in the source location parameters of the function.
	*/
	abort_ext :: proc(file: cstring, function: cstring, line: i32, fmt: cstring, #c_vararg args: ..any) ---
	/*
	Tigger a failed assertion. This aborts the application, showing the failed assertion and an error message.
	
	This function should not be called directly by user code, which should use the `OC_ASSERT` macro instead. The macro checks the assert condition and calls the function if it is false. It also takes care of filling in the source location parameters of the function.
	*/
	assert_fail :: proc(file: cstring, function: cstring, line: i32, src: cstring, fmt: cstring, #c_vararg args: ..any) ---
	// Set the logging verbosity.
	log_set_level :: proc(level: log_level) ---
	/*
	Log a message to the console.
	
	This function should not be called directly by user code, which should use the `oc_log_XXX` family of macros instead. The macros take care of filling in the message level and source location parameters of the function.
	*/
	log_ext :: proc(level: log_level, function: cstring, file: cstring, line: i32, fmt: cstring, #c_vararg args: ..any) ---
}

////////////////////////////////////////////////////////////////////////////////
// Types and helpers for doubly-linked lists.
////////////////////////////////////////////////////////////////////////////////

// An element of an intrusive doubly-linked list.
list_elt :: struct {
	// Points to the previous element in the list.
	prev: ^list_elt,
	// Points to the next element in the list.
	next: ^list_elt,
}

// A doubly-linked list.
list :: struct {
	// Points to the first element in the list.
	first: ^list_elt,
	// Points to the last element in the list.
	last: ^list_elt,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	// Check if a list is empty.
	list_empty :: proc(list: list) -> bool ---
	// Zero-initializes a linked list.
	list_init :: proc(list: ^list) ---
	// Insert an element in a list after a given element.
	list_insert :: proc(list: ^list, afterElt: ^list_elt, elt: ^list_elt) ---
	// Insert an element in a list before a given element.
	list_insert_before :: proc(list: ^list, beforeElt: ^list_elt, elt: ^list_elt) ---
	// Remove an element from a list.
	list_remove :: proc(list: ^list, elt: ^list_elt) ---
	// Add an element at the end of a list.
	list_push_back :: proc(list: ^list, elt: ^list_elt) ---
	// Remove the last element from a list.
	list_pop_back :: proc(list: ^list) -> ^list_elt ---
	// Add an element at the beginning of a list.
	list_push_front :: proc(list: ^list, elt: ^list_elt) ---
	// Remove the first element from a list.
	list_pop_front :: proc(list: ^list) -> ^list_elt ---
}

////////////////////////////////////////////////////////////////////////////////
// Base allocator and memory arenas.
////////////////////////////////////////////////////////////////////////////////

// The prototype of a procedure to reserve memory from the system.
// The prototype of a procedure to modify a memory reservation.
// A structure that defines how to allocate memory from the system.
base_allocator :: struct {
	// A procedure to reserve memory from the system.
	reserve: mem_reserve_proc,
	// A procedure to commit memory from the system.
	commit: mem_modify_proc,
	// A procedure to decommit memory from the system.
	decommit: mem_modify_proc,
	// A procedure to release memory previously reserved from the system.
	release: mem_modify_proc,
}

// A contiguous chunk of memory managed by a memory arena.
arena_chunk :: struct {
	listElt: list_elt,
	ptr: cstring,
	offset: u64,
	committed: u64,
	cap: u64,
}

// A memory arena, allowing to allocate memory in a linear or stack-like fashion.
arena :: struct {
	// An allocator providing memory pages from the system
	base: ^base_allocator,
	// A list of `oc_arena_chunk` chunks.
	chunks: list,
	// The chunk new memory allocations are pulled from.
	currentChunk: ^arena_chunk,
}

// This struct provides a way to store the current offset in a given arena, in order to reset the arena to that offset later. This allows using arenas in a stack-like fashion, e.g. to create temporary "scratch" allocations
arena_scope :: struct {
	// The arena which offset is stored.
	arena: ^arena,
	// The arena chunk to which the offset belongs.
	chunk: ^arena_chunk,
	// The offset to rewind the arena to.
	offset: u64,
}

// Options for arena creation.
arena_options :: struct {
	// The base allocator to use with this arena
	base: ^base_allocator,
	// The amount of memory to reserve up-front when creating the arena.
	reserve: u64,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	// Initialize a memory arena.
	arena_init :: proc(arena: ^arena) ---
	// Initialize a memory arena with additional options.
	arena_init_with_options :: proc(arena: ^arena, options: ^arena_options) ---
	// Release all resources allocated to a memory arena.
	arena_cleanup :: proc(arena: ^arena) ---
	// Allocate a block of memory from an arena.
	arena_push :: proc(arena: ^arena, size: u64) -> rawptr ---
	// Allocate an aligned block of memory from an arena.
	arena_push_aligned :: proc(arena: ^arena, size: u64, alignment: u32) -> rawptr ---
	// Reset an arena. All memory that was previously allocated from this arena is released to the arena, and can be reallocated by later calls to `oc_arena_push` and similar functions. No memory is actually released _to the system_.
	arena_clear :: proc(arena: ^arena) ---
	// Begin a memory scope. This creates an `oc_arena_scope` object that stores the current offset of the arena. The arena can later be reset to that offset by calling `oc_arena_scope_end`, releasing all memory that was allocated within the scope to the arena.
	arena_scope_begin :: proc(arena: ^arena) -> arena_scope ---
	// End a memory scope. This resets an arena to the offset it had when the scope was created. All memory allocated within the scope is released back to the arena.
	arena_scope_end :: proc(scope: arena_scope) ---
	/*
	Begin a scratch scope. This creates a memory scope on a per-thread, global "scratch" arena. This allows easily creating temporary memory for scratch computations or intermediate results, in a stack-like fashion.
	
	If you must return results in an arena passed by the caller, and you also use a scratch arena to do intermediate computations, beware that the results arena could itself be a scatch arena. In this case, you have to be careful not to intermingle your scratch computations with the final result, or clear your result entirely. You can either:
	
	- Allocate memory for the result upfront and call `oc_scratch_begin` afterwards, if possible.
	- Use `oc_scratch_begin_next()` and pass it the result arena, to get a scratch arena that does not conflict with it.
	*/
	scratch_begin :: proc() -> arena_scope ---
	// Begin a scratch scope that does not conflict with a given arena. See `oc_scratch_begin()` for more details about when to use this function.
	scratch_begin_next :: proc(used: ^arena) -> arena_scope ---
}

////////////////////////////////////////////////////////////////////////////////
// String slices and string lists.
////////////////////////////////////////////////////////////////////////////////

str8 :: string

str8_elt :: struct {
	listElt: list_elt,
	_string: str8,
}

str8_list :: struct {
	list: list,
	eltCount: u64,
	len: u64,
}

str16 :: distinct []rune

str16_elt :: struct {
	listElt: list_elt,
	_string: str16,
}

str16_list :: struct {
	list: list,
	eltCount: u64,
	len: u64,
}

str32 :: distinct []u16

str32_elt :: struct {
	listElt: list_elt,
	_string: str32,
}

str32_list :: struct {
	list: list,
	eltCount: u64,
	len: u64,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	str8_from_buffer :: proc(len: u64, buffer: cstring) -> str8 ---
	str8_slice :: proc(s: str8, start: u64, end: u64) -> str8 ---
	str8_push_buffer :: proc(arena: ^arena, len: u64, buffer: cstring) -> str8 ---
	str8_push_cstring :: proc(arena: ^arena, str: cstring) -> str8 ---
	str8_push_copy :: proc(arena: ^arena, s: str8) -> str8 ---
	str8_push_slice :: proc(arena: ^arena, s: str8, start: u64, end: u64) -> str8 ---
	str8_pushfv :: proc(arena: ^arena, format: cstring, args: va_list) -> str8 ---
	str8_pushf :: proc(arena: ^arena, format: cstring, #c_vararg args: ..any) -> str8 ---
	str8_cmp :: proc(s1: str8, s2: str8) -> i32 ---
	str8_to_cstring :: proc(arena: ^arena, _string: str8) -> cstring ---
	str8_list_push :: proc(arena: ^arena, list: ^str8_list, str: str8) ---
	str8_list_pushf :: proc(arena: ^arena, list: ^str8_list, format: cstring, #c_vararg args: ..any) ---
	str8_list_collate :: proc(arena: ^arena, list: str8_list, prefix: str8, separator: str8, postfix: str8) -> str8 ---
	str8_list_join :: proc(arena: ^arena, list: str8_list) -> str8 ---
	str8_split :: proc(arena: ^arena, str: str8, separators: str8_list) -> str8_list ---
	str16_from_buffer :: proc(len: u64, buffer: ^u16) -> str16 ---
	str16_slice :: proc(s: str16, start: u64, end: u64) -> str16 ---
	str16_push_buffer :: proc(arena: ^arena, len: u64, buffer: ^u16) -> str16 ---
	str16_push_copy :: proc(arena: ^arena, s: str16) -> str16 ---
	str16_push_slice :: proc(arena: ^arena, s: str16, start: u64, end: u64) -> str16 ---
	str16_list_push :: proc(arena: ^arena, list: ^str16_list, str: str16) ---
	str16_list_join :: proc(arena: ^arena, list: str16_list) -> str16 ---
	str16_split :: proc(arena: ^arena, str: str16, separators: str16_list) -> str16_list ---
	str32_from_buffer :: proc(len: u64, buffer: ^u32) -> str32 ---
	str32_slice :: proc(s: str32, start: u64, end: u64) -> str32 ---
	str32_push_buffer :: proc(arena: ^arena, len: u64, buffer: ^u32) -> str32 ---
	str32_push_copy :: proc(arena: ^arena, s: str32) -> str32 ---
	str32_push_slice :: proc(arena: ^arena, s: str32, start: u64, end: u64) -> str32 ---
	str32_list_push :: proc(arena: ^arena, list: ^str32_list, str: str32) ---
	str32_list_join :: proc(arena: ^arena, list: str32_list) -> str32 ---
	str32_split :: proc(arena: ^arena, str: str32, separators: str32_list) -> str32_list ---
}

////////////////////////////////////////////////////////////////////////////////
// UTF8 encoding/decoding.
////////////////////////////////////////////////////////////////////////////////

utf32 :: rune

utf8_dec :: struct {
	codepoint: utf32,
	size: u32,
}

unicode_range :: struct {
	firstCodePoint: utf32,
	count: u32,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	utf8_size_from_leading_char :: proc(leadingChar: char) -> u32 ---
	utf8_codepoint_size :: proc(codePoint: utf32) -> u32 ---
	utf8_codepoint_count_for_string :: proc(_string: str8) -> u64 ---
	utf8_byte_count_for_codepoints :: proc(codePoints: str32) -> u64 ---
	utf8_next_offset :: proc(_string: str8, byteOffset: u64) -> u64 ---
	utf8_prev_offset :: proc(_string: str8, byteOffset: u64) -> u64 ---
	utf8_decode :: proc(_string: str8) -> utf8_dec ---
	utf8_decode_at :: proc(_string: str8, offset: u64) -> utf8_dec ---
	utf8_encode :: proc(dst: cstring, codePoint: utf32) -> str8 ---
	utf8_to_codepoints :: proc(maxCount: u64, backing: ^utf32, _string: str8) -> str32 ---
	utf8_from_codepoints :: proc(maxBytes: u64, backing: cstring, codePoints: str32) -> str8 ---
	utf8_push_to_codepoints :: proc(arena: ^arena, _string: str8) -> str32 ---
	utf8_push_from_codepoints :: proc(arena: ^arena, codePoints: str32) -> str8 ---
}

////////////////////////////////////////////////////////////////////////////////
// Input, windowing, dialogs.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Application events.
////////////////////////////////////////////////////////////////////////////////

event_type :: enum u32 {
	NONE = 0,
	KEYBOARD_MODS = 1,
	KEYBOARD_KEY = 2,
	KEYBOARD_CHAR = 3,
	MOUSE_BUTTON = 4,
	MOUSE_MOVE = 5,
	MOUSE_WHEEL = 6,
	MOUSE_ENTER = 7,
	MOUSE_LEAVE = 8,
	CLIPBOARD_PASTE = 9,
	WINDOW_RESIZE = 10,
	WINDOW_MOVE = 11,
	WINDOW_FOCUS = 12,
	WINDOW_UNFOCUS = 13,
	WINDOW_HIDE = 14,
	WINDOW_SHOW = 15,
	WINDOW_CLOSE = 16,
	PATHDROP = 17,
	FRAME = 18,
	QUIT = 19,
}

key_action :: enum u32 {
	NO_ACTION = 0,
	PRESS = 1,
	RELEASE = 2,
	REPEAT = 3,
}

scan_code :: enum u32 {
	UNKNOWN = 0,
	SPACE = 32,
	APOSTROPHE = 39,
	COMMA = 44,
	MINUS = 45,
	PERIOD = 46,
	SLASH = 47,
	_0 = 48,
	_1 = 49,
	_2 = 50,
	_3 = 51,
	_4 = 52,
	_5 = 53,
	_6 = 54,
	_7 = 55,
	_8 = 56,
	_9 = 57,
	SEMICOLON = 59,
	EQUAL = 61,
	LEFT_BRACKET = 91,
	BACKSLASH = 92,
	RIGHT_BRACKET = 93,
	GRAVE_ACCENT = 96,
	A = 97,
	B = 98,
	C = 99,
	D = 100,
	E = 101,
	F = 102,
	G = 103,
	H = 104,
	I = 105,
	J = 106,
	K = 107,
	L = 108,
	M = 109,
	N = 110,
	O = 111,
	P = 112,
	Q = 113,
	R = 114,
	S = 115,
	T = 116,
	U = 117,
	V = 118,
	W = 119,
	X = 120,
	Y = 121,
	Z = 122,
	WORLD_1 = 161,
	WORLD_2 = 162,
	ESCAPE = 256,
	ENTER = 257,
	TAB = 258,
	BACKSPACE = 259,
	INSERT = 260,
	DELETE = 261,
	RIGHT = 262,
	LEFT = 263,
	DOWN = 264,
	UP = 265,
	PAGE_UP = 266,
	PAGE_DOWN = 267,
	HOME = 268,
	END = 269,
	CAPS_LOCK = 280,
	SCROLL_LOCK = 281,
	NUM_LOCK = 282,
	PRINT_SCREEN = 283,
	PAUSE = 284,
	F1 = 290,
	F2 = 291,
	F3 = 292,
	F4 = 293,
	F5 = 294,
	F6 = 295,
	F7 = 296,
	F8 = 297,
	F9 = 298,
	F10 = 299,
	F11 = 300,
	F12 = 301,
	F13 = 302,
	F14 = 303,
	F15 = 304,
	F16 = 305,
	F17 = 306,
	F18 = 307,
	F19 = 308,
	F20 = 309,
	F21 = 310,
	F22 = 311,
	F23 = 312,
	F24 = 313,
	F25 = 314,
	KP_0 = 320,
	KP_1 = 321,
	KP_2 = 322,
	KP_3 = 323,
	KP_4 = 324,
	KP_5 = 325,
	KP_6 = 326,
	KP_7 = 327,
	KP_8 = 328,
	KP_9 = 329,
	KP_DECIMAL = 330,
	KP_DIVIDE = 331,
	KP_MULTIPLY = 332,
	KP_SUBTRACT = 333,
	KP_ADD = 334,
	KP_ENTER = 335,
	KP_EQUAL = 336,
	LEFT_SHIFT = 340,
	LEFT_CONTROL = 341,
	LEFT_ALT = 342,
	LEFT_SUPER = 343,
	RIGHT_SHIFT = 344,
	RIGHT_CONTROL = 345,
	RIGHT_ALT = 346,
	RIGHT_SUPER = 347,
	MENU = 348,
	COUNT = 349,
}

key_code :: enum u32 {
	UNKNOWN = 0,
	SPACE = 32,
	APOSTROPHE = 39,
	COMMA = 44,
	MINUS = 45,
	PERIOD = 46,
	SLASH = 47,
	_0 = 48,
	_1 = 49,
	_2 = 50,
	_3 = 51,
	_4 = 52,
	_5 = 53,
	_6 = 54,
	_7 = 55,
	_8 = 56,
	_9 = 57,
	SEMICOLON = 59,
	EQUAL = 61,
	LEFT_BRACKET = 91,
	BACKSLASH = 92,
	RIGHT_BRACKET = 93,
	GRAVE_ACCENT = 96,
	A = 97,
	B = 98,
	C = 99,
	D = 100,
	E = 101,
	F = 102,
	G = 103,
	H = 104,
	I = 105,
	J = 106,
	K = 107,
	L = 108,
	M = 109,
	N = 110,
	O = 111,
	P = 112,
	Q = 113,
	R = 114,
	S = 115,
	T = 116,
	U = 117,
	V = 118,
	W = 119,
	X = 120,
	Y = 121,
	Z = 122,
	WORLD_1 = 161,
	WORLD_2 = 162,
	ESCAPE = 256,
	ENTER = 257,
	TAB = 258,
	BACKSPACE = 259,
	INSERT = 260,
	DELETE = 261,
	RIGHT = 262,
	LEFT = 263,
	DOWN = 264,
	UP = 265,
	PAGE_UP = 266,
	PAGE_DOWN = 267,
	HOME = 268,
	END = 269,
	CAPS_LOCK = 280,
	SCROLL_LOCK = 281,
	NUM_LOCK = 282,
	PRINT_SCREEN = 283,
	PAUSE = 284,
	F1 = 290,
	F2 = 291,
	F3 = 292,
	F4 = 293,
	F5 = 294,
	F6 = 295,
	F7 = 296,
	F8 = 297,
	F9 = 298,
	F10 = 299,
	F11 = 300,
	F12 = 301,
	F13 = 302,
	F14 = 303,
	F15 = 304,
	F16 = 305,
	F17 = 306,
	F18 = 307,
	F19 = 308,
	F20 = 309,
	F21 = 310,
	F22 = 311,
	F23 = 312,
	F24 = 313,
	F25 = 314,
	KP_0 = 320,
	KP_1 = 321,
	KP_2 = 322,
	KP_3 = 323,
	KP_4 = 324,
	KP_5 = 325,
	KP_6 = 326,
	KP_7 = 327,
	KP_8 = 328,
	KP_9 = 329,
	KP_DECIMAL = 330,
	KP_DIVIDE = 331,
	KP_MULTIPLY = 332,
	KP_SUBTRACT = 333,
	KP_ADD = 334,
	KP_ENTER = 335,
	KP_EQUAL = 336,
	LEFT_SHIFT = 340,
	LEFT_CONTROL = 341,
	LEFT_ALT = 342,
	LEFT_SUPER = 343,
	RIGHT_SHIFT = 344,
	RIGHT_CONTROL = 345,
	RIGHT_ALT = 346,
	RIGHT_SUPER = 347,
	MENU = 348,
	COUNT = 349,
}

keymod_flags :: enum u32 {
	NONE = 0,
	ALT = 1,
	SHIFT = 2,
	CTRL = 4,
	CMD = 8,
	MAIN_MODIFIER = 16,
}

mouse_button :: enum u32 {
	LEFT = 0,
	RIGHT = 1,
	MIDDLE = 2,
	EXT1 = 3,
	EXT2 = 4,
	BUTTON_COUNT = 5,
}

key_event :: struct {
	action: key_action,
	scanCode: scan_code,
	keyCode: key_code,
	button: mouse_button,
	mods: keymod_flags,
	clickCount: u8,
}

char_event :: struct {
	codepoint: utf32,
	sequence: array,
	seqLen: u8,
}

mouse_event :: struct {
	x: f32,
	y: f32,
	deltaX: f32,
	deltaY: f32,
	mods: keymod_flags,
}

move_event :: struct {
	frame: rect,
	content: rect,
}

event :: struct {
	window: window,
	type: event_type,
	_: struct #raw_union {
		key: key_event,
		character: char_event,
		mouse: mouse_event,
		move: move_event,
		paths: str8_list,
	},
}

file_dialog_kind :: enum u32 {
	SAVE = 0,
	OPEN = 1,
}

_oc_file_dialog_flags :: enum u32 {
	FILES = 1,
	DIRECTORIES = 2,
	MULTIPLE = 4,
	CREATE_DIRECTORIES = 8,
}

file_dialog_desc :: struct {
	kind: file_dialog_kind,
	flags: file_dialog_flags,
	title: str8,
	okLabel: str8,
	startAt: file,
	startPath: str8,
	filters: str8_list,
}

file_dialog_button :: enum u32 {
	CANCEL = 0,
	OK = 1,
}

file_dialog_result :: struct {
	button: file_dialog_button,
	path: str8,
	selection: str8_list,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	window_set_title :: proc(title: str8) ---
	window_set_size :: proc(size: vec2) ---
	request_quit :: proc() ---
	scancode_to_keycode :: proc(scanCode: scan_code) -> key_code ---
	clipboard_set_string :: proc(_string: str8) ---
}

////////////////////////////////////////////////////////////////////////////////
// File input/output.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// API for opening, reading and writing files.
////////////////////////////////////////////////////////////////////////////////

file :: distinct u64

file_open_flags_enum :: enum u32 {
	NONE = 0,
	APPEND = 2,
	TRUNCATE = 4,
	CREATE = 8,
	SYMLINK = 16,
	NO_FOLLOW = 32,
	RESTRICT = 64,
}

file_access_enum :: enum u32 {
	NONE = 0,
	READ = 2,
	WRITE = 4,
}

file_whence :: enum u32 {
	SET = 0,
	END = 1,
	CURRENT = 2,
}

io_op_enum :: enum u32 {
	OPEN_AT = 0,
	CLOSE = 1,
	FSTAT = 2,
	SEEK = 3,
	READ = 4,
	WRITE = 5,
	OC_OC_IO_ERROR = 6,
}

io_req :: struct {
	id: io_req_id,
	op: io_op,
	handle: file,
	offset: i64,
	size: u64,
	_: struct #raw_union {
		buffer: cstring,
		unused: u64,
	},
	_: struct #raw_union {
		_: struct {
			rights: file_access,
			flags: file_open_flags,
		},
		open: struct {
			rights: file_access,
			flags: file_open_flags,
		},
		whence: file_whence,
	},
}

io_error_enum :: enum u32 {
	OK = 0,
	UNKNOWN = 1,
	OP = 2,
	HANDLE = 3,
	PREV = 4,
	ARG = 5,
	PERM = 6,
	SPACE = 7,
	NO_ENTRY = 8,
	EXISTS = 9,
	NOT_DIR = 10,
	DIR = 11,
	MAX_FILES = 12,
	MAX_LINKS = 13,
	PATH_LENGTH = 14,
	FILE_SIZE = 15,
	OVERFLOW = 16,
	NOT_READY = 17,
	MEM = 18,
	INTERRUPT = 19,
	PHYSICAL = 20,
	NO_DEVICE = 21,
	WALKOUT = 22,
}

io_cmp :: struct {
	id: io_req_id,
	error: io_error,
	_: struct #raw_union {
		result: i64,
		size: u64,
		offset: i64,
		handle: file,
	},
}

file_type :: enum u32 {
	UNKNOWN = 0,
	REGULAR = 1,
	DIRECTORY = 2,
	SYMLINK = 3,
	BLOCK = 4,
	CHARACTER = 5,
	FIFO = 6,
	SOCKET = 7,
}

file_perm_enum :: enum u32 {
	OTHER_EXEC = 1,
	OTHER_WRITE = 2,
	OTHER_READ = 4,
	GROUP_EXEC = 8,
	GROUP_WRITE = 16,
	GROUP_READ = 32,
	OWNER_EXEC = 64,
	OWNER_WRITE = 128,
	OWNER_READ = 256,
	STICKY_BIT = 512,
	SET_GID = 1024,
	SET_UID = 2048,
}

datestamp :: struct {
	seconds: i64,
	fraction: u64,
}

file_status :: struct {
	uid: u64,
	type: file_type,
	perm: file_perm,
	size: u64,
	creationDate: datestamp,
	accessDate: datestamp,
	modificationDate: datestamp,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	io_wait_single_req :: proc(req: ^io_req) -> io_cmp ---
	file_nil :: proc() -> file ---
	file_is_nil :: proc(handle: file) -> bool ---
	file_open :: proc(path: str8, rights: file_access, flags: file_open_flags) -> file ---
	file_open_at :: proc(dir: file, path: str8, rights: file_access, flags: file_open_flags) -> file ---
	file_close :: proc(file: file) ---
	file_pos :: proc(file: file) -> i64 ---
	file_seek :: proc(file: file, offset: i64, whence: file_whence) -> i64 ---
	file_write :: proc(file: file, size: u64, buffer: cstring) -> u64 ---
	file_read :: proc(file: file, size: u64, buffer: cstring) -> u64 ---
	file_last_error :: proc(handle: file) -> io_error ---
	file_get_status :: proc(file: file) -> file_status ---
	file_size :: proc(file: file) -> u64 ---
	file_open_with_request :: proc(path: str8, rights: file_access, flags: file_open_flags) -> file ---
}

////////////////////////////////////////////////////////////////////////////////
// API for obtaining file capabilities through open/save dialogs.
////////////////////////////////////////////////////////////////////////////////

file_open_with_dialog_elt :: struct {
	listElt: list_elt,
	file: file,
}

file_open_with_dialog_result :: struct {
	button: file_dialog_button,
	file: file,
	selection: list,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	file_open_with_dialog :: proc(arena: ^arena, rights: file_access, flags: file_open_flags, desc: ^file_dialog_desc) -> file_open_with_dialog_result ---
}

////////////////////////////////////////////////////////////////////////////////
// API for handling filesystem paths.
////////////////////////////////////////////////////////////////////////////////

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	path_slice_directory :: proc(path: str8) -> str8 ---
	path_slice_filename :: proc(path: str8) -> str8 ---
	path_split :: proc(arena: ^arena, path: str8) -> str8_list ---
	path_join :: proc(arena: ^arena, elements: str8_list) -> str8 ---
	path_append :: proc(arena: ^arena, parent: str8, relPath: str8) -> str8 ---
	path_is_absolute :: proc(path: str8) -> bool ---
	path_slice_directory :: proc(path: str8) -> str8 ---
	path_slice_filename :: proc(path: str8) -> str8 ---
	path_split :: proc(arena: ^arena, path: str8) -> str8_list ---
	path_join :: proc(arena: ^arena, elements: str8_list) -> str8 ---
	path_append :: proc(arena: ^arena, parent: str8, relPath: str8) -> str8 ---
	path_is_absolute :: proc(path: str8) -> bool ---
}

////////////////////////////////////////////////////////////////////////////////
// 2D/3D rendering APIs.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// A 2D Vector Graphics API.
////////////////////////////////////////////////////////////////////////////////

surface :: distinct u64

canvas_renderer :: distinct u64

canvas_context :: distinct u64

font :: distinct u64

image :: distinct u64

gradient_blend_space :: enum u32 {
	LINEAR = 0,
	SRGB = 1,
}

color_space :: enum u32 {
	RGB = 0,
	SRGB = 1,
}

color :: [4]f32

joint_type :: enum u32 {
	MITER = 0,
	BEVEL = 1,
	NONE = 2,
}

cap_type :: enum u32 {
	NONE = 0,
	SQUARE = 1,
}

font_metrics :: struct {
	ascent: f32,
	descent: f32,
	lineGap: f32,
	xHeight: f32,
	capHeight: f32,
	width: f32,
}

glyph_metrics :: struct {
	ink: rect,
	advance: vec2,
}

text_metrics :: struct {
	ink: rect,
	logical: rect,
	advance: vec2,
}



image_region :: struct {
	image: image,
	rect: rect,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	surface_nil :: proc() -> surface ---
	surface_is_nil :: proc(surface: surface) -> bool ---
	surface_destroy :: proc(surface: surface) ---
	surface_get_size :: proc(surface: surface) -> vec2 ---
	surface_contents_scaling :: proc(surface: surface) -> vec2 ---
	surface_bring_to_front :: proc(surface: surface) ---
	surface_send_to_back :: proc(surface: surface) ---
	surface_get_hidden :: proc(surface: surface) -> bool ---
	surface_set_hidden :: proc(surface: surface, hidden: bool) ---
	color_rgba :: proc(r: f32, g: f32, b: f32, a: f32) -> color ---
	color_srgba :: proc(r: f32, g: f32, b: f32, a: f32) -> color ---
	color_convert :: proc(color: color, colorSpace: color_space) -> color ---
	canvas_renderer_nil :: proc() -> canvas_renderer ---
	canvas_renderer_is_nil :: proc(renderer: canvas_renderer) -> bool ---
	canvas_renderer_create :: proc() -> canvas_renderer ---
	canvas_renderer_destroy :: proc(renderer: canvas_renderer) ---
	canvas_render :: proc(renderer: canvas_renderer, _context: canvas_context, surface: surface) ---
	canvas_present :: proc(renderer: canvas_renderer, surface: surface) ---
	canvas_surface_create :: proc(renderer: canvas_renderer) -> surface ---
	canvas_surface_swap_interval :: proc(surface: surface, swap: i32) ---
	canvas_context_nil :: proc() -> canvas_context ---
	canvas_context_is_nil :: proc(_context: canvas_context) -> bool ---
	canvas_context_create :: proc() -> canvas_context ---
	canvas_context_destroy :: proc(_context: canvas_context) ---
	canvas_context_select :: proc(_context: canvas_context) -> canvas_context ---
	canvas_context_set_msaa_sample_count :: proc(_context: canvas_context, sampleCount: u32) ---
	font_nil :: proc() -> font ---
	font_is_nil :: proc(font: font) -> bool ---
	font_create_from_memory :: proc(mem: str8, rangeCount: u32, ranges: ^unicode_range) -> font ---
	font_create_from_file :: proc(file: file, rangeCount: u32, ranges: ^unicode_range) -> font ---
	font_create_from_path :: proc(path: str8, rangeCount: u32, ranges: ^unicode_range) -> font ---
	font_destroy :: proc(font: font) ---
	font_get_glyph_indices :: proc(font: font, codePoints: str32, backing: str32) -> str32 ---
	font_push_glyph_indices :: proc(arena: ^arena, font: font, codePoints: str32) -> str32 ---
	font_get_glyph_index :: proc(font: font, codePoint: utf32) -> u32 ---
	font_get_metrics :: proc(font: font, emSize: f32) -> font_metrics ---
	font_get_metrics_unscaled :: proc(font: font) -> font_metrics ---
	font_get_scale_for_em_pixels :: proc(font: font, emSize: f32) -> f32 ---
	font_text_metrics_utf32 :: proc(font: font, fontSize: f32, codepoints: str32) -> text_metrics ---
	font_text_metrics :: proc(font: font, fontSize: f32, text: str8) -> text_metrics ---
	image_nil :: proc() -> image ---
	image_is_nil :: proc(a: image) -> bool ---
	image_create :: proc(renderer: canvas_renderer, width: u32, height: u32) -> image ---
	image_create_from_rgba8 :: proc(renderer: canvas_renderer, width: u32, height: u32, pixels: ^u8) -> image ---
	image_create_from_memory :: proc(renderer: canvas_renderer, mem: str8, flip: bool) -> image ---
	image_create_from_file :: proc(renderer: canvas_renderer, file: file, flip: bool) -> image ---
	image_create_from_path :: proc(renderer: canvas_renderer, path: str8, flip: bool) -> image ---
	image_destroy :: proc(image: image) ---
	image_upload_region_rgba8 :: proc(image: image, region: rect, pixels: ^u8) ---
	image_size :: proc(image: image) -> vec2 ---
	rect_atlas_create :: proc(arena: ^arena, width: i32, height: i32) -> ^rect_atlas ---
	rect_atlas_alloc :: proc(atlas: ^rect_atlas, width: i32, height: i32) -> rect ---
	rect_atlas_recycle :: proc(atlas: ^rect_atlas, rect: rect) ---
	image_atlas_alloc_from_rgba8 :: proc(atlas: ^rect_atlas, backingImage: image, width: u32, height: u32, pixels: ^u8) -> image_region ---
	image_atlas_alloc_from_memory :: proc(atlas: ^rect_atlas, backingImage: image, mem: str8, flip: bool) -> image_region ---
	image_atlas_alloc_from_file :: proc(atlas: ^rect_atlas, backingImage: image, file: file, flip: bool) -> image_region ---
	image_atlas_alloc_from_path :: proc(atlas: ^rect_atlas, backingImage: image, path: str8, flip: bool) -> image_region ---
	image_atlas_recycle :: proc(atlas: ^rect_atlas, imageRgn: image_region) ---
	matrix_push :: proc(matrix: mat2x3) ---
	matrix_multiply_push :: proc(matrix: mat2x3) ---
	matrix_pop :: proc() ---
	matrix_top :: proc() -> mat2x3 ---
	clip_push :: proc(x: f32, y: f32, w: f32, h: f32) ---
	clip_pop :: proc() ---
	clip_top :: proc() -> rect ---
	set_color :: proc(color: color) ---
	set_color_rgba :: proc(r: f32, g: f32, b: f32, a: f32) ---
	set_color_srgba :: proc(r: f32, g: f32, b: f32, a: f32) ---
	set_gradient :: proc(blendSpace: gradient_blend_space, bottomLeft: color, bottomRight: color, topRight: color, topLeft: color) ---
	set_width :: proc(width: f32) ---
	set_tolerance :: proc(tolerance: f32) ---
	set_joint :: proc(joint: joint_type) ---
	set_max_joint_excursion :: proc(maxJointExcursion: f32) ---
	set_cap :: proc(cap: cap_type) ---
	set_font :: proc(font: font) ---
	set_font_size :: proc(size: f32) ---
	set_text_flip :: proc(flip: bool) ---
	set_image :: proc(image: image) ---
	set_image_source_region :: proc(region: rect) ---
	get_color :: proc() -> color ---
	get_width :: proc() -> f32 ---
	get_tolerance :: proc() -> f32 ---
	get_joint :: proc() -> joint_type ---
	get_max_joint_excursion :: proc() -> f32 ---
	get_cap :: proc() -> cap_type ---
	get_font :: proc() -> font ---
	get_font_size :: proc() -> f32 ---
	get_text_flip :: proc() -> bool ---
	get_image :: proc() -> image ---
	get_image_source_region :: proc() -> rect ---
	get_position :: proc() -> vec2 ---
	move_to :: proc(x: f32, y: f32) ---
	line_to :: proc(x: f32, y: f32) ---
	quadratic_to :: proc(x1: f32, y1: f32, x2: f32, y2: f32) ---
	cubic_to :: proc(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) ---
	close_path :: proc() ---
	glyph_outlines :: proc(glyphIndices: str32) -> rect ---
	codepoints_outlines :: proc(_string: str32) ---
	text_outlines :: proc(_string: str8) ---
	clear :: proc() ---
	fill :: proc() ---
	stroke :: proc() ---
	rectangle_fill :: proc(x: f32, y: f32, w: f32, h: f32) ---
	rectangle_stroke :: proc(x: f32, y: f32, w: f32, h: f32) ---
	rounded_rectangle_fill :: proc(x: f32, y: f32, w: f32, h: f32, r: f32) ---
	rounded_rectangle_stroke :: proc(x: f32, y: f32, w: f32, h: f32, r: f32) ---
	ellipse_fill :: proc(x: f32, y: f32, rx: f32, ry: f32) ---
	ellipse_stroke :: proc(x: f32, y: f32, rx: f32, ry: f32) ---
	circle_fill :: proc(x: f32, y: f32, r: f32) ---
	circle_stroke :: proc(x: f32, y: f32, r: f32) ---
	arc :: proc(x: f32, y: f32, r: f32, arcAngle: f32, startAngle: f32) ---
	text_fill :: proc(x: f32, y: f32, text: str8) ---
	image_draw :: proc(image: image, rect: rect) ---
	image_draw_region :: proc(image: image, srcRegion: rect, dstRegion: rect) ---
}

////////////////////////////////////////////////////////////////////////////////
// A surface for rendering using the GLES API.
////////////////////////////////////////////////////////////////////////////////

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	gles_surface_create :: proc() -> surface ---
	gles_surface_make_current :: proc(surface: surface) ---
	gles_surface_swap_interval :: proc(surface: surface, interval: i32) ---
	gles_surface_swap_buffers :: proc(surface: surface) ---
}

////////////////////////////////////////////////////////////////////////////////
// Graphical User Interface API.
////////////////////////////////////////////////////////////////////////////////

key_state :: struct {
	lastUpdate: u64,
	transitionCount: u32,
	repeatCount: u32,
	down: bool,
	sysClicked: bool,
	sysDoubleClicked: bool,
	sysTripleClicked: bool,
}

keyboard_state :: struct {
	keys: array,
	mods: keymod_flags,
}

mouse_state :: struct {
	lastUpdate: u64,
	posValid: bool,
	pos: vec2,
	delta: vec2,
	wheel: vec2,
	_: struct #raw_union {
		buttons: array,
		_: struct {
			left: key_state,
			right: key_state,
			middle: key_state,
			ext1: key_state,
			ext2: key_state,
		},
	},
}

BACKING_SIZE :: 64

text_state :: struct {
	lastUpdate: u64,
	backing: array,
	codePoints: str32,
}

clipboard_state :: struct {
	lastUpdate: u64,
	pastedText: str8,
}

input_state :: struct {
	frameCounter: u64,
	keyboard: keyboard_state,
	mouse: mouse_state,
	text: text_state,
	clipboard: clipboard_state,
}

ui_key :: struct {
	hash: u64,
}

ui_axis :: enum u32 {
	X = 0,
	Y = 1,
	COUNT = 2,
}

ui_align :: enum u32 {
	START = 0,
	END = 1,
	CENTER = 2,
}

ui_layout_align :: [2]ui_align

ui_layout :: struct {
	axis: ui_axis,
	spacing: f32,
	_: struct #raw_union {
		_: struct {
			x: f32,
			y: f32,
		},
		c: array,
	},
	margin: struct #raw_union {
		_: struct {
			x: f32,
			y: f32,
		},
		c: array,
	},
	align: ui_layout_align,
}

ui_size_kind :: enum u32 {
	TEXT = 0,
	PIXELS = 1,
	CHILDREN = 2,
	PARENT = 3,
	PARENT_MINUS_PIXELS = 4,
}

ui_size :: struct {
	kind: ui_size_kind,
	value: f32,
	relax: f32,
	minSize: f32,
}

ui_box_size :: [2]ui_size

ui_box_floating :: [2]bool

 :: enum u32 {
	NONE = 0,
	SIZE_WIDTH = 2,
	SIZE_HEIGHT = 4,
	LAYOUT_AXIS = 8,
	LAYOUT_ALIGN_X = 16,
	LAYOUT_ALIGN_Y = 32,
	LAYOUT_SPACING = 64,
	LAYOUT_MARGIN_X = 128,
	LAYOUT_MARGIN_Y = 256,
	FLOAT_X = 512,
	FLOAT_Y = 1024,
	COLOR = 2048,
	BG_COLOR = 4096,
	BORDER_COLOR = 8192,
	BORDER_SIZE = 16384,
	ROUNDNESS = 32768,
	FONT = 65536,
	FONT_SIZE = 131072,
	ANIMATION_TIME = 262144,
	ANIMATION_MASK = 524288,
	SIZE = 6,
	LAYOUT_MARGINS = 384,
	LAYOUT = 504,
	FLOAT = 1536,
	MASK_INHERITED = 985088,
}

ui_style :: struct {
	size: ui_box_size,
	layout: ui_layout,
	floating: ui_box_floating,
	floatTarget: vec2,
	color: color,
	bgColor: color,
	borderColor: color,
	font: font,
	fontSize: f32,
	borderSize: f32,
	roundness: f32,
	animationTime: f32,
	animationMask: ui_style_mask,
}

ui_palette :: struct {
	red0: color,
	red1: color,
	red2: color,
	red3: color,
	red4: color,
	red5: color,
	red6: color,
	red7: color,
	red8: color,
	red9: color,
	orange0: color,
	orange1: color,
	orange2: color,
	orange3: color,
	orange4: color,
	orange5: color,
	orange6: color,
	orange7: color,
	orange8: color,
	orange9: color,
	amber0: color,
	amber1: color,
	amber2: color,
	amber3: color,
	amber4: color,
	amber5: color,
	amber6: color,
	amber7: color,
	amber8: color,
	amber9: color,
	yellow0: color,
	yellow1: color,
	yellow2: color,
	yellow3: color,
	yellow4: color,
	yellow5: color,
	yellow6: color,
	yellow7: color,
	yellow8: color,
	yellow9: color,
	lime0: color,
	lime1: color,
	lime2: color,
	lime3: color,
	lime4: color,
	lime5: color,
	lime6: color,
	lime7: color,
	lime8: color,
	lime9: color,
	lightGreen0: color,
	lightGreen1: color,
	lightGreen2: color,
	lightGreen3: color,
	lightGreen4: color,
	lightGreen5: color,
	lightGreen6: color,
	lightGreen7: color,
	lightGreen8: color,
	lightGreen9: color,
	green0: color,
	green1: color,
	green2: color,
	green3: color,
	green4: color,
	green5: color,
	green6: color,
	green7: color,
	green8: color,
	green9: color,
	teal0: color,
	teal1: color,
	teal2: color,
	teal3: color,
	teal4: color,
	teal5: color,
	teal6: color,
	teal7: color,
	teal8: color,
	teal9: color,
	cyan0: color,
	cyan1: color,
	cyan2: color,
	cyan3: color,
	cyan4: color,
	cyan5: color,
	cyan6: color,
	cyan7: color,
	cyan8: color,
	cyan9: color,
	lightBlue0: color,
	lightBlue1: color,
	lightBlue2: color,
	lightBlue3: color,
	lightBlue4: color,
	lightBlue5: color,
	lightBlue6: color,
	lightBlue7: color,
	lightBlue8: color,
	lightBlue9: color,
	blue0: color,
	blue1: color,
	blue2: color,
	blue3: color,
	blue4: color,
	blue5: color,
	blue6: color,
	blue7: color,
	blue8: color,
	blue9: color,
	indigo0: color,
	indigo1: color,
	indigo2: color,
	indigo3: color,
	indigo4: color,
	indigo5: color,
	indigo6: color,
	indigo7: color,
	indigo8: color,
	indigo9: color,
	violet0: color,
	violet1: color,
	violet2: color,
	violet3: color,
	violet4: color,
	violet5: color,
	violet6: color,
	violet7: color,
	violet8: color,
	violet9: color,
	purple0: color,
	purple1: color,
	purple2: color,
	purple3: color,
	purple4: color,
	purple5: color,
	purple6: color,
	purple7: color,
	purple8: color,
	purple9: color,
	pink0: color,
	pink1: color,
	pink2: color,
	pink3: color,
	pink4: color,
	pink5: color,
	pink6: color,
	pink7: color,
	pink8: color,
	pink9: color,
	grey0: color,
	grey1: color,
	grey2: color,
	grey3: color,
	grey4: color,
	grey5: color,
	grey6: color,
	grey7: color,
	grey8: color,
	grey9: color,
	black: color,
	white: color,
}

ui_theme :: struct {
	white: color,
	primary: color,
	primaryHover: color,
	primaryActive: color,
	border: color,
	fill0: color,
	fill1: color,
	fill2: color,
	bg0: color,
	bg1: color,
	bg2: color,
	bg3: color,
	bg4: color,
	text0: color,
	text1: color,
	text2: color,
	text3: color,
	sliderThumbBorder: color,
	elevatedBorder: color,
	roundnessSmall: f32,
	roundnessMedium: f32,
	roundnessLarge: f32,
	palette: ^ui_palette,
}

ui_tag :: struct {
	hash: u64,
}

ui_selector_kind :: enum u32 {
	ANY = 0,
	OWNER = 1,
	TEXT = 2,
	TAG = 3,
	STATUS = 4,
	KEY = 5,
}

ui_status_enum :: enum u32 {
	NONE = 0,
	HOVER = 2,
	HOT = 4,
	ACTIVE = 8,
	DRAGGING = 16,
}

ui_selector_op :: enum u32 {
	DESCENDANT = 0,
	AND = 1,
}

ui_selector :: struct {
	listElt: list_elt,
	kind: ui_selector_kind,
	op: ui_selector_op,
	_: struct #raw_union {
		text: str8,
		key: ui_key,
		tag: ui_tag,
		status: ui_status,
	},
}

ui_pattern :: struct {
	l: list,
}

ui_box :: struct {
	listElt: list_elt,
	children: list,
	parent: ^ui_box,
	overlayElt: list_elt,
	bucketElt: list_elt,
	key: ui_key,
	frameCounter: u64,
	flags: ui_flags,
	_string: str8,
	tags: list,
	drawProc: ui_box_draw_proc,
	drawData: rawptr,
	beforeRules: list,
	afterRules: list,
	targetStyle: ^ui_style,
	style: ui_style,
	z: u32,
	floatPos: vec2,
	childrenSum: array,
	spacing: array,
	minSize: array,
	rect: rect,
	sig: ^ui_sig,
	fresh: bool,
	closed: bool,
	parentClosed: bool,
	dragging: bool,
	hot: bool,
	active: bool,
	scroll: vec2,
	pressedMouse: vec2,
	hotTransition: f32,
	activeTransition: f32,
}

ui_style_rule :: struct {
	boxElt: list_elt,
	buildElt: list_elt,
	tmpElt: list_elt,
	owner: ^ui_box,
	pattern: ui_pattern,
	mask: ui_style_mask,
	style: ^ui_style,
}

ui_sig :: struct {
	box: ^ui_box,
	mouse: vec2,
	delta: vec2,
	wheel: vec2,
	pressed: bool,
	released: bool,
	clicked: bool,
	doubleClicked: bool,
	tripleClicked: bool,
	rightPressed: bool,
	dragging: bool,
	hovering: bool,
	pasted: bool,
}

ui_flags :: enum u32 {
	NONE = 0,
	CLICKABLE = 1,
	SCROLL_WHEEL_X = 2,
	SCROLL_WHEEL_Y = 4,
	BLOCK_MOUSE = 8,
	HOT_ANIMATION = 16,
	ACTIVE_ANIMATION = 32,
	OVERFLOW_ALLOW_X = 64,
	OVERFLOW_ALLOW_Y = 128,
	CLIP = 256,
	DRAW_BACKGROUND = 512,
	DRAW_FOREGROUND = 1024,
	DRAW_BORDER = 2048,
	DRAW_TEXT = 4096,
	DRAW_PROC = 8192,
	OVERLAY = 65536,
}

MAX_INPUT_CHAR_PER_FRAME :: 64

ui_input_text :: struct {
	count: u8,
	codePoints: array,
}

ui_stack_elt :: struct {
	parent: ^ui_stack_elt,
	_: struct #raw_union {
		box: ^ui_box,
		size: ui_size,
		clip: rect,
	},
}

ui_tag_elt :: struct {
	listElt: list_elt,
	tag: ui_tag,
}

BOX_MAP_BUCKET_COUNT :: 1024

ui_edit_move :: enum u32 {
	NONE = 0,
	CHAR = 1,
	WORD = 2,
	LINE = 3,
}

ui_context :: struct {
	init: bool,
	input: input_state,
	frameCounter: u64,
	frameTime: f64,
	lastFrameDuration: f64,
	frameArena: arena,
	boxPool: pool,
	boxMap: array,
	root: ^ui_box,
	overlay: ^ui_box,
	overlayList: list,
	boxStack: ^ui_stack_elt,
	clipStack: ^ui_stack_elt,
	nextBoxBeforeRules: list,
	nextBoxAfterRules: list,
	nextBoxTags: list,
	z: u32,
	hovered: ^ui_box,
	focus: ^ui_box,
	editCursor: i32,
	editMark: i32,
	editFirstDisplayedChar: i32,
	editCursorBlinkStart: f64,
	editSelectionMode: ui_edit_move,
	editWordSelectionInitialCursor: i32,
	editWordSelectionInitialMark: i32,
	theme: ^ui_theme,
}

ui_text_box_result :: struct {
	changed: bool,
	accepted: bool,
	text: str8,
}

ui_select_popup_info :: struct {
	changed: bool,
	selectedIndex: i32,
	optionCount: i32,
	options: ^str8,
	placeholder: str8,
}

ui_radio_group_info :: struct {
	changed: bool,
	selectedIndex: i32,
	optionCount: i32,
	options: ^str8,
}

@(default_calling_convention="c", link_prefix="oc_")
foreign {
	input_process_event :: proc(arena: ^arena, state: ^input_state, event: ^event) ---
	input_next_frame :: proc(state: ^input_state) ---
	key_down :: proc(state: ^input_state, key: key_code) -> bool ---
	key_press_count :: proc(state: ^input_state, key: key_code) -> u8 ---
	key_release_count :: proc(state: ^input_state, key: key_code) -> u8 ---
	key_repeat_count :: proc(state: ^input_state, key: key_code) -> u8 ---
	key_down_scancode :: proc(state: ^input_state, key: scan_code) -> bool ---
	key_press_count_scancode :: proc(state: ^input_state, key: scan_code) -> u8 ---
	key_release_count_scancode :: proc(state: ^input_state, key: scan_code) -> u8 ---
	key_repeat_count_scancode :: proc(state: ^input_state, key: scan_code) -> u8 ---
	mouse_down :: proc(state: ^input_state, button: mouse_button) -> bool ---
	mouse_pressed :: proc(state: ^input_state, button: mouse_button) -> u8 ---
	mouse_released :: proc(state: ^input_state, button: mouse_button) -> u8 ---
	mouse_clicked :: proc(state: ^input_state, button: mouse_button) -> bool ---
	mouse_double_clicked :: proc(state: ^input_state, button: mouse_button) -> bool ---
	mouse_position :: proc(state: ^input_state) -> vec2 ---
	mouse_delta :: proc(state: ^input_state) -> vec2 ---
	mouse_wheel :: proc(state: ^input_state) -> vec2 ---
	input_text_utf32 :: proc(arena: ^arena, state: ^input_state) -> str32 ---
	input_text_utf8 :: proc(arena: ^arena, state: ^input_state) -> str8 ---
	clipboard_pasted :: proc(state: ^input_state) -> bool ---
	clipboard_pasted_text :: proc(state: ^input_state) -> str8 ---
	key_mods :: proc(state: ^input_state) -> keymod_flags ---
	ui_init :: proc(_context: ^ui_context) ---
	ui_get_context :: proc() -> ^ui_context ---
	ui_set_context :: proc(_context: ^ui_context) ---
	ui_process_event :: proc(event: ^event) ---
	ui_begin_frame :: proc(size: vec2, defaultStyle: ^ui_style, mask: ui_style_mask) ---
	ui_end_frame :: proc() ---
	ui_draw :: proc() ---
	ui_set_theme :: proc(theme: ^ui_theme) ---
	ui_key_make_str8 :: proc(_string: str8) -> ui_key ---
	ui_key_make_path :: proc(path: str8_list) -> ui_key ---
	ui_box_make_str8 :: proc(_string: str8, flags: ui_flags) -> ^ui_box ---
	ui_box_begin_str8 :: proc(_string: str8, flags: ui_flags) -> ^ui_box ---
	ui_box_end :: proc() -> ^ui_box ---
	ui_box_push :: proc(box: ^ui_box) ---
	ui_box_pop :: proc() ---
	ui_box_top :: proc() -> ^ui_box ---
	ui_box_lookup_key :: proc(key: ui_key) -> ^ui_box ---
	ui_box_lookup_str8 :: proc(_string: str8) -> ^ui_box ---
	ui_box_set_draw_proc :: proc(box: ^ui_box, proc: ui_box_draw_proc, data: rawptr) ---
	ui_box_closed :: proc(box: ^ui_box) -> bool ---
	ui_box_set_closed :: proc(box: ^ui_box, closed: bool) ---
	ui_box_active :: proc(box: ^ui_box) -> bool ---
	ui_box_activate :: proc(box: ^ui_box) ---
	ui_box_deactivate :: proc(box: ^ui_box) ---
	ui_box_hot :: proc(box: ^ui_box) -> bool ---
	ui_box_set_hot :: proc(box: ^ui_box, hot: bool) ---
	ui_box_sig :: proc(box: ^ui_box) -> ui_sig ---
	ui_tag_make_str8 :: proc(_string: str8) -> ui_tag ---
	ui_tag_box_str8 :: proc(box: ^ui_box, _string: str8) ---
	ui_tag_next_str8 :: proc(_string: str8) ---
	ui_apply_style_with_mask :: proc(dst: ^ui_style, src: ^ui_style, mask: ui_style_mask) ---
	ui_pattern_push :: proc(arena: ^arena, pattern: ^ui_pattern, selector: ui_selector) ---
	ui_pattern_all :: proc() -> ui_pattern ---
	ui_pattern_owner :: proc() -> ui_pattern ---
	ui_style_next :: proc(style: ^ui_style, mask: ui_style_mask) ---
	ui_style_match_before :: proc(pattern: ui_pattern, style: ^ui_style, mask: ui_style_mask) ---
	ui_style_match_after :: proc(pattern: ui_pattern, style: ^ui_style, mask: ui_style_mask) ---
	ui_label :: proc(label: cstring) -> ui_sig ---
	ui_label_str8 :: proc(label: str8) -> ui_sig ---
	ui_button :: proc(label: cstring) -> ui_sig ---
	ui_checkbox :: proc(name: cstring, checked: ^bool) -> ui_sig ---
	ui_slider :: proc(name: cstring, value: ^f32) -> ^ui_box ---
	ui_scrollbar :: proc(name: cstring, thumbRatio: f32, scrollValue: ^f32) -> ^ui_box ---
	ui_tooltip :: proc(label: cstring) ---
	ui_panel_begin :: proc(name: cstring, flags: ui_flags) ---
	ui_panel_end :: proc() ---
	ui_menu_bar_begin :: proc(name: cstring) ---
	ui_menu_bar_end :: proc() ---
	ui_menu_begin :: proc(label: cstring) ---
	ui_menu_end :: proc() ---
	ui_menu_button :: proc(label: cstring) -> ui_sig ---
	ui_text_box :: proc(name: cstring, arena: ^arena, text: str8) -> ui_text_box_result ---
	ui_select_popup :: proc(name: cstring, info: ^ui_select_popup_info) -> ui_select_popup_info ---
	ui_radio_group :: proc(name: cstring, info: ^ui_radio_group_info) -> ui_radio_group_info ---
}
