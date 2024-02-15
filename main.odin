package ved
import "core:fmt"
import "core:c"
import "core:sys/linux"
import "core:sys/unix"
import "core:os"
import "base:intrinsics"
import "core:strings"
import "core:unicode/utf8"
import "core:slice"

foreign import libc "system:c"
c_lflag :: enum {
    ISIG = 0o0000001,   
    ICANON = 0o0000002,
    XCASE = 0o0000004,
    ECHO = 0o0000010,
    ECHOE = 0o0000020,
    ECHOK = 0o0000040,
    ECHONL = 0o0000100,
    NOFLSH = 0o0000200, 
    TOSTOP = 0o0000400, 
    ECHOCTL = 0o0001000,
    ECHOPRT = 0o0002000,
    ECHOKE = 0o0004000, 
    FLUSHO = 0o0010000,
    PENDIN = 0o0040000,
    IEXTEN = 0o0100000,
    EXTPROC = 0o0200000,
}
tcflag_t :: c.uint
speed_t :: c.uint
cc_t :: c.uchar
NCCS :: 32
termios :: struct {
    c_iflag: tcflag_t,
    c_oflag: tcflag_t,
    c_cflag: tcflag_t,
    c_lflag: tcflag_t,
    c_line: cc_t,
    c_cc: [NCCS]cc_t,
    c_ispeed: speed_t,
    c_ospeed: speed_t,
}
TCSANOW :: 	0
TCSADRAIN :: 1
TCSAFLUSH :: 2
sighandler_t :: proc() -> c.int
foreign libc {
    tcgetattr :: proc (fd: c.int, termios: ^termios) -> c.int ---
    tcsetattr :: proc (fd: c.int, optional_actions: c.int, termios: ^termios) -> c.int ---
    signal :: proc(sig: c.int, handler: sighandler_t) -> sighandler_t ---
}
STDIN_FILENO :: 0
winsize :: struct {
    ws_row: c.ushort,
    ws_col: c.ushort,
    ws_xpixel: c.ushort,
    ws_ypixel: c.ushort,
}
size_changed :: proc "c" () -> c.int {
    context = {}
    ved.size = terminal_size()
    return 0;
}
TIOCGWINSZ :: 0x5413
terminal_size :: proc() -> winsize {
    res := winsize{}
    intrinsics.syscall(linux.SYS_ioctl, STDIN_FILENO, TIOCGWINSZ, uintptr(&res))
    return res
}
Line :: struct {
    start: int,
    end: int,
}
Cursor :: struct {
    col: int,
    row: int,
}
Buffer :: struct {
    data: []rune,
    lines: [dynamic]Line,
    file_name: string,
    cursor: Cursor,
    scroll_cursor: Cursor,
}
init_buffer :: proc(data: []rune, file_name: string) -> Buffer {
    lines := make([dynamic]Line)
    split_into_lines(data, &lines)
    return Buffer { data = data, lines = lines, file_name = file_name }
}
split_into_lines :: proc(data: []rune, lines: ^[dynamic]Line) {
    clear(lines)
    append(lines, Line{})
    line := &lines[0]
    for b,i  in data {
        if b == '\n' {
            line.end = i
            append(lines, Line { start = i + 1, end = i + 1 })
            line = &lines[len(lines) - 1]
        }
    }
    if len(lines) != 1 {
        unordered_remove(lines, len(lines) - 1) 
    }
}
Ved :: struct {
    buffers: [dynamic]Buffer,
    current_buf: int,
    size: winsize,
}
ved: Ved = {}
buf_cursor_col :: proc(buf: ^Buffer, dir: int) {
    line := buf.lines[buf.cursor.row]
    line_len := line.end - line.start
    if buf.cursor.col >= line_len { 
        if dir > 0 {
            return
        } else {
            buf.cursor.col = clamp(line_len - 1 + dir, 0, line_len)
        }
    }
    else {
        col := clamp(buf.cursor.col + dir, 0, line_len - 1)
        buf.cursor.col = col
        if buf.cursor.col - buf.scroll_cursor.col > int(ved.size.ws_col) {
            buf.scroll_cursor.col += 1
        } else if buf.cursor.col - buf.scroll_cursor.col < 0 {
            buf.scroll_cursor.col -= 1
        }
    }
}
buf_cursor_row :: proc(buf: ^Buffer, dir: int) {
    row := clamp(buf.cursor.row + dir, 0, len(buf.lines) - 1)
    buf.cursor.row = row
    if buf.cursor.row - buf.scroll_cursor.row >= int(ved.size.ws_row) {
        buf.scroll_cursor.row += 1
    }
    else if buf.cursor.row - buf.scroll_cursor.row <= 0 {
        buf.scroll_cursor.row -= 1
    }
    buf.scroll_cursor.row = clamp(buf.scroll_cursor.row, 0, len(buf.lines))
    line := buf.lines[row]
    if line.end - line.start < buf.scroll_cursor.col {
        buf.scroll_cursor.col = (line.end - line.start) / 2
        buf.cursor.col = line.end - 1
    }
}
set_cursor :: proc(col: int, row: int) {
    fmt.printf("\x1b[%i;%iH", row, col);
}
hide_cursor :: proc() {
    fmt.print("\x1b[?25l")
}
show_cursor :: proc() {
    fmt.print("\x1b[?25h")
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
    file_runes := utf8.string_to_runes(file_str)
    delete(file)
    delete(file_str)
    buf := init_buffer(file_runes, args[0])
    append(&ved.buffers, buf)
    old_state := termios{}
    res := tcgetattr(STDIN_FILENO, &old_state)
    old_state.c_lflag &~= (c.uint(c_lflag.ICANON) | c.uint(c_lflag.ECHO));
    res = tcsetattr(STDIN_FILENO, TCSANOW, &old_state);
    signal(c.int(linux.Signal.SIGWINCH), sighandler_t(size_changed))
    render_buf:= make([]u8, ved.size.ws_row * ved.size.ws_col * size_of(rune))
    for {
        buffer := &ved.buffers[ved.current_buf]
        size := ved.size
        set_cursor(0,0)
        hide_cursor()
        slice.zero(render_buf)
        rendered := 0
        for i in 0..<size.ws_row - 1 {
            linei := buffer.scroll_cursor.row + int(i) 
            if linei < len(buffer.lines) {
                line := buffer.lines[linei] 
                line_start := line.start + buffer.scroll_cursor.col
                line_end := clamp((line.end - line_start), 0, int(size.ws_col)) + line_start
                line_text := line_end > line_start ? buffer.data[line_start:line_end] : buffer.data[0:0]
                for r in line_text {
                    rendered += len(fmt.bprint(render_buf[rendered:], r))
                    
                }
                for i in 0..<int(size.ws_col) - len(line_text) {
                    rendered += len(fmt.bprint(render_buf[rendered:], ' '))
                }
            }
            else {
                for i in 0..<size.ws_col {
                    rendered += len(fmt.bprint(render_buf[rendered:], ' '))
                }
            }
            if i != size.ws_row - 1 {
                render_buf[rendered] = '\n'
                rendered += 1
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
        set_cursor((cur_cursor - buffer.scroll_cursor.col) + 1, buffer.cursor.row - buffer.scroll_cursor.row + 1)
        show_cursor()

        read_buf: [32]u8
        n, err := os.read(os.stdin, read_buf[:])
        assert(err == 0)
        for k in read_buf[:n] {
            switch k {
                case 'h':
                    buf_cursor_col(buffer, -1)
                case 'j':
                    buf_cursor_row(buffer, 1)
                case 'k':
                    buf_cursor_row(buffer, -1)
                case 'l':
                    buf_cursor_col(buffer, 1)
            }
        }
    }
}
