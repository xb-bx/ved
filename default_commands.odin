package ved
import "core:log"
import "core:unicode/utf8"
import "core:strings"
all_indexes_in_string :: proc(str: string, c: rune) -> []int {
    res := make([dynamic]int)
    str := str
    prev_off := 0
    for {
        off := strings.index_rune(str, c)
        if off == -1 do break 
        //index := pos_of_byte_offset(str, off)
        append(&res, prev_off + off)
        prev_off += off + utf8.rune_size(c)
        str = str[off + utf8.rune_size(c):]
        if len(str) == 0 do break
    }
    return res[:]
}
find_next :: proc(ved: ^Ved, buf: ^Buffer, read: string) -> CommandState {
    if len(read) == 0 {
        return .CommandReadChar
    }
    count := times_todo(ved)
    line := buf.lines[buf.cursor.row]
    line_str := buf_line_as_string(buf, line)
    run, s := utf8.decode_rune_in_string(read)
    if s <= 0 {
        return .CommandFinished
    }
    orig := clamp(0, buf.cursor.col, line.len)
    orig_off := utf8.rune_offset(line_str, orig)
    r, orig_size := utf8.decode_rune(line_str[orig:])

    indexes := all_indexes_in_string(line_str[orig_off + orig_size:], run)
    defer delete(indexes)
    if len(indexes) == 0 {
        return .CommandFinished
    }
    index := clamp(count - 1, 0, len(indexes))
    
    off := orig_off + indexes[index]
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
        binding = binding_from_chars("h"), action = proc(ved: ^Ved, buf: ^Buffer, _: string) -> CommandState { buf_cursor_col(buf, -1 * times_todo(ved)); return .CommandFinished },
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
    append(&ved.commands, Command {
        binding = binding_from_chars("dt"),
        action = proc(ved: ^Ved, buf: ^Buffer, c: string) -> CommandState {
            if len(c) < 1 { return .CommandReadChar }
            line := buf.lines[buf.cursor.row]
            line_str := buf_line_as_string(buf, line)
            run, s := utf8.decode_rune_in_string(c)
            if s <= 0 {
                return .CommandFinished
            }
            orig := clamp(0, buf.cursor.col, line.len)
            orig_off := utf8.rune_offset(line_str, orig)
            r, orig_size := utf8.decode_rune(line_str[orig:])
            if orig_size <= 0 { return .CommandFinished } 
            indexes := all_indexes_in_string(line_str[orig_off + orig_size:], run)
            defer delete(indexes)
            if len(indexes) == 0 { return .CommandFinished } 
            index := clamp(times_todo(ved) - 1, 0, len(indexes))
            index = indexes[index]
            off := orig_off + index
            buf_remove_range(buf, orig_off + line.start, off + orig_size + line.start)
            return .CommandFinished
        },
    })
}
