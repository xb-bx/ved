package ved
import "core:strings"
import "core:unicode/utf8"
CommandState :: enum {
    CommandReadChar,
    CommandFinished,
}
CommandAction :: proc(ved: ^Ved, buf: ^Buffer, read: string) -> CommandState
Command :: struct {
    binding: []Key,
    action:  CommandAction,
}
binding_from_chars :: proc(chars: string) -> []Key {
    keys := make([dynamic]Key)
    for c in chars {
        append(&keys, Key{key_rune = c})
    }
    return keys[:]
}
