-- Lua Matroska Parser for parsing Matroska and WebM files
-- written by hubblec4

local ebml = require "ebml"
local mk = require "matroska"

-- constants
local DOCTYPE_MATROSKA = "matroska"
local DOCTYPE_WEBM = "webm"


-- get_timestamp: returns a time in HH:MM:SS:NS format
local function get_timestamp(ns_time, ns_len)
	if ns_len == nil then ns_len = 9 end -- HH:MM:SS.NS format
	local minus = ""
    if ns_time < 0 then
        minus = "-"
        ns_time = ns_time * (-1)
    end
	
	local seconds = ns_time / 1e9
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	
	if ns_len == 0 then -- HH:MM:SS format
		return string.format("%s%02d:%02d:%02d", minus, h, m, s)
	else
		local ns = ("%09d"):format(ns_time % 1e9)
		ns = ns:sub(1, ns_len)
		return ("%s%02d:%02d:%02d.%s"):format(minus, h, m, s, ns)
	end
end

-- get_nanosecs: returns an integer in nano seconds
local function get_nanosecs(timestamp) -- timestamp should be in HH:MM:SS:NS format
    local h, m, s, ns = string.match(timestamp .. "00000000", "(%d+):([0-5]%d):([0-5]%d)%.(%d%d%d%d%d%d%d%d%d)")
    if h == nil then return nil end
    return (h * 3600 + m * 60 + s) * 1000000000 + ns
end


-- -----------------------------------------------------------------------------
-- Matroska Parser -------------------------------------------------------------
-- -----------------------------------------------------------------------------

local Matroska_Parser = {
    -- path: file path
    path = "",

    -- file: a file stream, loaded with "io.open" for example
    file = nil,

    -- err_msg: contains an error string
    err_msg = "",

    -- is_valid: boolean read only, is the loaded file valid
    is_valid = false,

    -- is_webm: boolean read only, is the loaded file a WebM file
    is_webm = false,

    -- Matroska root element
    Segment = nil,

    -- Top-level elements for faster access
    SeekHead = nil,
    SeekHead2 = nil,
    Info = nil,
    Attachments = nil,
    Chapters = nil,
    Cues = nil,
    Tracks = nil,
    Tags = nil,

    -- useful element values
    timestamp_scale = 1000000, -- the global timestamp scale
    seg_uuid = nil, -- SegmentUUID as hex-string
    seg_duration = 0.0, -- Segment Duration from INFO/Duration element
}

-- Matroska Parser constructor
function Matroska_Parser:new(path, file, do_analyze)
    local elem = {}
    setmetatable(elem, self)
    self.__index = self
    elem.path = path
    elem.file = file

    -- Validate
    elem.is_valid, elem.err_msg = elem:_validate()

    -- Analyze, find all Top-Level elements
    -- do_analyze = false: means the user have to analyze manually
    if elem.is_valid and (do_analyze == nil or do_analyze == true) then
        elem.is_valid, elem.err_msg = elem:_analyze()
    end

    -- close file if invalid
    if not elem.is_valid then elem:close() end
    return elem
end

-- Get element from SeekHead
function Matroska_Parser:get_element_from_seekhead(elem_class)
    if self.SeekHead == nil then return nil end
    local seek = self.SeekHead:find_first_of(elem_class)
    -- no seek found in the first SeekHead
    if not seek then
        -- search in the second SeekHead if present
        if self.SeekHead2 ~= nil then
            seek = self.SeekHead2:find_first_of(elem_class)
        end
        if not seek then return nil end
    end

    self.file:seek("set", self.Segment:get_global_position(seek:location()))
    return ebml.find_next_element(self.file, {elem_class}, 0, 0 , false)
end

-- close: a method to clean some var's
function Matroska_Parser:close()
    if self.file ~= nil then
        self.file:close()
        self.file = nil
    end
end


