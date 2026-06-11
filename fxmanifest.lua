fx_version("cerulean")
game("gta5")
lua54("yes")

name("wraiths-shops")
author("Wraith")
version("1.0.0")
description("Shop System")

shared_script("@ox_lib/init.lua")

shared_scripts({
	"config/shared.lua",
	"shared/hours.lua",
	"shared/locations.lua",
})

client_scripts({
	"@qbx_core/modules/playerdata.lua",
	"client/utils.lua",
	"client/nui.lua",
	"client/placement.lua",
	"client/manager.lua",
	"client/main.lua",
})

server_scripts({
	"server/storage.lua",
	"server/registry.lua",
	"server/bridge.lua",
	"server/manager.lua",
	"server/main.lua",
})

ui_page("web/build/index.html")

files({
	"config/shared.lua",
	"config/shops.lua",
	"data/shops.json",
	"shared/hours.lua",
	"shared/locations.lua",
	"client/bridge.lua",
	"client/debug.lua",
	"client/shops.lua",
	"client/targets.lua",
	"server/bridge.lua",
	"server/registry.lua",
	"server/storage.lua",
	"web/build/index.html",
	"web/build/**/*",
})
