
-- TODO
dokx = {}

-- AST setup

local class = require 'pl.class'
local stringx = require 'pl.stringx'
local tablex = require 'pl.tablex'

class.Comment()

function Comment:_init(text)
    text = stringx.strip(text)
    if stringx.startswith(text, "[[") then
        text = stringx.strip(text:sub(3))
    end
    if stringx.endswith(text, "]]") then
        text = stringx.strip(text:sub(1, -3))
    end
    local lines = stringx.splitlines(text)
    tablex.transform(function(line)
        if stringx.startswith(line, "--") then
            local chopIndex = 3
            if stringx.startswith(line, "-- ") then
                chopIndex = 4
            end
            return line:sub(chopIndex)
        end
        return line
    end, lines)
    text = stringx.join("\n", lines)
    self.text = text
end
function Comment:combine(other)
    return Comment(self.text .. other.text)
end
function Comment:str()
    return "{Comment: " .. self.text .. "}"
end
function makeComment(text)
    return Comment(text)
end

class.Function()

function Function:_init(name)
    self.name = name
end
function Function:str()
    return "{Function: " .. self.name .. "}"
end

function makeFunction(name)
    return Function(name)
end

class.Whitespace()
function makeWhitespace()
    return Whitespace()
end
function Whitespace:str()
    return "{Whitespace}"
end

class.DocumentedFunction()

function DocumentedFunction:_init(func, doc)
    self._func = func
    self._doc = doc
end

function DocumentedFunction:name()
    return self._func.name
end
function DocumentedFunction:doc()
    return self._doc.text
end

function DocumentedFunction:str()
    return "{Documented function: \n   " .. self._func:str() .. "\n   " .. self._doc:str() .. "\n}"
end

-- Lua 5.1 parser - based on one from http://lua-users.org/wiki/LpegRecipes

local lpeg = require "lpeg";

local locale = lpeg.locale();

local P, S, V = lpeg.P, lpeg.S, lpeg.V;

local C, Cb, Cc, Cg, Cs, Cmt =
    lpeg.C, lpeg.Cb, lpeg.Cc, lpeg.Cg, lpeg.Cs, lpeg.Cmt;

local shebang = P "#" * (P(1) - P "\n")^0 * P "\n";

local function K (k) -- keyword
  return P(k) * -(locale.alnum + P "_");
end

