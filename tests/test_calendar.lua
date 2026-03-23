local MiniTest = require("mini.test")
local expect = MiniTest.expect
local new_set = MiniTest.new_set

local calendar = require("womwiki.calendar")

local T = new_set()

--------------------------------------------------------------------------------
-- _days_in_month
--------------------------------------------------------------------------------

local dim = new_set()
T["_days_in_month"] = dim

dim["january has 31 days"] = function()
	expect.equality(calendar._days_in_month(2024, 1), 31)
end

dim["february has 28 days in common year"] = function()
	expect.equality(calendar._days_in_month(2023, 2), 28)
end

dim["february has 29 days in leap year"] = function()
	expect.equality(calendar._days_in_month(2024, 2), 29)
end

dim["february has 29 days in century leap year"] = function()
	expect.equality(calendar._days_in_month(2000, 2), 29)
end

dim["february has 28 days in century non-leap year"] = function()
	expect.equality(calendar._days_in_month(1900, 2), 28)
end

dim["april has 30 days"] = function()
	expect.equality(calendar._days_in_month(2024, 4), 30)
end

dim["june has 30 days"] = function()
	expect.equality(calendar._days_in_month(2024, 6), 30)
end

dim["july has 31 days"] = function()
	expect.equality(calendar._days_in_month(2024, 7), 31)
end

dim["august has 31 days"] = function()
	expect.equality(calendar._days_in_month(2024, 8), 31)
end

dim["september has 30 days"] = function()
	expect.equality(calendar._days_in_month(2024, 9), 30)
end

dim["november has 30 days"] = function()
	expect.equality(calendar._days_in_month(2024, 11), 30)
end

dim["december has 31 days"] = function()
	expect.equality(calendar._days_in_month(2024, 12), 31)
end

--------------------------------------------------------------------------------
-- _first_day_of_month
--------------------------------------------------------------------------------

local fdm = new_set()
T["_first_day_of_month"] = fdm

-- os.date wday: 1=Sunday, 2=Monday, ..., 7=Saturday

fdm["2024-01-01 is Monday (wday 2)"] = function()
	expect.equality(calendar._first_day_of_month(2024, 1), 2)
end

fdm["2024-09-01 is Sunday (wday 1)"] = function()
	expect.equality(calendar._first_day_of_month(2024, 9), 1)
end

fdm["2024-02-01 is Thursday (wday 5)"] = function()
	expect.equality(calendar._first_day_of_month(2024, 2), 5)
end

fdm["2023-01-01 is Sunday (wday 1)"] = function()
	expect.equality(calendar._first_day_of_month(2023, 1), 1)
end

fdm["2025-03-01 is Saturday (wday 7)"] = function()
	expect.equality(calendar._first_day_of_month(2025, 3), 7)
end

fdm["2024-07-01 is Monday (wday 2)"] = function()
	expect.equality(calendar._first_day_of_month(2024, 7), 2)
end

fdm["returns value between 1 and 7"] = function()
	-- Test a range of months to verify bounds
	for year = 2020, 2026 do
		for month = 1, 12 do
			local wday = calendar._first_day_of_month(year, month)
			expect.equality(wday >= 1 and wday <= 7, true)
		end
	end
end

fdm["2000-01-01 is Saturday (wday 7)"] = function()
	expect.equality(calendar._first_day_of_month(2000, 1), 7)
end

return T
