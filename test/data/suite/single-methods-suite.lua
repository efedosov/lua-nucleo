--------------------------------------------------------------------------------
-- single-methods-suite.lua: suite used for full suite tests
-- This file is a part of lua-nucleo library
-- Copyright (c) lua-nucleo authors (see file `COPYRIGHT` for the license)
--------------------------------------------------------------------------------

local make_suite = select(1, ...)
local test = make_suite("single-methods-suite", { to_test = true })
test:factory "to_test" { "method1", "method2" }
test:methods "method1" "method2"
test "any" (function() end)
