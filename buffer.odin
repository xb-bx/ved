package ved
Line :: struct {
    start: int,
    end: int,
}
Cursor :: struct {
    col: int,
    row: int,
}
Buffer :: struct {
    data: [dynamic]rune,
    lines: [dynamic]Line,
    file_name: string,
    cursor: Cursor,
    scroll_cursor: Cursor,
}
init_buffer :: proc(data: [dynamic]rune, file_name: string) -> Buffer {
    lines := make([dynamic]Line)
    split_into_lines(data, &lines)
    return Buffer { data = data, lines = lines, file_name = file_name }
}
split_into_lines :: proc(data: [dynamic]rune, lines: ^[dynamic]Line) {
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
buf_insert :: proc(buf: ^Buffer, r: rune) {
    line := buf.lines[buf.cursor.row]
    line_len := line.end - line.start
    buf.cursor.col = clamp(buf.cursor.col, 0, line_len - 1)
    inject_at(&buf.data, line.start + buf.cursor.col, r) 
    split_into_lines(buf.data, &buf.lines)
    buf.cursor.col += 1
}
buf_remove :: proc(buf: ^Buffer) {
    line := buf.lines[buf.cursor.row]
    line_len := line.end - line.start
    buf.cursor.col = clamp(buf.cursor.col, 0, line_len - 1)
    if buf.cursor.col == 0 {
        if buf.cursor.row == 0 {
            return
        } else {
            prev_line := buf.lines[buf.cursor.row - 1]
            prev_line_len := prev_line.end - prev_line.start
            ordered_remove(&buf.data, line.start - 1) 
            split_into_lines(buf.data, &buf.lines)
            buf_cursor_row(buf, -1)
            buf_cursor_col(buf, prev_line_len)
        }

    }
    else {
        buf.cursor.col = clamp(buf.cursor.col - 1, 0, line_len - 1)
        ordered_remove(&buf.data, line.start + buf.cursor.col)
        split_into_lines(buf.data, &buf.lines)
    }

}
