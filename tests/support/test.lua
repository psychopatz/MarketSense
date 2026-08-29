local Test = {}

local modRoot = os.getenv("MARKET_SENSE_TEST_MOD")
assert(modRoot and modRoot ~= "", "MARKET_SENSE_TEST_MOD is required")

local sharedRoot = modRoot .. "/common/media/lua/shared/"
local pathsAdded = false

function Test.addPackagePaths()
    if not pathsAdded then
        package.path = sharedRoot .. "?.lua;" .. package.path
        pathsAdded = true
    end
    return package.path
end

function Test.path(relative)
    relative = tostring(relative or "")
    assert(string.sub(relative, 1, 1) ~= "/", "test path must be relative")
    assert(not string.find(relative, "..", 1, true), "test path cannot traverse parents")
    return sharedRoot .. relative
end

function Test.load(relative)
    Test.addPackagePaths()
    return dofile(Test.path(relative))
end

function Test.read(relative)
    local handle = assert(io.open(Test.path(relative), "rb"), "cannot open test source")
    local source = handle:read("*a")
    handle:close()
    return source
end

function Test.equal(actual, expected, label)
    if actual ~= expected then
        error((label or "equal") .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual), 2)
    end
end

function Test.truthy(value, label)
    if not value then
        error((label or "truthy") .. ": expected truthy value", 2)
    end
    return value
end

function Test.falsy(value, label)
    if value then
        error((label or "falsy") .. ": expected falsy value", 2)
    end
end

function Test.contains(value, fragment, label)
    if not string.find(tostring(value or ""), tostring(fragment or ""), 1, true) then
        error((label or "contains") .. ": missing=" .. tostring(fragment), 2)
    end
end

function Test.finish(name)
    print(tostring(name or "test") .. ": ok")
    return true
end

Test.modRoot = modRoot
return Test
