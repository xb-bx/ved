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

Ved :: struct {
    buffers: [dynamic]Buffer,
    current_buf: int,
    size: winsize,
}
ved: Ved = {}
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