-- Validate (private)
function Matroska_Parser:_validate()
    -- open file
    if not self.file then
        self.file = io.open(self.path, "rb")
        if not self.file then
            return false, "file couldn't be open"
        end
    end

    -- check if an EBML and Segment element is present and a valid DocType is used
    
    -- find EBML element
    local elem = ebml.find_next_element(self.file, {ebml.EBML}, 0, 0, false)
    if not elem then
        return false, "EBML element not found."
    end

    -- EBML element found -> parse and check DocType
    elem:read_data(self.file)
    local doc = elem:get_child(ebml.DocType).value
    if doc ~= DOCTYPE_MATROSKA and doc ~= DOCTYPE_WEBM then
        return false, "'"..doc.."' is not a valid DocType value"
    end

    -- find Segment, note there can be Void elements before
    local read_size = 0xFFFFFF
    elem = ebml.find_next_element(self.file, {mk.Segment}, read_size, -1, false)
    while elem do
        if elem:get_context().id == mk.Segment:get_context().id then
            self.Segment = elem
            return true, ""
        end
        -- elem is a Void
        elem:skip_data(self.file)
        read_size = read_size - (elem.data_size + elem.data_size_len + 1)
        if read_size <= 0 then
            break
        end

        -- find next element
        elem = ebml.find_next_element(self.file, {mk.Segment}, read_size, -1, false)
    end

    return false, "Segment element not found."
end


-- Analyze (private)
function Matroska_Parser:_analyze()
    -- find all Top-Level elements, exclude Clusters
    local run_byte = self.Segment.data_position
    local end_byte = 0
    local elem
    local level = 0
    local semantic = mk.Segment:get_semantic()
    local id
    local found_cluster = false

    if self.Segment.unknown_data_size then
        end_byte = self.file:seek("end")
        self.file:seek("set", run_byte)
    else
        end_byte = self.Segment:end_position()
    end

    -- loop Segment content
    while run_byte < end_byte do
        elem, level = ebml.find_next_element(self.file, semantic, end_byte - run_byte, level)

        if not elem then
            return false, "Analyze error: no next element found"
        end

        id = elem:get_context().id

        -- first SeekHead
        if id == mk.seekhead.SeekHead:get_context().id  then
            elem:read_data(self.file) -- parse fully
            self.SeekHead = elem

        -- Info
        elseif id == mk.info.Info:get_context().id  then
            self.Info = elem
            self:_parse_Info()

        -- Chapters
        elseif id == mk.chapters.Chapters:get_context().id  then
            elem:read_data(self.file) -- parse fully
            self.Chapters = elem

        -- Tracks
        elseif id == mk.tracks.Tracks:get_context().id  then
            elem:read_data(self.file) -- parse fully
            self.Tracks = elem

        -- Attachments
        elseif id == mk.attachs.Attachments:get_context().id  then
            elem:skip_data(self.file) -- skip data, parse later
            self.Attachments = elem

        -- Tags
        elseif id == mk.tags.Tags:get_context().id  then
            elem:read_data(self.file) -- parse fully
            self.Tags = elem

        -- first Cluster
        elseif id == mk.cluster.Cluster:get_context().id then
            found_cluster = true
            break

        -- hint: Cues are usually not before the first Cluster    

        else -- global elements or Dummy
            elem:skip_data(self.file) -- skip data
        end

        run_byte = elem:end_position()
    end

    -- no Cluster found, the end of the file has been reached
    if not found_cluster then return true, "" end

    -- search for a second SeekHead
    self.SeekHead2 = self:get_element_from_seekhead(mk.seekhead.SeekHead)
    if self.SeekHead2 then self.SeekHead2:read_data(self.file) end

    -- some elements are located after the Clusters
    -- and in some cases all Top-Level elements behind the Clusters
    -- use the SeekHeads to find the elements
    -- a SeekHead is maybe not alwyas present -> uses other technic TODO:

    if not self.Info then
        self.Info = self:get_element_from_seekhead(mk.info.Info)
        self:_parse_Info()
    end

    if not self.Attachments then
        self.Attachments = self:get_element_from_seekhead(mk.attachs.Attachments)
    end
    
    if not self.Chapters then
        self.Chapters = self:get_element_from_seekhead(mk.chapters.Chapters)
        if self.Chapters then self.Chapters:read_data(self.file) end
    end

    if not self.Cues then
        self.Cues = self:get_element_from_seekhead(mk.cues.Cues)
    end

    if not self.Tracks then
        self.Tracks = self:get_element_from_seekhead(mk.tracks.Tracks)
        if self.Tracks then self.Tracks:read_data(self.file) end
    end

    if not self.Tags then
        self.Tags = self:get_element_from_seekhead(mk.tags.Tags)
        if self.Tags then self.Tags:read_data(self.file) end
    end
    
    return true, ""
