-- EBML library for reading EBML documents
-- written by hubblec4


--[=[ Lua Verison compatiblity: 
    Lua 5.1, Lua 5.2 and LuaJIT are not able to handle Bit operations fully
    Lua 5.3 (and higher, 5.3++) has proper build-in Bit operation support  
    
    I use my own "Compiler switch" technic to support both cases directly
    Code for Lua5.3++ uses: --[[LuaNew <- start switch
    Code for older Lua versions uses: -- [[LuaOld <- start switch
    for switching you have to make a manual String replace
    Xxx = "New" or "Old"
    activate LuaXxx: change "--[[LuaXxx" to "-- [[LuaXxx"
    disable LuaXxx: change "-- [[LuaXxx" to "--[[LuaXxx"    

    default version is LuaOld
--]=]

-- Define some functions for older Lua versions
-- [[LuaOld start

-- left shift
local function lsh(val, shift)
    return val * (2 ^ shift)
end

-- right shift
local function rsh(val, shift)
    return math.floor(val / (2 ^ shift))
end

-- Bitwise AND
local function bwAND(a, b)
    local result = 0
    local bitval = 1

    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitval = bitval * 2
    end

    return result
end

-- get float 32 from a buffer
local function get_float(buffer)
    local b1, b2, b3, b4 = string.byte(buffer, 1, 4)

    local sign = bwAND(b1, 0x80)
    local exponent = bwAND(b1, 0x7F) * 2 + bwAND(b2, 0x80) - 127
    local mantisse = (0x800000 + bwAND(b2, 0x7F) * 2^16 + b3 * 2^8 + b4) / 2^23

    return (-1)^sign * 2^exponent * mantisse
end

-- get double 64 from a buffer
local function get_double(buffer)
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(buffer, 1, 8)

    local sign = bwAND(b1, 0x80)
    local exponent = bwAND(b1, 0x7F) * 2^4 + bwAND(b2, 0xF0) - 1023
    local mantisse = (0x10000000000000 + (b2 % 16) * 2^48 + b3 * 2^40 + b4 * 2^32 + b5 * 2^24 + b6 * 2^16 + b7 * 2^8 + b8) / 2^52

    return (-1)^sign * 2^exponent * mantisse
end

-- end LuaOld ]]


-- EBML defines for reading data
local SCOPE_NO_DATA = 0
local SCOPE_PARTIAL_DATA = 1
local SCOPE_ALL_DATA = 2

-- EBML defines for element levels
local ELEM_LEVEL_GLOBAL = -1 -- all values smaller 0 are global elements
local ELEM_LEVEL_CHILD = 0
local ELEM_LEVEL_SIBLING = 1
-- local ELEM_LEVEL_PARENT > 1 all values greater 1 are parent elements

-- max data size
local MAX_DATA_SIZE = 0x7FFFFFFF


--[[LuaNew start

-- decode VINT - returns the u-integer value and value is an unknown-size value
local function decode_vint(buf, len, start)
    start = start or 1
    local sizemask = 1 << 7
    local sizeunknown = 0x7f
    local result = 0

    if len == 0 or len > 8 or #buf +1 < start + len then
        return -1, false
    end

    sizemask = sizemask >> (len -1)
    result = buf[start] & ~sizemask

    for i = 2, len do
        result = (result << 8) | buf[start + i - 1]
        sizeunknown = (sizeunknown << 7) | 0x7F
    end
    
    return result, sizeunknown == result
end

-- get VINT length 
local function get_vint_len(byte1)
    -- in order of occurrence 
    if     byte1 & 0x80 ~= 0 then return 1
    elseif byte1 & 0x40 ~= 0 then return 2
    elseif byte1 & 0x10 ~= 0 then return 4
    elseif byte1 & 0x20 ~= 0 then return 3
    elseif byte1 & 0x01 ~= 0 then return 8
    elseif byte1 == 0        then return 0
    elseif byte1 & 0x08 ~= 0 then return 5
    elseif byte1 & 0x04 ~= 0 then return 6
    elseif byte1 & 0x02 ~= 0 then return 7
    end
end
-- LuaNew end ]]

-- [[LuaOld start

-- decode VINT - returns the u-integer value and value is an unknown-size value
local function decode_vint(buf, len, start)
    start = start or 1
    local sizemask = 0x80
    local sizeunknown = 0x7f
    local result = 0

    if len == 0 or len > 8 or #buf +1 < start + len then
        return -1, false
    end

    sizemask = rsh(sizemask, len -1)
    result = bwAND(buf[start], (0xFF - sizemask))

    for i = 2, len do
        result = lsh(result, 8) + buf[start + i - 1]
        sizeunknown = lsh(sizeunknown, 7) + 0x7F
    end
    
    return math.floor(result), sizeunknown == result
end

-- get VINT length 
local function get_vint_len(byte1)
    if byte1 >= 128 then
        return 1
    elseif byte1 >= 64 then
        return 2
    elseif byte1 >= 32 then
        return 3
    elseif byte1 >= 16 then
        return 4
    elseif byte1 >= 8 then
        return 5
    elseif byte1 >= 4 then
        return 6
    elseif byte1 >= 2 then
        return 7
    elseif byte1 == 1 then
        return 8
    else
        return 0
    end
end
-- LuaOld end ]]


-- EBML stream reading
local function read_stream(stream, size)
    local t = stream:read(size)
    if #t ~= size then
        error("EOF in read_stream")
    end
    return t
end

-- remove zero bytes from a string - EBML allows padding strings with zero-bytes
local function remove_zero_bytes(str)
    return string.gsub(str, "%z", "")
end


-- -----------------------------------------------------------------------------
-- EBML Element ----------------------------------------------------------------
-- -----------------------------------------------------------------------------

-- EBML Element Base class
local ebml_element = {
    -- data_position: element data positon in the stream
    data_position = 0,
    -- data_size: size of data
    data_size = 0,
    -- data_size_len: the length of the data_size vaule from 1 to 8
    data_size_len = 0,
    -- unknown_data_size: data size is unknown -> infinity size
    unknown_data_size = false,
    -- value: a var for all EBML type values
    value = nil
}

-- EBML element construtor
function ebml_element:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

-- data size is finite
function ebml_element:data_size_is_finite()
    return not self.unknown_data_size
end

-- read data (virtual) 
function ebml_element:read_data(stream, readfully)
    return 0
end

-- get context (virtual)
function ebml_element:get_context()
    return nil
end

-- validate data size (virtual)
function ebml_element:validate_data_size()
    return true
end

-- validate data (virtual)
function ebml_element:validate_data()
    return true
end

-- unknown data size is allowed (virtual)
function ebml_element:unknown_size_is_allowed()
    return false
end

-- is Dummy
function ebml_element:is_dummy()
    return false
end

-- is Master
function ebml_element:is_master()
    return false
end

-- is_class: checks if an element ID matches the ID of the given class
function ebml_element:is_class(class)
    return self:get_context().id == class:get_context().id
end

-- skip data
-- function ebml_element:skip_data(stream)
-- must be defined later

-- end position
function ebml_element:end_position()
    return self.data_position + self.data_size
end


-- -----------------------------------------------------------------------------
-- EBML Binary type ------------------------------------------------------------
-- -----------------------------------------------------------------------------

-- EBML Binary class
local ebml_binary = ebml_element:new()

-- ebml binary constructor -----------------------------------------------------
function ebml_binary:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = "" -- init empty data
    return elem
end

-- read binary data ------------------------------------------------------------
function ebml_binary:read_data(stream, readfully)
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = "" -- init with the type default value, empty data

    if readfully == SCOPE_NO_DATA or self.data_size == 0 then
        return self.data_size
    end
    
    self.value = read_stream(stream, self.data_size)
    return self.data_size
end

-- validate data size 
function ebml_binary:validate_data_size()
    return self.data_size <= MAX_DATA_SIZE
end


-- -----------------------------------------------------------------------------
-- EBML UTF-8 type -------------------------------------------------------------
-- -----------------------------------------------------------------------------

-- EBML UTF-8  class
local ebml_utf8 = ebml_element:new()

-- ebml utf-8 constructor ------------------------------------------------------
function ebml_utf8:new(def_val)
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = def_val or ""
    return elem
end

-- read utf8 data --------------------------------------------------------------
function ebml_utf8:read_data(stream, readfully)
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = ""

    if readfully == SCOPE_NO_DATA or self.data_size == 0 then
        return self.data_size
    end
    
    self.value = remove_zero_bytes(read_stream(stream, self.data_size))
    return self.data_size
end

-- validate data size 
function ebml_utf8:validate_data_size()
    return self.data_size <= MAX_DATA_SIZE
end


-- -----------------------------------------------------------------------------
-- EBML String type ------------------------------------------------------------
-- -----------------------------------------------------------------------------

-- EBML String  class
local ebml_string = ebml_element:new()

-- ebml string constructor -----------------------------------------------------
function ebml_string:new(def_val)
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = def_val or ""
    return elem
end

-- read data -------------------------------------------------------------------
function ebml_string:read_data(stream, readfully)
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = ""

    if readfully == SCOPE_NO_DATA or self.data_size == 0 then
        return self.data_size
    end

    self.value = remove_zero_bytes(read_stream(stream, self.data_size))
    return self.data_size
end

-- validate data size 
function ebml_string:validate_data_size()
    return self.data_size <= MAX_DATA_SIZE
end

-- validate data
function ebml_string:validate_data()
    -- allowed chars from 0x20 to 0x7E, zero-bytes are already removed
    for i = 1, #self.value do
        if string.byte(self.value, i) < 0x20
        or string.byte(self.value, i) > 0x7E then
            return false
        end
    end
    return true
end



-- -----------------------------------------------------------------------------
-- EBML Unsigned Integer type --------------------------------------------------
-- -----------------------------------------------------------------------------

-- EBML U-Integer class
local ebml_uinteger = ebml_element:new()

-- ebml u-integer constructor
function ebml_uinteger:new(def_val)
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = def_val or 0
    return elem
end

-- read u-integer data
function ebml_uinteger:read_data(stream, readfully)
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = 0 -- init with the type default value

    if readfully == SCOPE_NO_DATA or self.data_size == 0 then
        return self.data_size
    end

    local buffer = read_stream(stream, self.data_size)

    for i = 1, self.data_size do
        --[[LuaNew
        self.value = (self.value << 8) | string.byte(buffer, i)
        -- LuaNew end ]]

        -- [[LuaOld
        self.value = lsh(self.value, 8) + string.byte(buffer, i)
        -- LuaOld end ]]        
    end
    -- [[LuaOld
    self.value = math.floor(self.value)
    -- LuaOld end ]]  

    return self.data_size
end

-- validate data size 
function ebml_uinteger:validate_data_size()
    return self.data_size >= 0 and self.data_size <= 8
end


-- -----------------------------------------------------------------------------
-- EBML Signed Integer type ----------------------------------------------------
-- -----------------------------------------------------------------------------

-- EBML Integer class
local ebml_integer = ebml_element:new()

-- ebml s-integer constructor
function ebml_integer:new(def_val)
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = def_val or 0
    return elem
end

-- read s-integer data
function ebml_integer:read_data(stream, readfully)
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = 0 -- init with the type default value

    if readfully == SCOPE_NO_DATA or self.data_size == 0 then
        return self.data_size
    end

    local buffer = read_stream(stream, self.data_size)

    --[[LuaNew
    for i = 1, self.data_size do
        self.value = (self.value << 8) | string.byte(buffer, i)
    end

    local sign_bit = 1 << (self.data_size * 8 - 1)
    if (self.value & sign_bit) ~= 0 then
        self.value = self.value - (1 << (self.data_size * 8))
    end
    -- LuaNew end ]]

    -- [[LuaOld
    for i = 1, self.data_size do
        self.value = lsh(self.value, 8) + string.byte(buffer, i)
    end

    local sign_bit = lsh(1, (self.data_size * 8 - 1))
    if bwAND(self.value, sign_bit) ~= 0 then
        self.value = self.value - lsh(1, (self.data_size * 8))
    end
    self.value = math.floor(self.value)
    -- LuaOld end ]]

    return self.data_size
end

-- validate data size 
function ebml_integer:validate_data_size()
    return self.data_size >= 0 and self.data_size <= 8
end


-- -----------------------------------------------------------------------------
-- EBML Float type -------------------------------------------------------------
-- -----------------------------------------------------------------------------

-- EBML Float class
local ebml_float = ebml_element:new()

-- ebml float constructor
function ebml_float:new(def_val)
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = def_val or 0.0
    return elem
end

-- read float data
function ebml_float:read_data(stream, readfully)
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = 0.0 -- init with the type default value

    if readfully == SCOPE_NO_DATA or self.data_size == 0 then
        return self.data_size
    end

    local buffer = read_stream(stream, self.data_size)

    --[[LuaNew
    if self.data_size == 4 then
        self.value = string.unpack(">f", buffer)
    else -- data_size == 8
        self.value = string.unpack(">d", buffer)
    end
    -- LuaNew end ]]

    -- [[LuaOld
    if self.data_size == 4 then
        self.value = get_float(buffer)
    else -- data_size == 8
        self.value = get_double(buffer)
    end
    -- LuaOld end ]]

    return self.data_size
end

-- validate data size 
function ebml_float:validate_data_size()
    return (self.data_size == 0 or self.data_size == 4 or self.data_size == 8)
end


-- -----------------------------------------------------------------------------
-- EBML Date type --------------------------------------------------------------
-- -----------------------------------------------------------------------------

-- UNIX epoch delay to UTC
local UNIX_EPOCH_DELAY = 978307200

-- EBML Date class
local ebml_date = ebml_element:new()

-- ebml date constructor
function ebml_date:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = 0
    return elem
end

-- read date data
function ebml_date:read_data(stream, readfully)
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = 0 -- init with the type default value

    if readfully == SCOPE_NO_DATA or self.data_size == 0 then
        return self.data_size
    end

    local buffer = read_stream(stream, self.data_size)

    --[[LuaNew
    for i = 1, self.data_size do
        self.value = (self.value << 8) | string.byte(buffer, i)
    end

    local sign_bit = 1 << (self.data_size * 8 - 1)
    if (self.value & sign_bit) ~= 0 then
        self.value = self.value - (1 << (self.data_size * 8))
    end
    -- LuaNew end ]]

    -- [[LuaOld
    for i = 1, self.data_size do
        self.value = lsh(self.value, 8) + string.byte(buffer, i)
    end

    local sign_bit = lsh(1, (self.data_size * 8 - 1))
    if bwAND(self.value, sign_bit) ~= 0 then
        self.value = self.value - lsh(1, (self.data_size * 8))
    end
    self.value = math.floor(self.value)
    -- LuaOld end ]]

    return self.data_size
end

-- validate data size 
function ebml_date:validate_data_size()
    return self.data_size == 8
end

-- get UTC formated
function ebml_date:get_utc()
    return os.date("!%Y-%m-%d %H:%M:%S", math.floor(self.value / 1000000000) + UNIX_EPOCH_DELAY)
end


-- -----------------------------------------------------------------------------
-- EBML Master type - forward declaration --------------------------------------
-- -----------------------------------------------------------------------------

-- EBML Master class
local ebml_master = ebml_element:new()


-- -----------------------------------------------------------------------------
-- EBML elements forward declaration -------------------------------------------
-- -----------------------------------------------------------------------------

local EBML = ebml_master:new()
local EBMLVersion = ebml_uinteger:new(1)
local EBMLReadVersion = ebml_uinteger:new(1)
local EBMLMaxIDLength = ebml_uinteger:new(4)
local EBMLMaxSizeLength = ebml_uinteger:new(8)
local DocType = ebml_string:new()
local DocTypeVersion = ebml_uinteger:new(1)
local DocTypeReadVersion = ebml_uinteger:new(1)
local DocTypeExtension = ebml_master:new()
local DocTypeExtensionName = ebml_string:new()
local DocTypeExtensionVersion = ebml_uinteger:new()
local Void = ebml_binary:new()
local CRC32 = ebml_binary:new()
local Dummy = ebml_binary:new()-- not in the specs but included in c++ libEBML

local semantic_ebml_global = {Void, CRC32}


-- core functions for reading an EBML stream

-- create element using semantic - returns the element and it's level 
local function create_elem_using_semantic(id, semantic, elem_level, allow_dummy, check_global)
    -- predefines
    if check_global == nil then
        check_global = true
    end

    -- search in the current semantic -> child elements
    if semantic then
        for i = 1, #semantic do
            if id == semantic[i]:get_context().id then
                return semantic[i]:new(), elem_level
            end
        end
    end
        
    -- Ebml global semantic
    if check_global then
        for i = 1, #semantic_ebml_global do
            if id == semantic_ebml_global[i]:get_context().id then
                return semantic_ebml_global[i]:new(), ELEM_LEVEL_GLOBAL
            end
        end
    end
        
    -- Parent element - a sibling
    local parent_s = semantic[1]:get_context().parent
    if parent_s == nil then return nil, elem_level end -- root element has been reached
    if parent_s:get_context().id == id then
        return parent_s:new(), elem_level +1
    end
        
    -- check whether it's not part of an upper parent
    parent_s = parent_s:get_context().parent
    if parent_s then
        return create_elem_using_semantic(id, parent_s:get_semantic(), elem_level +1, allow_dummy, false)
    end
        
    -- Dummy element
    if allow_dummy then
        return Dummy:new(id), ELEM_LEVEL_CHILD
    end
        
    return nil, elem_level
end
      

-- find next element - return@1 the element, return@2 element level, return@3 element position
local function find_next_element(stream, semantic, max_read_size, elem_level, allow_dummy)
    -- predefines
    -- elem_level == -1 -> this is a special case for searching elements on the root level
    -- normaly, elem_level's < 0 means global element
    -- so be careful to use "-1", only for root elements
    local root_search = false
    if elem_level == nil then elem_level = 0
    elseif elem_level == -1 then
        elem_level = ELEM_LEVEL_CHILD
        root_search = true
    end

    if allow_dummy == nil then allow_dummy = true end
    
    local readed_size = 0
    local id_start = 0
    local found = false
    local parse_start = stream:seek()
  
    local possible_id_len = 0
    local possible_id = 0
    local possible_size_len = 0
  
    local available_bytes = 0
    local headbuffer = {}
    local elem = nil
    local elem_level_org = elem_level
  
    local function read_more_bytes(size)
        local data = stream:read(size)
        if data and #data == size then
            for i = 1, size do
                headbuffer[available_bytes + i] = string.byte(data, i)
            end
            available_bytes = available_bytes + size
            readed_size = readed_size + size
            return true
        end
        return false
    end
  
    local function shift_data()
        if available_bytes > 1 then
            for i = 2, available_bytes do
                headbuffer[i - 1] = headbuffer[i]
            end
        end
        available_bytes = available_bytes - 1
        id_start = id_start + 1
    end
  
    local function find_id()
        found = false
        while not found do
            if available_bytes == 0 then
                if not read_more_bytes(1) then
                    break
                end
            end
  
            possible_id_len = get_vint_len(headbuffer[1])
            if possible_id_len > 0 and possible_id_len < 5 then
                if possible_id_len > available_bytes then
                    if not read_more_bytes(possible_id_len - available_bytes) then
                        break
                    end
                end
          
                possible_id = headbuffer[1]
                for b = 2, possible_id_len do
                    --[[LuaNew
                    possible_id = (possible_id << 8) | headbuffer[b]
                    -- LuaNew end ]]

                    -- [[LuaOld
                    possible_id = lsh(possible_id, 8) + headbuffer[b]
                    -- LuaOld end ]]                    
                end

                found = true
                break
            end
  
            if max_read_size <= readed_size then
                break
            end
  
            shift_data()
        end
    end
  
    local function read_size()
        found = false
        if available_bytes == possible_id_len then
            if not read_more_bytes(1) then
                return
            end
        end
  
        possible_size_len = get_vint_len(headbuffer[possible_id_len +1])
        if possible_id_len == 0 then
            return
        end
  
        if possible_size_len > available_bytes - possible_id_len then
            if not read_more_bytes(possible_size_len - (available_bytes - possible_id_len)) then
                return
            end
        end
  
        found = max_read_size >= readed_size or max_read_size == 0
    end
  
      
    while max_read_size >= readed_size do
        find_id()
        if not found then return nil, elem_level end
  
        read_size()
        if found then
            elem, elem_level = create_elem_using_semantic(possible_id, semantic, elem_level, allow_dummy)
        else
            elem = nil
        end

        if elem then
            elem.data_size_len = possible_size_len
            elem.data_size, elem.unknown_data_size = decode_vint(headbuffer, possible_size_len, possible_id_len +1)
  
            if allow_dummy or (not elem:is_dummy()) then
                if elem:validate_data_size() and (max_read_size == 0 or (elem_level > ELEM_LEVEL_CHILD)
                or (max_read_size >= id_start + possible_id_len + possible_size_len + elem.data_size)
                or elem.unknown_data_size or root_search) then
                    elem.data_position = parse_start + id_start + possible_id_len + possible_size_len
                    stream:seek("set", elem.data_position)
                    return elem, elem_level, parse_start + id_start
                end
            end
        end
  
        if max_read_size > readed_size then
            shift_data()
        else
            return nil, elem_level
        end
        elem_level = elem_level_org
    end
  
    return nil, elem_level
  end
  


  -- Ebml Element
  -- skip data, must be defined after find_next_element()
function ebml_element:skip_data(stream)
    -- data size is finite
    if not self.unknown_data_size then
        stream:seek("cur", self.data_size)
        return
    end

    -- data size is infinite, skip with it's own semantic
    local elem, level, pos
    local semantic = self:get_semantic()

    while true do
        elem, level, pos = find_next_element(stream, semantic, MAX_DATA_SIZE, 0)
        if elem == nil then return end

        if level > ELEM_LEVEL_CHILD then
            -- finish skip data - set file postion back to the start of the element            
            stream:seek("set", pos)
            return
        end
        elem:skip_data(stream)
    end
end


-- -----------------------------------------------------------------------------
-- EBML Master type ------------------------------------------------------------
-- -----------------------------------------------------------------------------

  -- ebml master constructor
function ebml_master:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.value = {}
    return elem
end

-- read data
function ebml_master:read_data(stream, readfully, elem_level, allow_dummy)
    if allow_dummy == nil then allow_dummy = true end
    if elem_level == nil then elem_level = ELEM_LEVEL_CHILD end
    if readfully == nil then readfully = SCOPE_ALL_DATA end
    self.value = {} -- init value as an empty table!
    if readfully == SCOPE_NO_DATA then return end
      
    local max_read_size
    if self.unknown_data_size then
        max_read_size = MAX_DATA_SIZE
    else
        if self.data_size == 0 then return end
        max_read_size = self.data_size
    end
      
    stream:seek("set", self.data_position)
    local elem, elem_level, pos = find_next_element(stream, self.get_semantic(), max_read_size, elem_level, allow_dummy)    
      
    while elem and elem_level <= ELEM_LEVEL_CHILD and max_read_size > 0 do
        if self:data_size_is_finite() and elem:data_size_is_finite() then
            max_read_size = (self.data_position + self.data_size) - (elem.data_position + elem.data_size)
        end
      
        --local success, error = pcall(function()
            -- new: TScopeMode: SCOPE_PARTIAL_DATA for this Master
            -- all non-Master elements will be parsed fully
            -- Master elements only the header is parsed
            if elem:is_master() and readfully == SCOPE_PARTIAL_DATA then
                elem:skip_data(stream)
            else
                elem:read_data(stream, readfully, elem_level, allow_dummy)
            end
        --end)
      
        table.insert(self.value, elem)
      
        if max_read_size < 1 then return end
      
        elem, elem_level, pos = find_next_element(stream, self.get_semantic(), max_read_size, ELEM_LEVEL_CHILD, allow_dummy)
    end

    -- last found element is a Sibling
    if elem_level > ELEM_LEVEL_CHILD then
        stream:seek("set", pos) -- set file pointer back to elements start
    end
end

-- is Master
function ebml_master:is_master()
    return true
end

-- validate data size - any size is valid
function ebml_master:validate_data_size()
    return self:unknown_size_is_allowed() or not self.unknown_data_size
end

-- find element
function ebml_master:find_element(elem_class, create_if_nil)
    for idx, elem in ipairs(self.value) do
        if elem:get_context().id == elem_class:get_context().id then
            return elem, idx
        end
    end

    -- elem not found, only create if it's mandatory
    if create_if_nil and elem_class:get_context().manda then
        local new_elem = elem_class:new()
        table.insert(self.value, new_elem)
        return new_elem, #self.value
    end

    -- not found and no creation
    return nil, -1
end

-- find child
function ebml_master:find_child(elem_class)
    return self:find_element(elem_class)
end

-- find next child
function ebml_master:find_next_child(prev_idx)
    local id = self.value[prev_idx]:get_context().id

    for i = prev_idx + 1, #self.value do
        if self.value[i]:get_context().id == id then
            return self.value[i], i
        end
    end

    -- no next child
    return nil, -1
end

-- get child
function ebml_master:get_child(elem_class)
    return self:find_element(elem_class, true)
end
-- -----------------------------------------------------------------------------


-- EBML ------------------------------------------------------------------------
function EBML:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function EBML:get_context()
    return {id = 0x1A45DFA3, manda = true, parent = nil, name = "EBML"}
end

function EBML:get_semantic()
    return {EBMLVersion, EBMLReadVersion, EBMLMaxIDLength, EBMLMaxSizeLength,
        DocType, DocTypeVersion, DocTypeReadVersion, DocTypeExtension}
end
-- -----------------------------------------------------------------------------


-- EBMLVersion -----------------------------------------------------------------
function EBMLVersion:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function EBMLVersion:get_context()
    return {id = 0x4286, manda = true, parent = EBML, name = "EBMLVersion"}
end

function EBMLVersion:validate_data()
    return self.value > 0
end
-- -----------------------------------------------------------------------------


-- EBMLReadVersion -------------------------------------------------------------
function EBMLReadVersion:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function EBMLReadVersion:get_context()
    return {id = 0x42F7, manda = true, parent = EBML, name = "EBMLReadVersion"}
end

function EBMLReadVersion:validate_data()
    return self.value == 1
end
-- -----------------------------------------------------------------------------


-- EBMLMaxIDLength -------------------------------------------------------------
function EBMLMaxIDLength:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function EBMLMaxIDLength:get_context()
    return {id = 0x42F2, manda = true, parent = EBML, name = "EBMLMaxIDLength"}
end

function EBMLMaxIDLength:validate_data()
    return self.value >= 4
end
-- -----------------------------------------------------------------------------


-- EBMLMaxSizeLength -----------------------------------------------------------
function EBMLMaxSizeLength:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function EBMLMaxSizeLength:get_context()
    return {id = 0x42F3, manda = true, parent = EBML, name = "EBMLMaxSizeLength"}
end

function EBMLMaxSizeLength:validate_data()
    return self.value > 0
end
-- -----------------------------------------------------------------------------


-- DocType ---------------------------------------------------------------------
function DocType:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function DocType:get_context()
    return {id = 0x4282, manda = true, parent = EBML, name = "DocType"}
end

function DocType:validate_data_size()
    return self.data_size > 0
end
-- -----------------------------------------------------------------------------


-- DocTypeVersion --------------------------------------------------------------
function DocTypeVersion:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function DocTypeVersion:get_context()
    return {id = 0x4287, manda = true, parent = EBML, name = "DocTypeVersion"}
end

function DocTypeVersion:validate_data()
    return self.value > 0
end
-- -----------------------------------------------------------------------------


-- DocTypeReadVersion ----------------------------------------------------------
function DocTypeReadVersion:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function DocTypeReadVersion:get_context()
    return {id = 0x4285, manda = true, parent = EBML, name = "DocTypeReadVersion"}
end

function DocTypeReadVersion:validate_data()
    return self.value > 0
end
-- -----------------------------------------------------------------------------


-- DocTypeExtension ------------------------------------------------------------
function DocTypeExtension:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function DocTypeExtension:get_context()
    return {id = 0x4281, manda = false, parent = EBML, name = "DocTypeExtension"}
end

function DocTypeExtension:get_semantic()
    return {DocTypeExtensionName, DocTypeExtensionVersion}
end
-- -----------------------------------------------------------------------------


-- DocTypeExtensionName --------------------------------------------------------
function DocTypeExtensionName:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function DocTypeExtensionName:get_context()
    return {id = 0x4283, manda = true, parent = DocTypeExtension, name = "DocTypeExtensionName"}
end

function DocTypeExtensionName:validate_data_size()
    return self.data_size > 0
end
-- -----------------------------------------------------------------------------


-- DocTypeExtensionVersion -----------------------------------------------------
function DocTypeExtensionVersion:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function DocTypeExtensionVersion:get_context()
    return {id = 0x4284, manda = true, parent = DocTypeExtension, name = "DocTypeExtensionVersion"}
end

function DocTypeExtensionVersion:validate_data()
    return self.value > 0
end
-- -----------------------------------------------------------------------------



-- -----------------------------------------------------------------------------
-- EBML Global elements --------------------------------------------------------
-- -----------------------------------------------------------------------------


-- Void ------------------------------------------------------------------------
function Void:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function Void:get_context()
    return {id = 0xEC, manda = false, parent = nil, name = "Void"}
end

-- read data - no data should be reading 
function Void:read_data(stream, readfully)
    self:skip_data(stream)
    return self.data_size
end
-- -----------------------------------------------------------------------------


-- CRC-32 ----------------------------------------------------------------------
function CRC32:new()
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    return elem
end

function CRC32:get_context()
    return {id = 0xBF, manda = false, parent = nil, name = "CRC-32"}
end

function CRC32:validate_data_size()
    return self.data_size == 4
end
-- -----------------------------------------------------------------------------


-- EBML Dummy ------------------------------------------------------------------
function Dummy:new(dummy_id)
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    self.dummy_id = dummy_id
    return elem
end

function Dummy:get_context()
    return {id = 0xFF, manda = false, parent = nil, name = "Dummy"}
end

function Dummy:is_dummy()
    return true
end
-- -----------------------------------------------------------------------------



-- Export module
local module = {}
module.SCOPE_NO_DATA = SCOPE_NO_DATA
module.SCOPE_PARTIAL_DATA = SCOPE_PARTIAL_DATA
module.SCOPE_ALL_DATA = SCOPE_ALL_DATA
module.ELEM_LEVEL_GLOBAL = ELEM_LEVEL_GLOBAL
module.ELEM_LEVEL_CHILD = ELEM_LEVEL_CHILD
module.ELEM_LEVEL_SIBLING = ELEM_LEVEL_SIBLING
module.MAX_DATA_SIZE = MAX_DATA_SIZE

module.binary = ebml_binary
module.utf8 = ebml_utf8
module.string = ebml_string
module.uinteger = ebml_uinteger
module.integer = ebml_integer
module.float = ebml_float
module.date = ebml_date
module.master = ebml_master

module.EBML = EBML
module.EBMLVersion = EBMLVersion
module.EBMLReadVersion = EBMLReadVersion
module.EBMLMaxIDLength = EBMLMaxIDLength
module.EBMLMaxSizeLength = EBMLMaxSizeLength
module.DocType = DocType
module.DocTypeVersion = DocTypeVersion
module.DocTypeReadVersion = DocTypeReadVersion
module.DocTypeExtension = DocTypeExtension
module.DocTypeExtensionName = DocTypeExtensionName
module.DocTypeExtensionVersion = DocTypeExtensionVersion
module.Void = Void
module.CRC32 = CRC32
module.Dummy = Dummy

module.find_next_element = find_next_element


return module
