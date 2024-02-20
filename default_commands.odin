package ved
import "core:log"
import "core:unicode/utf8"
import "core:strings"

find_next :: proc(ved: ^Ved, buf: ^Buffer, read: string) -> CommandState {
    if len(read) == 0 {
        return .CommandReadChar
    }
    line := buf.lines[buf.cursor.row]
    line_str := buf_line_as_string(buf, line)
    run, s := utf8.decode_rune_in_string(read)
    if s <= 0 {
        return .CommandFinished
    }
    orig := clamp(0, buf.cursor.col, line.len)
    orig_off := utf8.rune_offset(line_str, orig)
    r, orig_size := utf8.decode_rune(line_str[orig:])
    off := orig_off + strings.index_rune(line_str[orig_off + orig_size:], run)
    off = pos_of_byte_offset(line_str, off) + 1
    buf_cursor_col(buf, off - orig)
    return .CommandFinished
}
times_todo :: proc(ved: ^Ved) -> int {
    return ved.count == 0 ? 1 : ved.count
}
add_default_commands :: proc(ved: ^Ved) {
    append(&ved.commands, Command {
        binding = binding_from_chars("f"),
        action = find_next,
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("gg"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { buf_cursor_row(buf, -999999999999); buf_cursor_row(buf, ved.count); buf_cursor_col(buf, -9999999999); return .CommandFinished },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("G"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { buf_cursor_row(buf, 999999999999); buf_cursor_col(buf, -9999999999); return .CommandFinished },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("h"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { buf_cursor_col(buf, -1 * times_todo(ved)); return .CommandFinished },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("j"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { buf_cursor_row(buf, 1 * times_todo(ved)); return .CommandFinished },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("l"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { buf_cursor_col(buf, 1 * times_todo(ved)); return .CommandFinished },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("k"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { buf_cursor_row(buf, -1 * times_todo(ved)); return .CommandFinished },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("dd"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { for _ in 0..<times_todo(ved) do buf_remove_range(buf, buf.lines[buf.cursor.row].start, buf.lines[buf.cursor.row].end + 1) ; return .CommandFinished },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("x"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState 
        {
            count := times_todo(ved)
            line := buf.lines[buf.cursor.row]
            start := clamp(buf.cursor.col, 0, line.len)
            end := start + clamp(count, 0, line.len - start)
            if end == line.len do end -= 1 // Ensure we dont remove '\n'
            buf_remove_range(buf, line.start + start, line.start + end)
            return .CommandFinished
        },
    })
    append(&ved.commands, Command {
        binding = binding_from_chars("D"),
        action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState {
            line := buf.lines[buf.cursor.row]
            buf_remove_range(buf, line.start + buf.cursor.col, line.end)
            return .CommandFinished
        },
    })
}
