package ved
import "base:intrinsics"
import "core:c"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sys/linux"
import "core:sys/unix"
import "core:unicode"
import "core:unicode/utf8"
VedMode :: enum {
    Normal,
    Insert,
}
Ved :: struct {
    buffers:     [dynamic]Buffer,
    current_buf: int,
    size:        winsize,
    mode:        VedMode,
}
ved: Ved = {}
set_cursor :: proc(col: int, row: int) {
    fmt.printf("\x1b[%i;%iH", row, col)
}
set_cursor_block :: proc() {
    fmt.print("\x1b[2 q")
}
set_cursor_line :: proc() {
    fmt.print("\x1b[6 q")
}
hide_cursor :: proc() {
    fmt.print("\x1b[?25l")
}
show_cursor :: proc() {
    fmt.print("\x1b[?25h")
}
Modifier :: enum {
    Control,
    Alt,
}
Modifiers :: bit_set[Modifier]
SpecialKey :: enum {
    None,
    Enter,
    Escape,
    LeftArrow,
    RightArrow,
    UpArrow,
    DownArrow,
}
Key :: struct {
    key_rune:    rune,
    mod:         Modifiers,
    special_key: SpecialKey,
}
read_keys :: proc(keys_buf: ^[dynamic]Key) {
    buf: [128]u8
    start := 0
    read_more := true
    for read_more {
        read_more = false
        n, err := os.read(os.stdin, buf[start:])
        assert(err == 0)
        i := 0
        for i < n + start {
            if buf[i] <= 26 {
                append(keys_buf, Key{key_rune = rune(buf[i] + 'a'), mod = {.Control}})
                i += 1
            } else if buf[i] <= 127 {
                append(keys_buf, Key{key_rune = rune(buf[i])})
                i += 1
            } else {
                run, size := utf8.decode_rune_in_bytes(buf[i:])
                if size == 0 {
                    start = i
                    read_more = true
                    break
                } else {
                    append(keys_buf, Key{key_rune = rune(buf[i]), mod = {}})
                }
            }
        }
    }
}
main :: proc() {
    ved.buffers = make([dynamic]Buffer)
    ved.size = terminal_size()
    args: []string = os.args[1:]
    if len(args) == 0 {
        os.exit(1)
    }
    if !os.exists(args[0]) {
        os.exit(1)
    }
    file, ok := os.read_entire_file_from_filename(args[0])
    if !ok {
        os.exit(1)
    }
    file_str := (strings.clone_from_bytes(file))
    file_runes_slice := utf8.string_to_runes(file_str)
    file_runes := make_dynamic_array_len_cap([dynamic]rune, 0, len(file_runes_slice))
    append_elems(&file_runes, ..file_runes_slice)
    delete(file)
    delete(file_str)
    delete(file_runes_slice)
    buf := init_buffer(file_runes, args[0])
    append(&ved.buffers, buf)
    raw := termios{}
    res := tcgetattr(STDIN_FILENO, &raw)
    cooked := raw
    cooked.c_lflag &~= (c.uint(c_lflag.ICANON) | c.uint(c_lflag.ECHO))
    cfmakeraw(&cooked)
    res = tcsetattr(STDIN_FILENO, TCSANOW, &cooked)
    signal(c.int(linux.Signal.SIGWINCH), sighandler_t(size_changed))
    render_buf := make([]u8, ved.size.ws_row * ved.size.ws_col * size_of(rune))
    keys_buf := make([dynamic]Key)

    for {
        buffer := &ved.buffers[ved.current_buf]
        size := ved.size
        set_cursor(0, 0)
        hide_cursor()
        slice.zero(render_buf)
        rendered := 0
        for i in 0 ..< size.ws_row - 1 {
            linei := buffer.scroll_cursor.row + int(i)
            if linei < len(buffer.lines) {
                line := buffer.lines[linei]
                line_start := line.start + buffer.scroll_cursor.col
                line_end := clamp((line.end - line_start), 0, int(size.ws_col)) + line_start
                line_text :=
                    line_end > line_start ? buffer.data[line_start:line_end] : buffer.data[0:0]
                for r in line_text {
                    if (unicode.is_space(r)) {
                        rendered += len(fmt.bprint(render_buf[rendered:], ' '))
                    } else {
                        rendered += len(fmt.bprint(render_buf[rendered:], r))
                    }

                }
                for i in 0 ..< int(size.ws_col) - len(line_text) {
                    rendered += len(fmt.bprint(render_buf[rendered:], ' '))
                }
            } else {
                for i in 0 ..< size.ws_col {
                    rendered += len(fmt.bprint(render_buf[rendered:], ' '))
                }
            }
        }
        //fmt.eprintln(render_buf)
        os.write(os.stdout, render_buf)
        set_cursor(0, int(ved.size.ws_row))
        fmt.print("                                  ")
        set_cursor(0, int(ved.size.ws_row))
        fmt.printf("%s:%i:%i", buffer.file_name, buffer.cursor.row, buffer.cursor.col)
        current_line := buffer.lines[buffer.cursor.row]
        cur_line_len := current_line.end - current_line.start
        cur_cursor := min(buffer.cursor.col, cur_line_len - 1)
        set_cursor(
            (cur_cursor - buffer.scroll_cursor.col) + 1,
            buffer.cursor.row - buffer.scroll_cursor.row + 1,
        )
        show_cursor()
        clear(&keys_buf)
        //buf:[32]u8
        //os.read(os.stdin, buf[:])
        //fmt.println(buf)
        //if true { return }
        read_keys(&keys_buf)
        if ved.mode == VedMode.Normal {
            for k in keys_buf {
                switch k.key_rune {
                case 'h':
                    buf_cursor_col(buffer, -1)
                case 'j':
                    buf_cursor_row(buffer, 1)
                case 'k':
                    buf_cursor_row(buffer, -1)
                case 'l':
                    buf_cursor_col(buffer, 1)
                case 'i':
                    set_cursor_line()
                    ved.mode = VedMode.Insert
                case 'q':
                    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
                    return
                }
            }
        } else if ved.mode == VedMode.Insert {
            for k in keys_buf {
                switch k.key_rune {
                // ESCAPE
                case '\x1b':
                    set_cursor_block()
                    ved.mode = VedMode.Normal
                    break
                // BACKSPACE
                case '\x7f':
                    buf_remove(buffer)
                case 'n':
                    if Modifier.Control in k.mod {
                        buf_insert(buffer, '\n')
                        buf_cursor_col(buffer, -1)
                        buf_cursor_row(buffer, 1)
                    } else {
                        buf_insert(buffer, 'n')
                    }
                case:
                    buf_insert(buffer, k.key_rune)

                }
            }
        }
    }
}