end

-- bin2hex (private) - converts binary data to a hex-string
function Matroska_Parser:_bin2hex(bin)
    local hex = "0x"
    for i = 1, #bin do
        hex = hex .. string.format("%02X", string.byte(bin, i))
    end
    return hex
end

-- Parse Info (private)
function Matroska_Parser:_parse_Info()
    if self.Info then
        self.Info:read_data(self.file) -- parse fully

        -- parse SegmentUUID
        self.seg_uuid = self.Info:find_child(mk.info.SegmentUUID)
        if self.seg_uuid then
            self.seg_uuid = self:_bin2hex(self.seg_uuid.value)
        end

        -- parse TimestampScale
        self.timestamp_scale = self.Info:get_child(mk.info.TimestampScale).value
        
        -- parse Duration
        self.seg_duration = self.Info:find_child(mk.info.Duration)
        if self.seg_duration then
            self.seg_duration = self:_segment_ticks_2_matroska_ticks(self.seg_duration.value)
        end
    end
end

-- segment_ticks_2_matroska_ticks (private)
function Matroska_Parser:_segment_ticks_2_matroska_ticks(segm_ticks, as_timestamp)
    -- All timestamp values in Matroska are expressed in multiples of a tick. They are usually stored as integers.
    -- formula: timestamp in nanoseconds = element value * TimestampScale -> element vaule = segm_ticks
    -- Info\Duration is stored as a floating-point
    if as_timestamp then
        return get_timestamp(math.floor(self.timestamp_scale * segm_ticks))
    end
    return math.floor(self.timestamp_scale * segm_ticks)
end

-- find_mtx_stats_tag (private): try to find a MKVToolNix stats tag
function Matroska_Parser:find_MTX_stats_tag(track)
    if self.Tags == nil then return nil end
    return self.Tags:find_Tag_byName(track, "_STATISTICS_TAGS")
end

-- video_duration: returns the duration of a video track in nanoseconds
function Matroska_Parser:get_video_duration(v_track)
    --[[ The Info\Duartion is a value which contains the longest duration of all tracks
         therefore is this value not really useful
         when MKVToolNix statistics tags are availible: there is a video duration with a millisec accuracy
         to get this value is very easy and fast
         without this stats tags we have to parse the Clusters to find the last video frame
         the last video frame timestamp plus it's frame duration is the video duration 
         ]]
    if v_track == nil then
        v_track = self:get_video(1) -- get first video
    elseif type(v_track) == "number" then
        v_track = self:get_video(v_track)
    end
    if v_track == nil then return nil end

    -- try first the MKVToolNix stats tags
    local stats = self:find_MTX_stats_tag(v_track)
    if stats then
        local timestamp = stats:find_SimpleTag_byName("DURATION")
        if timestamp then
            timestamp = timestamp:get_string()
            if timestamp then
                timestamp = get_nanosecs(timestamp)
                if timestamp then return timestamp end
            end
        end
    end

    -- TODO: use Clusters -> find a Cluster with the last frame for the track
    --local vid = v_track:get_child(mk.tracks.TrackUID).value
