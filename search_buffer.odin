package ved
import "core:strings"
import "core:slice"
import "core:unicode/utf8"
SearchResult :: struct {
    start: int,
    end:   int,
}
SearchBuffer :: struct {
    position:       int,
    search_pattern: strings.Builder,
    search_results: [dynamic]SearchResult,
}
has_prefix :: proc(buf: []rune, prefix: []rune) -> bool {
    if len(prefix) > len(buf) {
        return false
    }
    return slice.equal(buf[:len(prefix)], prefix)
}
search_in_buf :: proc(search: ^SearchBuffer, buf: ^Buffer) {
    clear(&search.search_results)
    if len(buf.data) == 0 { return }
    //rawbuffer := slice.bytes_from_ptr(rawptr(&buf.data[0]), len(buf.data) * size_of(rune))
    search_runes := utf8.string_to_runes(strings.to_string(search.search_pattern))
    defer delete(search_runes)
    i := 0
    for i < len(buf.data) - len(search_runes) {
        if has_prefix(buf.data[i:], search_runes) {
            append(&search.search_results, SearchResult {start = i, end = i + len(search_runes)})
            i += len(search_runes)
        } else {
            i += 1
        }
    }
}
