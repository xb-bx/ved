package ved
import "base:intrinsics"
import "core:c"
import "core:fmt"
import "core:log"
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
    Search,
}
Ved :: struct {
    buffers:              [dynamic]Buffer,
    current_buf:          int,
    size:                 winsize,
    mode:                 VedMode,
    search:               SearchBuffer,
    count:                int,
    current_command_str:  strings.Builder,
    current_command_keys: [dynamic]Key,
    command_data:         strings.Builder,
    current_command:      Maybe(Command),
    commands:             [dynamic]Command,
    filtered_commands:    [dynamic]Command,
    last_command:         Maybe(LastCommand),
    global_marks:         map[rune]Mark,
}
filter :: proc(d: ^[dynamic]$T, data: $D, fltr: proc(data: D, elem: ^T) -> bool) {
    i := 0
    for i < len(d) {
        if !fltr(data, &d[i]) {
            ordered_remove(d, i)
            i -= 1
        }
        i += 1
    }
}
key_eq :: proc(left: Key, right: Key) -> bool {
    return(
        left.key_rune == right.key_rune &&
        left.mod == right.mod &&
        left.special_key == right.special_key \
    )
}
filter_commands :: proc(ved: ^Ved) {
    if len(ved.filtered_commands) == 0 do append(&ved.filtered_commands, ..ved.commands[:])
    cmd_filter :: proc(ved: ^Ved, elem: ^Command) -> bool {
        lasti := len(ved.current_command_keys) - 1
        if len(elem.binding) < len(ved.current_command_keys) {
            return false
        } else if key_eq(elem.binding[lasti], ved.current_command_keys[lasti]) {
            return true
        }
        return false
    }
    last_key := ved.current_command_keys[len(ved.current_command_keys) - 1]
    filter(&ved.filtered_commands, ved, cmd_filter)
}
ved: Ved = {}
set_inverse_color :: proc() {
    fmt.printf("\x1b[7m")
}
set_normal_color :: proc() {
    fmt.printf("\x1b[27m")
}
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
                ch := buf[i] + 'a'
                special := SpecialKey.None
                if ch == 'n' do special = .Enter
                append(keys_buf, Key{key_rune = rune(ch), mod = {.Control}, special_key = special})
                i += 1
            } else if buf[i] == 27 && i + 3 <= n + start {
                assert(buf[i + 1] == 91)
                switch buf[i + 2] {
                case 68:
                    append(keys_buf, Key{key_rune = '\x1b', special_key = SpecialKey.LeftArrow})
                case 67:
                    append(keys_buf, Key{key_rune = '\x1b', special_key = SpecialKey.RightArrow})
                case 66:
                    append(keys_buf, Key{key_rune = '\x1b', special_key = SpecialKey.DownArrow})
                case 65:
                    append(keys_buf, Key{key_rune = '\x1b', special_key = SpecialKey.UpArrow})
                case:
                    panic("unknown escape")
                }
                i += 3
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
line_of_position :: proc(lines: []Line, pos: int) -> int {
    if len(lines) == 0 {return -1}
    if lines[0].start <= pos && lines[0].end >= pos {return 0}
    left, mid, right := 0, len(lines) / 2, len(lines) - 1
    if lines[mid].start <= pos && lines[mid].end >= pos {
        return mid
    } else if lines[mid].start > pos {
        return line_of_position(lines[0:mid], pos)
    } else {
        return mid + line_of_position(lines[mid:right + 1], pos)
    }
}
ved_set_buf :: proc(ved: ^Ved, buf: ^Buffer) {
    for &buffer, i in ved.buffers {
        if buf == &buffer {
            ved.current_buf = i
            break
        }
    }
}
ved_update_last_command :: proc(ved: ^Ved) {
    if ved.current_command != nil && !ved.current_command.(Command).repeatable do return
    if ved.last_command != nil do delete(ved.last_command.(LastCommand).input)
    ved.last_command = LastCommand {
        command = ved.current_command.(Command),
        input   = strings.clone(strings.to_string(ved.command_data)),
        count   = ved.count,
    }
}
@(private)
ved_init :: proc(ved: ^Ved) {
    ved.buffers = make([dynamic]Buffer)
    ved.size = terminal_size()
    ved.search = SearchBuffer {
        search_results = make([dynamic]SearchResult),
    }
    num := 0x123 + 321 + 0o1231
    strings.builder_init(&ved.current_command_str)
    ved.current_command_keys = make([dynamic]Key)
    ved.filtered_commands = make([dynamic]Command)
    ved.commands = make([dynamic]Command)
    add_default_commands(ved)
    strings.builder_init(&ved.search.search_pattern)

}
main :: proc() {
    ved_init(&ved)
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
    file_sb: strings.Builder = {}
    strings.builder_init(&file_sb)
    strings.write_bytes(&file_sb, file)
    delete(file)
    buf := buf_init(&file_sb, args[0])
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
        buffer.width = int(ved.size.ws_col)
        buffer.height = int(ved.size.ws_row) - 2
        size := ved.size
        set_cursor(0, 0)
        hide_cursor()
        slice.zero(render_buf)
        rendered := 0
        for i in 0 ..< buffer.height {
            linei := buffer.scroll_cursor.row + int(i)
            if linei < len(buffer.lines) {
                line := buffer.lines[linei]
                line_start := line.start + buffer.scroll_cursor.col
                line_end := clamp((line.len), 0, int(size.ws_col)) + line_start
                line_text :=
                    line_end > line_start ? buf_slice_to_string(buffer, line_start, line_end) : ""
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
        os.write(os.stdout, render_buf)
        set_cursor(0, int(ved.size.ws_row) - 1)
        fmt.print("                                  ")
        set_cursor(0, int(ved.size.ws_row) - 1)
        n := fmt.printf("%s:%i:%i", buffer.file_name, buffer.cursor.row, buffer.cursor.col)
        current_cmd := strings.to_string(ved.current_command_str)
        if len(current_cmd) != 0 || ved.count != 0 {
            cmdstr :=
                ved.count == 0 \
                ? strings.clone(current_cmd) \
                : fmt.aprintf("%i%s", ved.count, current_cmd)
            defer delete(cmdstr)
            set_cursor(int(ved.size.ws_col) - len(cmdstr), int(ved.size.ws_row) - 1)
            fmt.print(cmdstr)
        } else {
            for i in 0 ..< int(ved.size.ws_col) - n {
                fmt.print(' ')
            }
        }

        current_line := buffer.lines[buffer.cursor.row]
        cur_cursor := min(buffer.cursor.col, current_line.len - 1)
        term_col := (cur_cursor - buffer.scroll_cursor.col) + 1
        term_row := clamp(buffer.cursor.row - buffer.scroll_cursor.row + 1, 0, buffer.height)
        for result in ved.search.search_results {
            line_index := line_of_position(buffer.lines[:], result.start)
            if line_index < buffer.scroll_cursor.row ||
               line_index >= buffer.scroll_cursor.row + buffer.height {
                continue
            }
            line := buffer.lines[line_index]
            col := result.start - line.start + 1
            row := line_index - buffer.scroll_cursor.row + 1
            set_cursor(col, row)
            fmt.print("\x1b[2m")
            text := buf_slice_to_string(buffer, result.start, result.end)
            for r in text {
                fmt.print(r)
            }
            fmt.print("\x1b[22m")
        }
        set_cursor(term_col, term_row)
        if ved.mode == .Search {
            set_cursor(0, int(ved.size.ws_row))
            fmt.print("/")
            fmt.print(strings.to_string(ved.search.search_pattern))
            for i in 0 ..< int(ved.size.ws_col) -
                strings.builder_len(ved.search.search_pattern) -
                1 {
                fmt.print(" ")
            }
            set_cursor(2 + ved.search.position, int(ved.size.ws_row))

        }
        show_cursor()
        clear(&keys_buf)
        read_keys(&keys_buf)
        switch ved.mode {
        case .Search:
            pattern := &ved.search.search_pattern
            for k in keys_buf {
                if k.special_key != .None {
                    #partial switch k.special_key {
                    case .LeftArrow:
                        ved.search.position = clamp(
                            ved.search.position - 1,
                            0,
                            strings.builder_len(pattern^),
                        )
                    case .RightArrow:
                        ved.search.position = clamp(
                            ved.search.position + 1,
                            0,
                            strings.builder_len(pattern^),
                        )
                    case .Enter, .Escape:
                        ved.mode = .Normal
                        set_cursor_block()
                    }
                } else {
                    switch k.key_rune {
                    case '\x1b':
                        set_cursor_block()
                        ved.mode = .Normal
                    case '\x7f':
                        if ved.search.position > 0 {
                            ordered_remove(&pattern.buf, ved.search.position - 1)
                            ved.search.position -= 1
                        }
                        search_in_buf(&ved.search, buffer)
                    case:
                        if ved.search.position == strings.builder_len(pattern^) {
                            fmt.sbprint(pattern, k.key_rune)

                        } else {
                            bytes, n := utf8.encode_rune(k.key_rune)
                            inject_at(&pattern.buf, ved.search.position, ..bytes[:n])
                        }
                        ved.search.position += 1
                        search_in_buf(&ved.search, buffer)
                    }
                }
            }
        case .Normal:
            for k in keys_buf {
                if ved.current_command != nil {
                    fmt.sbprint(&ved.current_command_str, k.key_rune)
                    fmt.sbprint(&ved.command_data, k.key_rune)
                    state := ved.current_command.(Command).action(
                        &ved,
                        buffer,
                        strings.to_string(ved.command_data),
                    )
                    if state == .CommandFinished {
                        ved_update_last_command(&ved)
                        strings.builder_reset(&ved.current_command_str)
                        ved.count = 0
                        strings.builder_reset(&ved.command_data)
                        ved.current_command = nil
                    }
                } else if strings.builder_len(ved.current_command_str) == 0 {
                    reset_count := true
                    count := ved.count == 0 ? 1 : ved.count
                    if k.special_key != .None {
                        switch k.special_key {
                        case .LeftArrow:
                            buf_cursor_col(buffer, -1 * count)
                        case .DownArrow, .Enter:
                            buf_cursor_row(buffer, 1 * count)
                        case .UpArrow:
                            buf_cursor_row(buffer, -1 * count)
                        case .RightArrow:
                            buf_cursor_col(buffer, 1 * count)
                        case .Escape, .None:
                        }
                    } else {
                        switch k.key_rune {
                        case '0' ..= '9':
                            ved.count *= 10
                            ved.count += int(k.key_rune) - int('0')
                            reset_count = false
                        case '.':
                            if ved.last_command != nil {
                                last := ved.last_command.(LastCommand)
                                ved.count = last.count
                                last.command.action(&ved, buffer, last.input)
                                ved.count = 0
                            }
                        case 'N':
                            if len(ved.search.search_results) > 0 {
                                next := -1
                                for res, i in ved.search.search_results {
                                    if res.start >=
                                       buffer.lines[buffer.cursor.row].start + buffer.cursor.col {
                                        next = i - 1
                                        break
                                    }
                                }

                                res := SearchResult{}
                                if next == len(ved.search.search_results) {
                                    res = ved.search.search_results[0]
                                } else if next == -1 {
                                    res =
                                        ved.search.search_results[len(ved.search.search_results) - 1]
                                } else {
                                    res = ved.search.search_results[next]
                                }
                                row := line_of_position(buffer.lines[:], res.start)
                                buf_cursor_row(buffer, row - buffer.cursor.row)
                                col := res.start - buffer.lines[row].start
                                buf_cursor_col(buffer, -99999)
                                buf_cursor_col(buffer, col)
                            }
                        case 'n':
                            if len(ved.search.search_results) > 0 {
                                next := -1
                                for res, i in ved.search.search_results {
                                    if res.start >
                                       buffer.lines[buffer.cursor.row].start + buffer.cursor.col {
                                        next = i
                                        break
                                    }
                                }
                                res := SearchResult{}
                                if next == len(ved.search.search_results) || next == -1 {
                                    res = ved.search.search_results[0]
                                } else {
                                    res = ved.search.search_results[next]
                                }
                                row := line_of_position(buffer.lines[:], res.start)
                                buf_cursor_row(buffer, row - buffer.cursor.row)
                                col := res.start - buffer.lines[row].start
                                buf_cursor_col(buffer, -99999)
                                buf_cursor_col(buffer, col)
                            }
                        case 'i':
                            set_cursor_line()
                            ved.mode = VedMode.Insert
                        case 'a':
                            set_cursor_line()
                            ved.mode = VedMode.Insert
                            buf_cursor_col(buffer, 1)
                        case 'o':
                            set_cursor_line()
                            ved.mode = VedMode.Insert
                            line_end := buffer.lines[buffer.cursor.row].rune_end
                            buf_cursor_col(buffer, line_end - buffer.cursor.col + 1)
                            sb_insert_rune(buffer.data, line_end, '\n')
                            split_into_lines(buffer.data, &buffer.lines)
                            buf_cursor_row(buffer, 1)
                            buf_cursor_col(buffer, -1)
                        case '$':
                            buf_cursor_col(
                                buffer,
                                buffer.lines[buffer.cursor.row].end - buffer.cursor.col,
                            )
                        case '^':
                            line := buffer.lines[buffer.cursor.row]
                            for c, i in buf_cur_line_string(buffer) {
                                if !unicode.is_space(c) {
                                    buf_cursor_col(buffer, -99999)
                                    buf_cursor_col(buffer, i)
                                    break
                                }
                            }
                        case 'q':
                            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
                            return
                        case '/':
                            set_cursor_line()
                            ved.mode = VedMode.Search
                        case:
                            fmt.sbprint(&ved.current_command_str, k.key_rune)
                            append(&ved.current_command_keys, k)
                            filter_commands(&ved)
                            reset_count = false
                            if len(ved.filtered_commands) == 0 {
                                strings.builder_reset(&ved.current_command_str)
                                clear(&ved.current_command_keys)
                            } else if len(ved.filtered_commands) == 1 &&
                               len(ved.filtered_commands[0].binding) ==
                                   len(ved.current_command_keys) {
                                ved.current_command = ved.filtered_commands[0]
                                clear(&ved.current_command_keys)
                                clear(&ved.filtered_commands)
                                state := ved.current_command.(Command).action(
                                    &ved,
                                    buffer,
                                    strings.to_string(ved.command_data),
                                )
                                if state == .CommandFinished {
                                    ved_update_last_command(&ved)
                                    strings.builder_reset(&ved.current_command_str)
                                    strings.builder_reset(&ved.command_data)
                                    reset_count = true
                                    ved.current_command = nil
                                }
                            }

                        }
                    }
                    if reset_count do ved.count = 0
                } else if len(ved.filtered_commands) != 0 {
                    fmt.sbprint(&ved.current_command_str, k.key_rune)
                    append(&ved.current_command_keys, k)
                    filter_commands(&ved)
                    if len(ved.filtered_commands) == 0 {
                        strings.builder_reset(&ved.current_command_str)
                        clear(&ved.current_command_keys)
                    } else if len(ved.filtered_commands) == 1 {
                        ved.current_command = ved.filtered_commands[0]
                        clear(&ved.current_command_keys)
                        clear(&ved.filtered_commands)
                        state := ved.current_command.(Command).action(
                            &ved,
                            buffer,
                            strings.to_string(ved.command_data),
                        )
                        if state == .CommandFinished {
                            ved_update_last_command(&ved)
                            strings.builder_reset(&ved.current_command_str)
                            strings.builder_reset(&ved.command_data)
                            ved.count = 0
                            ved.current_command = nil
                        }
                    }
                }
            }
        case .Insert:
            for k in keys_buf {
                if k.special_key != .None {
                    switch k.special_key {
                    case .LeftArrow:
                        buf_cursor_col(buffer, -1)
                    case .DownArrow:
                        buf_cursor_row(buffer, 1)
                    case .UpArrow:
                        buf_cursor_row(buffer, -1)
                    case .RightArrow:
                        buf_cursor_col(buffer, 1)
                    case .Enter:
                        buf_insert(buffer, '\n')
                        buf_cursor_col(buffer, -999)
                        buf_cursor_row(buffer, 1)
                    case .Escape:
                        set_cursor_block()
                        ved.mode = VedMode.Normal
                        break
                    case .None:
                    }
                } else {
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
                        buf_insert(buffer, 'n')
                    case:
                        buf_insert(buffer, k.key_rune)

                    }

                }
            }
        }
    }
}
