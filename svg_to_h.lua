local inspect = require("inspect")
local lfs = require("lfs")
local lpeg = require("lpeg")
local locale = lpeg.locale{}
local V, P, C, Cc, Cg, Ct, Cf, Carg, Cp, Cmt = lpeg.V, lpeg.P, lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Ct, lpeg.Cf, lpeg.Carg, lpeg.Cp, lpeg.Cmt
local any, alpha, ws = locale.print, locale.alpha, locale.space

local element

local function virtualize(subject, pos, t, start_tag, props, content_start, children, content_end, end_tag)
	end_tag = end_tag or start_tag
	local _children = {}
	table.insert(t, { start_tag, props, _children })
	element:match(subject:sub(content_start, content_end), 1, _children)
	if start_tag ~= end_tag then return false end
	return true, t
end

element = P{
	"element",
	element = Cmt(Carg(1) * Cg(V"balanced_tag" + V"void_tag"), virtualize) ^ 0,
	balanced_tag = V"start_tag" * Cp() * Ct((V"balanced_tag" + V"void_tag") ^ 0) * Cp() * V"end_tag" * ws ^ 0,
	void_tag = P"<" * V"tag_name" * V"props" * P"/>" * Cp() * Cc{} * Cp() * ws ^ 0,
	start_tag = P"<" * V"tag_name" * V"props" * P">" * ws ^ 0,
	end_tag = P"</" * V"tag_name" * P">",
	props = Cf(Ct"" * Cg(V"prop") ^ 0, rawset),
	prop = C(V"name") * P"=" * ((P"'" * C((any - P"'") ^ 0) * P"'") + P"\"" * C((any - P"\"") ^ 0) * P"\"") * ws ^ 0,
	tag_name = C(V"name") * ws ^ 0,
	name = alpha * (alpha + (P"-" * alpha ^ 1)) ^ 0,
}

local function map(arr, fn)
	local o = {}
	for i, v in ipairs(arr) do o[i] = fn(v) end

	return o
end

local serialize do
	local template = "%s: \"%s\","
	serialize = function(t)
		local str = "{"
		for k,v in pairs(t) do
			str = str .. template:format("[\"" .. k .. "\"]", type(v) == "table" and serialize(v) or v)
		end

		return str .. "}"
	end
end

local function generate(node, parent, state)
	state = state or {}
	local name, props, children = node[1], node[2], node[3]

	if name == "svg" or name == "g" then
		for _,child in ipairs(children) do
			table.insert(state, generate(child, node))
		end

		return state
	end

	if parent[1] == "g" then
		for k,v in pairs(parent[2]) do
			props[k] = props[k] or v
		end
	end

	if name == "path" then
		return ([[el.appendChild(svg["%s"]("%s", %s));]]):format(name, props.d, serialize(props));
	elseif name == "line" then
		return ([[el.appendChild(svg["%s"](%s, %s, %s, %s, %s));]]):format(name, props.x1, props.y1, props.x2, props.y2, serialize(props));
	elseif name == "rectangle" then
		return ([[el.appendChild(svg["rect"](%s, %s, %s, %s, %s));]]):format(props.x, props.y, props.width, props.height, serialize(props));
	elseif name == "ellipse" then
		return ([[el.appendChild(svg["%s"](%s, %s, %s, %s, %s));]]):format(name, props.cx, props.cy, props.rx * 2, props.ry * 2, serialize(props))
	elseif name == "circle" then
		return ([[el.appendChild(svg["%s"](%s, %s, %s, %s));]]):format(name, props.cx, props.cy, props.r * 2, serialize(props))
	elseif name == "polyline" or name == "polygon" then
		local points = P{
			"points",
			points = Ct(V"pair" * (V"ws" ^ 1 * V"pair") ^ 0),
			pair = Ct(C(V"float") * P"," * V"ws" ^ 0 * C(V"float")),
			float = V"digit" ^ 0 * P"." ^ -1 * V"digit" ^ 1,
			digit = lpeg.R"09",
			wd = lpeg.S"\t\r\n ",
		}
		return ([[el.appendChild(svg["%s"](%s, %s));]]):format(name == "polyline" and "linearPath" or "polygon", inspect(points:match(props.points)):gsub("%p", function(c) return c == "{" and "[" or c == "}" and "]" or c end), serialize(props));
	else
		return ([[el.appendChild(svg["%s"](%s));]]):format(name, serialize(props));
	end
end

local function stringify(t, str)
	str = str or ""

	for _, command in ipairs(t) do
		str = str .. (type(command) == "string" and command or stringify(command))
	end

	return str
end

local to_js = [[
import { h } from "hyperapp.js";
import rough from "rough.js";
import uuid from "uuid.js";

export default (props = {}) => {
	let proto;
	const new_props = {
		...props,
		key: props.key || uuid(),
		xmlns: "http://www.w3.org/2000/svg",
		viewBox: "-1 -1 37 37",
		width: (props.size || 1) * 16,
		height: (props.size || 1) * 16,
		oncreate: el => {
			const svg = rough.svg(el, {
				options: props.options || {
					roughness: 0.1,
					strokeWidth: 0.2,
					fillStyle: "solid",
				}
			});

			if (proto) {
				el.parentNode.replaceChild(proto.cloneNode(true), el);
			} else {
				%s
				proto = el;
			}
		},
	};
	delete new_props.options;

	return h("svg", new_props);
};]]

local i = 0
local j = 0

for f in lfs.dir(lfs.currentdir()) do
	if f:sub(-3) == "svg" then
		local svg = io.open(f):read("*a")
		local virtual = element:match(svg, 1, {})[1]

		if virtual then
			local js = assert(io.open(("%s.js"):format(f:sub(-3)), "w+"))
			js:write(to_js:format(stringify(generate(virtual))))
			js:close()
			i = i + 1
		else
			-- os.remove(f)
			print("to remove: " .. f)
			j = j + 1
		end
	end
end

print(i .. " written")
print(j .. " skipped")

os.exit()
