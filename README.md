# Stack Machine in Lua (SMiL)

SMiL is an implementation of the ideas presented in Eduardo Ochs's paper 
["Bootstrapping a Forth in 40 lines of Lua code"](http://angg.twu.net/miniforth-article.html).
However, this implementation deviates from the usage of a bytecode instead 
opting to transform code directly into lua objects.

Work here is given away freely under CC0 (or MIT if CC0 is not valid in your legal jurisdiction).

## Caviats

- No Strings
- No Comments.
    - These will need to be added to the parser itself.
    - You can use `%L --` a comment.
- Parse-time words operate on the stack unprotected.
- Quotations assume all parsing operations return a value.
- New lines generate what is basically a `NOP` instruction.

## Goals

Miscellaneous list of tasks I want to work towards.

- [ ] Implement compilation to Lua
- [ ] Implement a REPL
- [ ] Improve parse-time words