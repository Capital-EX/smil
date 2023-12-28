--
-- Much of this implementation is following "Bootstrapping a Forth in 40 lines 
-- of Lua code" by Eduardo Ochs.
--
-- http://angg.twu.net/miniforth-article.html
--
jit.off()
_F, DS, POS = {}, { n = 0 }, 1

LOAD = function (code) return assert(load(code)) end
EVAL = function (code) (LOAD(code))() end
TOS  = function (s) return s[s.n] end
POP  = function (s) local x = TOS(s) s[s.n], s.n = nil, s.n - 1 return x end
PSH  = function (s, x) s.n = s.n + 1 s[s.n] = x end

local __tostring = function (self) return self:compile() end
LUA_QUOTE = function (source)
    return setmetatable(
           { source = source, type = "LuaQuote"
           , func   = assert(load(source))
           , call
                = function (self) self.func() end
           , inline 
                = function (self) return self.source end
           , compile
                = function (self) return self.source end
           }, {__tostring = __tostring})
end

SMIL_QUOTE = function (body)
    return setmetatable(
           { body = body, type = "LupaQuote"
           , call
                = function (self)
                    for _, item in ipairs(self.body) do
                        if type(item) == "table" and item.type == "Word" then
                            item:call()
                        else
                            PSH(DS, item)
                        end
                    end
                end
           , compile
                = function (self)

                end
           }, {__tostring = __tostring})
end

---@param args { name: string, def: table, immediate: boolean, undefined: boolean, recursive: boolean }
---@return table
WORD = function (args)
    return setmetatable(
           { name = args.name, type = "Word", def = args.def
           , recursive = (args.recursive ~= nil) and args.recursive or false
           , undefined = (args.undefined ~= nil) and args.undefined or false
           , immediate = (args.immediate ~= nil) and args.immediate or false
           , call
                = function (self)
                    self.def:call()
                end
           , compile
                = function (self)
                    if self.def.type == "LuaQuote" then
                        return self.def.source
                    elseif self.def.type == "LupaQuote" then
                        local code = {}
                        for i, v in ipairs(self.def.body) do
                            code[#code+1] = v:compile()
                        end
                        return table.concat(code, "\n")
                    else
                        return self.def:compile()
                    end
                end
           }, {__tostring = __tostring})
end

function parse_pattern(pat)
    local capture, newpos = PROG:match(pat, POS)
    if newpos then POS = newpos return capture end
end

-- Allow quotes to be parsed on their own
function parse_squote () return parse_pattern("^(')()")         end
function parse_dquote () return parse_pattern("^(\")()")        end
function parse_token  () return parse_squote() or
                                      parse_dquote() or
                                      parse_pattern("^([^ \t\n]+)()") end

-- Parsing words to handle whitespace 
function parse_spaces      () return parse_pattern("^([ \t]*)()")    end
function parse_nl          () return parse_pattern("^(\n)()")        end
function parse_to_nl       () return parse_pattern("^([^\n]*)()")    end
function parse_token_or_nl () return parse_token() or parse_nl()        end
function get_token         () parse_spaces() return  parse_token()      end
function get_token_or_nl   () parse_spaces() return parse_token_or_nl() end

NOP      = WORD{ name = "NOP", def = LUA_QUOTE("") }
_F["%L"] = WORD{ name = "%L",  def = LUA_QUOTE([[ parse_spaces() EVAL(parse_to_nl()) ]]), parsing = true}

RUNNING = true
RUN = function() while RUNNING do INTERPRET() end end

INTERPRET_WORD = function() if _F[word] then _F[word]:call() return true end end
INTERPRET_NUMBER = function() local n = tonumber(word) if n then PSH(DS, n) return true end end
INTERPRET = function()
    word = get_token_or_nl() or ""
    local _ = INTERPRET_WORD() or INTERPRET_NUMBER() or error("Can't interpret: " .. word)
end

PARSE_WORD = function() if _F[word] then return _F[word] end end
PARSE_NUMBER = function() local n = tonumber(word) if n then return n end end
PARSE_DATUM = function()
    local datum = PARSE_WORD() or PARSE_NUMBER() or error("Can't parse: " .. word)
    if type(datum) == "table" and datum.immediate then
        datum:call()
    else
        PSH(DS, datum)
    end
end

PROG = [=[
%L _F["\n"]     = WORD{ name = "\n", def = LUA_QUOTE("") } 
%L _F[""]       = WORD{ name = "",   def = LUA_QUOTE([[ RUNNING = false ]]) }
%L _F["L["]     = WORD{ name = "L[", def = LUA_QUOTE([[ PSH(DS, LUA_QUOTE(parse_pattern("^(.-)%s]()"))) ]]), immediate = true }
%L _F["'"]      = WORD{ name = "'",  def = LUA_QUOTE([[ PSH(DS, parse_token()) ]]),                          immediate = true }
%L _F["DEFINE"] = WORD{ name = "DEFINE",   def = LUA_QUOTE([[ local name = POP(DS) if _F[name] then _F[name].def = POP(DS) _F[name].undefined = false else _F[name] = WORD{ name = name, def = POP(DS) } end ]]) }
L[ local name = POP(DS) _F[name] = WORD{ name = name, def = NOP, undefined = true } ] 'DECLARE DEFINE
L[ local name = POP(DS) _F[name] = WORD{ name = name, def = POP(DS), immediate = true } ] 'IMMEDIATE DEFINE
L[ POP(DS):call() ] 'CALL DEFINE
L[ local f, t, b = POP(DS), POP(DS), POP(DS) if b then PSH(DS, t) else PSH(DS, f) end ] '? DEFINE
L[ 
    local body = {}
    word = get_token_or_nl()
    while word ~= "]" do
        PARSE_DATUM() body[#body+1] = POP(DS) word = get_token_or_nl()
    end
    PSH(DS, SMIL_QUOTE(body))
] '[ IMMEDIATE
L[ PSH(DS, TOS(DS)) ] 'DUP DEFINE
L[ local x, y = POP(DS), POP(DS) PSH(DS, x) PSH(DS, y) ] 'SWP DEFINE
L[ local x, y = POP(DS), POP(DS) PSH(DS, y + x) ] '+ DEFINE
L[ local x, y = POP(DS), POP(DS) PSH(DS, y - x) ] '- DEFINE
L[ local x, y = POP(DS), POP(DS) PSH(DS, y == x) ] '== DEFINE

'FIB DECLARE [
    DUP 0 == [ ] [ DUP 1 == [ ] [ DUP 1 - FIB SWP 2 - FIB + ] ? CALL ] ? CALL
] 'FIB DEFINE 

30 FIB L[ print(POP(DS)) ] CALL
]=]

POS = 1
RUN()