end

-- elem_to_string: generates a human readable string for an element
function Matroska_Parser:elem_to_string(elem, verbose)
    if elem == nil or type(elem.is_master) ~= "function" then return "" end
    local result = ""

    local function do_verbose(_e)
        result = result .. " (data position: " .. _e.data_position
            .. ", data size: " .. _e.data_size .. ")"
    end

    local function get_string(_elem, level)
        local prefix = "|"
        for i = 1, level do
            prefix = prefix .. " "
        end
        prefix = prefix .. "+ "

        if _elem:is_master() then
            result = result .. "\n" .. prefix .. _elem:get_context().name
            if verbose then do_verbose(_elem) end

            for _, e in ipairs(_elem.value) do
                get_string(e, level + 1)
            end

        elseif _elem:is_dummy() then
            result = result .. "\n" .. prefix .. "Dummy: dummyID " .. _elem.dummy_id
            if verbose then do_verbose(_elem) end

        else -- all other types
            result = result .. "\n" .. prefix .. _elem:get_context().name .. ": "

            local e_type = getmetatable(_elem.__index) -- get the ebml type

            -- string and utf8
            if e_type == ebml.utf8 or e_type == ebml.string or e_type == ebml.integer then
                result = result .. _elem.value

            -- integer
            elseif e_type == ebml.integer then
                -- elements with Matroska Ticks
                if _elem:is_class(mk.cluster.DiscardPadding) then
                    result = result .. get_timestamp(_elem.value)

                -- elements with Track Ticks --TODO: currently not fully supported
                elseif _elem:is_class(mk.cluster.ReferenceBlock) then
                    -- TrackTimestampScale is not taken into account for the moment -> default vaule is 1.0
                    result = result .. self:_segment_ticks_2_matroska_ticks(_elem.value, true)
                else
                    result = result .. _elem.value
                end


            -- uinteger
            elseif e_type == ebml.uinteger then
                -- elements with Segment Ticks
                if _elem:is_class(mk.cluster.Timestamp)
                or _elem:is_class(mk.cues.CueDuration) then
                    result = result .. self:_segment_ticks_2_matroska_ticks(_elem.value, true)

                -- elements with Matroska Ticks
                elseif _elem:is_class(mk.tracks.DefaultDuration)
                or _elem:is_class(mk.tracks.DefaultDecodedFieldDuration)
                or _elem:is_class(mk.tracks.SeekPreRoll)
                or _elem:is_class(mk.tracks.CodecDelay)
                or _elem:is_class(mk.chapters.ChapterTimeStart)
                or _elem:is_class(mk.chapters.ChapterTimeEnd)
                or _elem:is_class(mk.cues.CueTime)
                or _elem:is_class(mk.cues.CueRefTime) then
                    result = result .. get_timestamp(_elem.value)

                -- elements with Track Ticks --TODO: currently not fully supported
                elseif _elem:is_class(mk.cluster.BlockDuration) then
                    -- TrackTimestampScale is not taken into account for the moment -> default vaule is 1.0
                    result = result .. self:_segment_ticks_2_matroska_ticks(_elem.value, true)

                else
                    result = result .. _elem.value
                end

            -- float
            elseif e_type == ebml.float then
                if _elem:is_class(mk.info.Duration) then
                    result = result .. self:_segment_ticks_2_matroska_ticks(_elem.value, true)
                else
                    result = result .. _elem.value
                end

            -- date
            elseif e_type == ebml.date then
                result = result .. _elem:get_utc()

            else -- binary type
                -- print hex value for small binary data like UUIDs
                if #_elem.value < 17 then
                    result = result .. self:_bin2hex(_elem.value)

                else -- more than 16 Bytes, TODO: Adler32
                    result = result .. "binary data" -- for the moment
                end
            end

            if verbose then do_verbose(_elem) end
        end
    end

    get_string(elem, 0)
    return result