local lua = P {
  (shebang)^-1 * V "space" * V "chunk" * V "space" * -P(1);

  -- keywords

  keywords = K "and" + K "break" + K "do" + K "else" + K "elseif" +
             K "end" + K "false" + K "for" + K "function" + K "if" +
             K "in" + K "local" + K "nil" + K "not" + K "or" + K "repeat" +
             K "return" + K "then" + K "true" + K "until" + K "while";

  -- longstrings

  longstring = P { -- from Roberto Ierusalimschy's lpeg examples
    V "open" * C((P(1) - V "closeeq")^0) *
        V "close" / function (o, s) return s end;

    open = "[" * Cg((P "=")^0, "init") * P "[" * (P "\n")^-1;
    close = "]" * C((P "=")^0) * "]";
    closeeq = Cmt(V "close" * Cb "init", function (s, i, a, b) return a == b end)
  };

  -- comments & whitespace

  comment = (P "--" * C(V "longstring") +
            P "--" * C((P(1) - P "\n")^0 * (P "\n" + -P(1)))) / makeComment;

  space = (C(locale.space) / makeWhitespace + V "comment")^0;

  -- Types and Comments

  Name = (locale.alpha + P "_") * (locale.alnum + P "_")^0 - V "keywords";
  Number = (P "-")^-1 * V "space" * P "0x" * locale.xdigit^1 *
               -(locale.alnum + P "_") +
           (P "-")^-1 * V "space" * locale.digit^1 *
               (P "." * locale.digit^1)^-1 * (S "eE" * (P "-")^-1 *
                   locale.digit^1)^-1 * -(locale.alnum + P "_") +
           (P "-")^-1 * V "space" * P "." * locale.digit^1 *
               (S "eE" * (P "-")^-1 * locale.digit^1)^-1 *
               -(locale.alnum + P "_");
  String = P "\"" * (P "\\" * P(1) + (1 - P "\""))^0 * P "\"" +
           P "'" * (P "\\" * P(1) + (1 - P "'"))^0 * P "'" +
           V "longstring";

  -- Lua Complete Syntax

  chunk = (V "space" * V "stat" * (V "space" * P ";")^-1)^0 *
              (V "space" * V "laststat" * (V "space" * P ";")^-1)^-1;

  block = V "chunk";

  stat = K "do" * V "space" * V "block" * V "space" * K "end" +
         K "while" * V "space" * V "exp" * V "space" * K "do" * V "space" *
             V "block" * V "space" * K "end" +
         K "repeat" * V "space" * V "block" * V "space" * K "until" *
             V "space" * V "exp" +
         K "if" * V "space" * V "exp" * V "space" * K "then" *
             V "space" * V "block" * V "space" *
             (K "elseif" * V "space" * V "exp" * V "space" * K "then" *
              V "space" * V "block" * V "space"
             )^0 *
             (K "else" * V "space" * V "block" * V "space")^-1 * K "end" +
         K "for" * V "space" * V "Name" * V "space" * P "=" * V "space" *
             V "exp" * V "space" * P "," * V "space" * V "exp" *
             (V "space" * P "," * V "space" * V "exp")^-1 * V "space" *
             K "do" * V "space" * V "block" * V "space" * K "end" +
         K "for" * V "space" * V "namelist" * V "space" * K "in" * V "space" *
             V "explist" * V "space" * K "do" * V "space" * V "block" *
             V "space" * K "end" +
         K "function" * V "space" * V "funcname" * V "space" *  V "funcbody" +
         K "local" * V "space" * K "function" * V "space" * V "Name" *
             V "space" * V "funcbody" +
         K "local" * V "space" * V "namelist" *
             (V "space" * P "=" * V "space" * V "explist")^-1 +
         V "varlist" * V "space" * P "=" * V "space" * V "explist" +
         V "functioncall";

  laststat = K "return" * (V "space" * V "explist")^-1 + K "break";

  funcname = C(V "Name" * (V "space" * P "." * V "space" * V "Name")^0 *
      (V "space" * P ":" * V "space" * V "Name")^-1) / makeFunction;

  namelist = V "Name" * (V "space" * P "," * V "space" * V "Name")^0;

  varlist = V "var" * (V "space" * P "," * V "space" * V "var")^0;

  -- Let's come up with a syntax that does not use left recursion
  -- (only listing changes to Lua 5.1 extended BNF syntax)
  -- value ::= nil | false | true | Number | String | '...' | function |
  --           tableconstructor | functioncall | var | '(' exp ')'
  -- exp ::= unop exp | value [binop exp]
  -- prefix ::= '(' exp ')' | Name
  -- index ::= '[' exp ']' | '.' Name
  -- call ::= args | ':' Name args
  -- suffix ::= call | index
  -- var ::= prefix {suffix} index | Name
  -- functioncall ::= prefix {suffix} call

  -- Something that represents a value (or many values)
  value = K "nil" +
          K "false" +
          K "true" +
          V "Number" +
          V "String" +
          P "..." +
          V "function" +
          V "tableconstructor" +
          V "functioncall" +
          V "var" +
          P "(" * V "space" * V "exp" * V "space" * P ")";

  -- An expression operates on values to produce a new value or is a value
  exp = V "unop" * V "space" * V "exp" +
        V "value" * (V "space" * V "binop" * V "space" * V "exp")^-1;

  -- Index and Call
  index = P "[" * V "space" * V "exp" * V "space" * P "]" +
          P "." * V "space" * V "Name";
  call = V "args" +
         P ":" * V "space" * V "Name" * V "space" * V "args";

  -- A Prefix is a the leftmost side of a var(iable) or functioncall
  prefix = P "(" * V "space" * V "exp" * V "space" * P ")" +
           V "Name";
  -- A Suffix is a Call or Index
  suffix = V "call" +
           V "index";

  var = V "prefix" * (V "space" * V "suffix" * #(V "space" * V "suffix"))^0 *
            V "space" * V "index" +
        V "Name";
  functioncall = V "prefix" *
                     (V "space" * V "suffix" * #(V "space" * V "suffix"))^0 *
                 V "space" * V "call";

  explist = V "exp" * (V "space" * P "," * V "space" * V "exp")^0;

  args = P "(" * V "space" * (V "explist" * V "space")^-1 * P ")" +
         V "tableconstructor" +
         V "String";

  ["function"] = K "function" * V "space" * V "funcbody";

  funcbody = P "(" * V "space" * (V "parlist" * V "space")^-1 * P ")" *
                 V "space" *  V "block" * V "space" * K "end";

  parlist = V "namelist" * (V "space" * P "," * V "space" * P "...")^-1 +
            P "...";

  tableconstructor = P "{" * V "space" * (V "fieldlist" * V "space")^-1 * P "}";

  fieldlist = V "field" * (V "space" * V "fieldsep" * V "space" * V "field")^0
                  * (V "space" * V "fieldsep")^-1;

  field = P "[" * V "space" * V "exp" * V "space" * P "]" * V "space" * P "=" *
              V "space" * V "exp" +
          V "Name" * V "space" * P "=" * V "space" * V "exp" +
          V "exp";

  fieldsep = P "," +
             P ";";

  binop = K "and" + -- match longest token sequences first
          K "or" +
          P ".." +
          P "<=" +
          P ">=" +
          P "==" +
          P "~=" +
          P "+" +
          P "-" +
          P "*" +
          P "/" +
          P "^" +
          P "%" +
          P "<" +
          P ">";

  unop = P "-" +
         P "#" +
         K "not";
};

function dokx.extractDocs(inputPath)

    local content = io.open(inputPath, "rb"):read("*all")

    local matched = { lpeg.match(lua, content) }

    local List = require 'pl.List'
    local merged = List.new()
    local tablex = require 'pl.tablex'

    -- Merge adjacent comments
    tablex.foreachi(matched, function(x)
        if #merged ~= 0 and merged[merged:len()]:is_a(Comment) and x:is_a(Comment) then
            merged[merged:len()] = merged[merged:len()]:combine(x)
        else
            merged:append(x)
        end
    end)

    -- Remove whitespace
    merged = tablex.filter(merged, function(x) return not x:is_a(Whitespace) end)

    local merged2 = List.new()
    tablex.foreachi(merged, function(x)
        if #merged2 ~= 0 and merged2[merged2:len()]:is_a(Comment) and x:is_a(Function) then
            merged2[merged2:len()] = DocumentedFunction(x, merged2[merged2:len()])
        else
            merged2:append(x)
        end
    end)


    -- Find comments that immediately precede functions - we assume these are the corresponding docs

    local documentedFunctions = List.new()
    local undocumentedFunctions = List.new()

    for entity in merged2:iter() do
        --    print(entity:str())
        if entity:is_a(DocumentedFunction) then
            documentedFunctions:append(entity)
        end
        if entity:is_a(Function) then
            undocumentedFunctions:append(entity)
        end
    end

    print("Undocumented functions:", undocumentedFunctions)
    return documentedFunctions
end