end

-- get_edition_name: returns String with the name(s) of the given edition
function  Matroska_Parser:get_edition_name(edition, language, all, noFallback)
    if edition == nil then return nil end
    if type(edition) == "number" then -- check edition is a number -> index
        if not self.Chapters then return nil end
        edition = self.Chapters:get_edition(edition)
    end
    --[[ language: string, BCP47
         all: boolean, all names of a language or all names if no language is set
    ]]
    local name_s = ""
    local lng, i, name
    local found_lang = false
    local first_simple = nil

    -- almost is the edition name stored in the Tags, the new EditionDisplay is not widly used
    if self.Tags then
        -- find the Tag with Name TITLE
        local tag = self.Tags:find_Tag_byName(edition, "TITLE")
        if tag then
            -- loop SimpleTags's
            local simple, idx = tag:find_child(mk.tags.SimpleTag)
            while simple do
                if simple:get_child(mk.tags.TagName).value == "TITLE" then
                    -- save the first SimpleTag
                    if first_simple == nil then first_simple = simple end

                    -- check language
                    if language ~= "" then
                        found_lang = false
                        -- check BCP47 first
                        lng = simple:find_child(mk.tags.TagLanguageBCP47)
                        if lng and lng.value == language then
                            found_lang = true
                        end
                        -- check IS0639_3 language
                        if not found_lang then
                            found_lang = simple:get_child(mk.tags.TagLanguage).value == language
                        end
                    end

                    -- get the name
                    if found_lang or language == "" then
                        if name_s == "" then
                            name_s = simple:get_string()
                        else
                            name = simple:get_string()
                            if name ~= "" then
                                name_s = name_s .. " || " .. name
                            end
                        end
                    end

                    -- finish if a name was found, and not all names was requested
                    if name_s ~= "" and all ~= true then return name_s end
                end
                simple, idx = tag:find_next_child(idx)
            end
        end
    end

    -- check EditionDisplay elements
    local display, idx = edition:find_child(mk.chapters.EditionDisplay)
    local first_display = display
    while display do
        if language ~= "" then
            found_lang = false

            -- check BCP47
            lng, i = edition:find_child(mk.chapters.EditionLanguageIETF)
            while lng do
                if lng.value == language then
                    found_lang = true
                    break
                end
                lng, i = edition:find_next_child(i)
            end
        end

        -- get the name    
        if found_lang or language == "" then
            if name_s == "" then
                name_s = display:get_child(mk.chapters.EditionString).value
            else
                name = display:get_child(mk.chapters.EditionString).value
                if name ~= "" then
                    name_s = name_s .. " || " .. name
                end
            end
        end

        -- finish if a name was found, and not all names was requested
        if name_s ~= "" and all ~= true then return name_s end
        
        display, idx = edition:find_next_child(idx)
    end

    if noFallback then return "" end
    
    -- no name found, check "first"-elements
    -- first SimpleTag
    if first_simple then
        name = first_simple:get_string()
        if name ~= "" then return name end
    end
    -- first EditionDisplay
    if first_display then
        return first_display:get_child(mk.chapters.EditionString).value
    end

    return ""
end

-- get_video: returns a video TrackEntry element
function Matroska_Parser:get_video(idx, uid)
    if self.Tracks then
        return self.Tracks:get_track(idx, uid, mk.tracks.TrackType_enum.video)
    end
    return nil
end

-- get_audio: returns a audio TrackEntry element
function Matroska_Parser:get_audio(idx, uid)
    if self.Tracks then
        return self.Tracks:get_track(idx, uid, mk.tracks.TrackType_enum.audio)
    end
    return nil
end

-- get_subtitle: returns a subtitle TrackEntry element
function Matroska_Parser:get_subtitle(idx, uid)
    if self.Tracks then
        return self.Tracks:get_track(idx, uid, mk.tracks.TrackType_enum.subtitle)
    end
    return nil
end

-- get_video_rotation: first returns a vaule from -180.0 to 180.0 or from 0 to 359 as integer
-- second returns: boolean, if the vaule is a native Matroska value
function Matroska_Parser:get_video_rotation(vid)
    -- vid is a video track index, can be nil -> means first video track
    -- Matroska has a native Element ProjectionPoseRoll (float): value range -180.0 to 180.0
    -- The Tags ROTATE is a widly used non official feature: values (0) 90 180 270
    -- ProjectionPoseRoll has a higher priority and Tags must be ignored
    -- a return value of 0 means no rotation

    local trk = self:get_video(vid) -- get the track entry
    if not trk then return 0 end -- no video found

    -- check ProjectionPoseRoll first
    local video = trk:find_child(mk.tracks.Video) -- find the video element
    if not video then return 0 end -- no video element found, should not happen

    -- find ProjectionPoseRoll
    local projection = video:find_child(mk.tracks.Projection)
    if projection then -- projection element found
        local poseroll = projection:find_child(mk.tracks.ProjectionPoseRoll)
        if poseroll then -- ProjectionPoseRoll element found
            return poseroll.value, true
        end
    end

    -- use non official Tags ROTATE
    if not self.Tags then return 0 end
    local tag = self.Tags:find_Tag_byName(trk, "ROTATE")
    if tag then
        local simple = tag:find_SimpleTag_byName("ROTATE") -- is defintiv present
        local val = tonumber(simple:get_string())
        if val and val > 0 and val < 360 then
            return val, false
        end
    end

    -- no rotation found
    return 0
end

-- get_title: returns String, if the Title element is not present an empty string returns
function Matroska_Parser:get_title()
    if self.Info == nil then return "" end
    local t = self.Info:find_child(mk.info.Title)
    if t == nil then return "" end

    return t.value
end


-- Matroska features -----------------------------------------------------------

-- Ordered chapters are used
function Matroska_Parser:ordered_chapters_are_used()
    if self.Chapters ~= nil then
        -- get the default edition and check if ordered chapters are used
        local def_edition = self.Chapters:get_default_edition()
        if def_edition
        and def_edition:get_child(mk.chapters.EditionFlagOrdered).value > 0 then
            if def_edition:find_child(mk.chapters.ChapterAtom) then
                return true
            end
        end
    end
    return false
end


-- Hard-Linking is used
function Matroska_Parser:hardlinking_is_used()
    -- check if the Hard-Linking is used
    -- retrun@1 : boolean - is used?
    -- return@2 SegmentUUID, return@3 PrevUUID, return@4 NextUUID

    -- WebM don't support Hard-Linking
    if self.is_webm then return false end

    -- check the UIDs
    local seg_id, prev_id, next_id = self:hardlinking_get_uids()

    -- no prev or next UID -> no Hard-Linking
    if prev_id == nil and next_id == nil then return false end

    -- Ordered Chapters or Soft-Linking overrides Hard-Linking
    -- check the Chapters
    if self:ordered_chapters_are_used() then return false end
    
    -- all is checked and Hard-Linking is used
    return true, seg_id, prev_id, next_id
end

-- Hard-Linking get UIDs
function Matroska_Parser:hardlinking_get_uids()
    -- check the UIDs
    if self.Info == nil then return end

    local prev_id = self.Info:find_child(mk.info.PrevUUID)
    if prev_id then prev_id = self:_bin2hex(prev_id.value) end
    
    local next_id = self.Info:find_child(mk.info.NextUUID)
    if next_id then next_id = self:_bin2hex(next_id.value) end

    return self.seg_uuid, prev_id, next_id
end



-- Export module ---------------------------------------------------------------
local module = {
    Matroska_Parser = Matroska_Parser,
    get_timestamp = get_timestamp
}
return module